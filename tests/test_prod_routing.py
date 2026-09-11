import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('routing', Path(__file__).resolve().parents[1] / 'scripts/prod-routing.py')
routing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(routing)


def plan():
    before = {'port': 80, 'default_action': [{'type': 'forward', 'forward': [{'target_group': [
        {'arn': 'legacy', 'weight': 100}, {'arn': 'ecs', 'weight': 0}
    ]}]}]}
    after = copy.deepcopy(before)
    groups = after['default_action'][0]['forward'][0]['target_group']
    groups[0]['weight'], groups[1]['weight'] = 0, 100
    return {
        'planned_values': {'outputs': {'routing_weights': {'value': {'legacy': 0, 'ecs': 100}}}},
        'resource_changes': [{'mode': 'managed', 'address': 'module.alb.aws_lb_listener.http',
                              'change': {'actions': ['update'], 'before': before, 'after': after}}],
    }


class RoutingTests(unittest.TestCase):
    def test_first_deployment_defaults_to_legacy(self):
        self.assertEqual(routing.current_weights({}), {'legacy': 100, 'ecs': 0})

    def test_later_infra_preserves_ecs(self):
        outputs = {'routing_weights': {'value': {'legacy': 0, 'ecs': 100}}}
        self.assertEqual(routing.current_weights(outputs), {'legacy': 0, 'ecs': 100})
        routing.check_plan(plan(), routing.current_weights(outputs))

    def test_missing_output_fails_instead_of_resetting(self):
        with self.assertRaises(KeyError):
            routing.current_weights({'application_url': {'value': 'example'}})

    def test_weight_only_cutover_passes(self):
        routing.check_plan(plan(), {'legacy': 0, 'ecs': 100}, cutover=True)

    def test_rollback_passes(self):
        value = plan()
        change = value['resource_changes'][0]['change']
        change['before'], change['after'] = change['after'], change['before']
        value['planned_values']['outputs']['routing_weights']['value'] = {'legacy': 100, 'ecs': 0}
        routing.check_plan(value, {'legacy': 100, 'ecs': 0}, cutover=True)

    def test_replacement_rejected(self):
        value = plan()
        value['resource_changes'][0]['change']['actions'] = ['delete', 'create']
        with self.assertRaises(ValueError):
            routing.check_plan(value, {'legacy': 0, 'ecs': 100}, cutover=True)

    def test_ec2_change_rejected(self):
        value = plan()
        value['resource_changes'][0]['address'] = 'module.legacy.aws_instance.legacy'
        with self.assertRaises(ValueError):
            routing.check_plan(value, {'legacy': 0, 'ecs': 100}, cutover=True)

    def test_other_listener_changes_rejected(self):
        value = plan()
        value['resource_changes'][0]['change']['after']['port'] = 443
        with self.assertRaises(ValueError):
            routing.check_plan(value, {'legacy': 0, 'ecs': 100}, cutover=True)

    def test_infra_cannot_reset_ecs_routing(self):
        with self.assertRaises(ValueError):
            routing.check_plan(plan(), {'legacy': 100, 'ecs': 0})

    def test_repeated_cutover_noop_passes(self):
        value = plan()
        value['resource_changes'] = []
        routing.check_plan(value, {'legacy': 0, 'ecs': 100}, cutover=True)


if __name__ == '__main__':
    unittest.main()
