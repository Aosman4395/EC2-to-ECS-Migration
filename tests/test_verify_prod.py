import importlib.util
import io
import os
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('verify_prod', Path(__file__).resolve().parents[1] / 'scripts/verify-prod.py')
verify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify)


def target(state):
    return {'TargetHealth': {'State': state}}


class ProductionVerificationTests(unittest.TestCase):
    def test_empty_targets_fail(self):
        self.assertFalse(verify.targets_ready([]))

    def test_mixed_targets_fail(self):
        self.assertFalse(verify.targets_ready([target('healthy'), target('unhealthy')]))

    def test_healthy_targets_pass(self):
        self.assertTrue(verify.targets_ready([target('healthy')]))

    def run_verification(self, legacy_weight=100, ecs_weight=0, backend='memory', destination='legacy'):
        responses = [
            {'TargetHealthDescriptions': [target('healthy')]},
            {'TargetHealthDescriptions': [target('healthy')]},
            {'Listeners': [{'DefaultActions': [{'Type': 'forward', 'ForwardConfig': {
                'TargetGroups': [
                    {'TargetGroupArn': 'legacy', 'Weight': legacy_weight},
                    {'TargetGroupArn': 'ecs', 'Weight': ecs_weight},
                ]
            }}]}]},
        ]
        env = {'LEGACY_TARGET_GROUP_ARN': 'legacy', 'ECS_TARGET_GROUP_ARN': 'ecs',
               'LISTENER_ARN': 'listener', 'APPLICATION_URL': 'http://example.invalid'}
        body = ('{"status":"ready","storage":"' + backend + '"}').encode()
        with patch.dict(os.environ, env, clear=True), patch.object(verify, 'aws', side_effect=responses), \
                patch.object(verify.urllib.request, 'urlopen', return_value=io.BytesIO(body)), \
                patch.object(verify.time, 'monotonic', side_effect=[0, 0, 121]):
            verify.main(destination=destination)

    def test_initial_routing_passes(self):
        self.run_verification()

    def test_unexpected_cutover_fails(self):
        with self.assertRaises(SystemExit):
            self.run_verification(0, 100)

    def test_ecs_cutover_passes(self):
        self.run_verification(0, 100, 'postgres', 'ecs')

    def test_preflight_only_checks_destination(self):
        with patch.dict(os.environ, {'LEGACY_TARGET_GROUP_ARN': 'legacy', 'ECS_TARGET_GROUP_ARN': 'ecs'}), \
                patch.object(verify, 'aws', return_value={'TargetHealthDescriptions': [target('healthy')]}) as aws, \
                patch.object(verify.urllib.request, 'urlopen') as http:
            verify.main(destination='legacy', preflight=True)
        self.assertEqual(aws.call_count, 1)
        self.assertEqual(aws.call_args.args[-1], 'legacy')
        http.assert_not_called()

    def test_wrong_backend_fails(self):
        with self.assertRaises(SystemExit):
            self.run_verification(backend='postgres')


if __name__ == '__main__':
    unittest.main()
