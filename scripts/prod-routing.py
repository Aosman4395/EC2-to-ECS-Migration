"""Preserve prod routing from its existing Terraform state and constrain cutover plans."""
import argparse
import copy
import json
import os
import subprocess
from pathlib import Path


def validate_weights(weights):
    if weights not in ({'legacy': 100, 'ecs': 0}, {'legacy': 0, 'ecs': 100}):
        raise ValueError('Only full legacy or ECS routing is supported by these workflows.')
    return weights


def current_weights(outputs):
    if not outputs:
        return {'legacy': 100, 'ecs': 0}  # First provisioning only.
    return validate_weights(outputs['routing_weights']['value'])


def without_weights(listener):
    result = copy.deepcopy(listener)
    for action in result.get('default_action', []):
        for forward in action.get('forward', []):
            for group in forward.get('target_group', []):
                group.pop('weight', None)
            forward['target_group'] = sorted(forward.get('target_group', []), key=lambda g: g['arn'])
    return result


def check_plan(plan, expected, cutover=False):
    validate_weights(expected)
    actual = plan['planned_values']['outputs']['routing_weights']['value']
    if actual != expected:
        raise ValueError(f'Unexpected planned routing: {actual}; expected {expected}')
    if not cutover:
        return
    for resource in plan.get('resource_changes', []):
        if resource['mode'] != 'managed' or resource['change']['actions'] == ['no-op']:
            continue
        change = resource['change']
        if resource['address'] != 'module.alb.aws_lb_listener.http' or change['actions'] != ['update']:
            raise ValueError(f'Unrelated change: {resource["address"]}. Apply prod infrastructure first.')
        if without_weights(change['before']) != without_weights(change['after']):
            raise ValueError('Cutover may change only listener target-group weights.')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('operation', choices=['preserve', 'export', 'check'])
    parser.add_argument('--plan')
    parser.add_argument('--cutover', action='store_true')
    args = parser.parse_args()
    if args.operation == 'check':
        check_plan(json.loads(Path(args.plan).read_text()), {
            'legacy': int(os.environ['TF_VAR_legacy_weight']),
            'ecs': int(os.environ['TF_VAR_ecs_weight']),
        }, args.cutover)
        print('Routing plan checks passed.')
        return
    outputs = json.loads(subprocess.check_output(['terraform', 'output', '-json'], text=True))
    weights = current_weights(outputs)
    if args.operation == 'preserve':
        with open(os.environ['GITHUB_ENV'], 'a') as env:
            for name, value in weights.items():
                env.write(f'TF_VAR_{name}_weight={value}\n')
        print(f'Preserving recorded routing: {weights}')
    else:
        with open(os.environ['GITHUB_ENV'], 'a') as env:
            for name in ['application_url', 'legacy_target_group_arn', 'ecs_target_group_arn', 'listener_arn']:
                env.write(f'{name.upper()}={outputs[name]["value"]}\n')
        with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
            output.write(f'expected_backend={"ecs" if weights["ecs"] == 100 else "legacy"}\n')


if __name__ == '__main__':
    main()
