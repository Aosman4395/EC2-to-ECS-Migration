"""Read-only post-apply checks. Never changes listener weights or creates orders."""
import json
import os
import subprocess
import time
import urllib.request


def aws(*args):
    return json.loads(subprocess.check_output(['aws', *args, '--output', 'json'], text=True))


def targets_ready(descriptions):
    # An empty target group must never pass verification.
    return bool(descriptions) and all(
        item['TargetHealth']['State'] == 'healthy' for item in descriptions
    )


def main():
    groups = {
        'legacy': os.environ['LEGACY_TARGET_GROUP_ARN'],
        'ecs': os.environ['ECS_TARGET_GROUP_ARN'],
    }
    deadline = time.monotonic() + 900
    while True:
        results = {
            name: aws('elbv2', 'describe-target-health', '--target-group-arn', arn)['TargetHealthDescriptions']
            for name, arn in groups.items()
        }
        print(json.dumps(results), flush=True)
        if all(targets_ready(items) for items in results.values()):
            break
        if time.monotonic() >= deadline:
            raise SystemExit('Targets did not become healthy within 15 minutes. Inspect startup and application logs.')
        time.sleep(20)

    listener = aws('elbv2', 'describe-listeners', '--listener-arns', os.environ['LISTENER_ARN'])['Listeners'][0]
    forward = next(action['ForwardConfig'] for action in listener['DefaultActions'] if action['Type'] == 'forward')
    weights = {group['TargetGroupArn']: group['Weight'] for group in forward['TargetGroups']}
    # This infrastructure-only phase must not cut over.
    if weights.get(groups['legacy']) != 100 or weights.get(groups['ecs']) != 0:
        raise SystemExit('Expected initial 100/0 routing. No automatic weight change was attempted.')

    with urllib.request.urlopen(os.environ['APPLICATION_URL'] + '/ready', timeout=15) as response:
        ready = json.load(response)
    if ready != {'status': 'ready', 'storage': 'memory'}:
        raise SystemExit(f'Unexpected initial production readiness response: {ready}')
    message = 'Production ALB verified: both target groups healthy; routing remains legacy=100, ECS=0.'
    print(message)
    summary = os.environ.get('GITHUB_STEP_SUMMARY')
    if summary:
        with open(summary, 'a') as output:
            output.write(message + '\n')


if __name__ == '__main__':
    main()
