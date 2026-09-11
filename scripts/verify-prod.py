"""Read-only post-apply checks. Never changes listener weights or creates orders."""
import argparse
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


def main(destination="legacy", preflight=False, destination_only=False):
    groups = {
        'legacy': os.environ['LEGACY_TARGET_GROUP_ARN'],
        'ecs': os.environ['ECS_TARGET_GROUP_ARN'],
    }
    checked_groups = {destination: groups[destination]} if preflight or destination_only else groups
    deadline = time.monotonic() + 900
    while True:
        results = {
            name: aws('elbv2', 'describe-target-health', '--target-group-arn', arn)['TargetHealthDescriptions']
            for name, arn in checked_groups.items()
        }
        print(json.dumps(results), flush=True)
        if all(targets_ready(items) for items in results.values()):
            break
        if time.monotonic() >= deadline:
            raise SystemExit('Targets did not become healthy within 15 minutes. Inspect startup and application logs.')
        time.sleep(20)

    if preflight:
        print(f'Destination {destination} has healthy targets.')
        return

    listener = aws('elbv2', 'describe-listeners', '--listener-arns', os.environ['LISTENER_ARN'])['Listeners'][0]
    forward = next(action['ForwardConfig'] for action in listener['DefaultActions'] if action['Type'] == 'forward')
    weights = {group['TargetGroupArn']: group['Weight'] for group in forward['TargetGroups']}
    expected = {groups['legacy']: 100 if destination == 'legacy' else 0,
                groups['ecs']: 100 if destination == 'ecs' else 0}
    if weights != expected:
        raise SystemExit(f'Unexpected listener weights: {weights}; expected {expected}')

    # Allow a short propagation interval after the listener update.
    expected_storage = 'postgres' if destination == 'ecs' else 'memory'
    deadline = time.monotonic() + 120
    while True:
        try:
            with urllib.request.urlopen(os.environ['APPLICATION_URL'] + '/ready', timeout=15) as response:
                ready = json.load(response)
            if ready == {'status': 'ready', 'storage': expected_storage}:
                break
        except (OSError, ValueError) as error:
            ready = str(error)
        if time.monotonic() >= deadline:
            raise SystemExit(f'Unexpected production readiness response: {ready}')
        time.sleep(5)
    message = f'Production verified: checked targets healthy; routing destination={destination}, storage={expected_storage}.'
    print(message)
    summary = os.environ.get('GITHUB_STEP_SUMMARY')
    if summary:
        with open(summary, 'a') as output:
            output.write(message + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--destination', choices=['legacy', 'ecs'], default='legacy')
    parser.add_argument('--preflight', action='store_true')
    parser.add_argument('--destination-only', action='store_true')
    args = parser.parse_args()
    main(args.destination, args.preflight, args.destination_only)
