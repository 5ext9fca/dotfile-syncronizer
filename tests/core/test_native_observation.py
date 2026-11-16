import unittest

from dotfiles_core.errors import AdapterError, ProtocolError
from dotfiles_core.native_observation import NativeObservation
from dotfiles_core.protocol import Result


class FakeObservationAdapter:
    def __init__(self, answers):
        self.answers = answers
        self.calls = []

    def invoke(self, operation, context):
        self.calls.append((operation, context))
        value = self.answers[operation]
        if isinstance(value, Exception):
            raise value
        return Result(operation, 0, value)


class NativeObservationTests(unittest.TestCase):
    def test_discovery_evidence_and_no_package_queries(self):
        adapter = FakeObservationAdapter({'discovery-path': {'path': '/中文/tool'}})
        item = {'id': 'tool', 'method': 'apt', 'discovery': 'manual:file:home:tool'}
        result = NativeObservation(adapter, '', 'unix').observe(item, 'normal')
        self.assertEqual(result['action'], 'skip')
        self.assertEqual(result['detected_method'], 'manual')
        self.assertEqual(result['detected_paths'], '["/中文/tool"]')
        self.assertEqual([call[0] for call in adapter.calls], ['discovery-path'])
        adapter.answers['discovery-path'] = {'path': ''}
        result = NativeObservation(adapter, '', 'unix').observe(result, 'resume')
        self.assertEqual(result['action'], 'install')
        self.assertEqual(result['reason'], 'resume-recheck-required')
        self.assertEqual(result['detected_paths'], '')
        self.assertEqual(result['decision_reason'], 'no-discovery-match')

    def test_command_fallback_and_environment_gate(self):
        adapter = FakeObservationAdapter({'install-state': {'state': ''}, 'install-command-probe': {'present': True}})
        item = {'id': 'tool', 'method': 'script', 'probe_command': 'tool'}
        result = NativeObservation(adapter, 'context', 'unix', '/policy').observe(item, 'resume')
        self.assertEqual(result['action'], 'skip')
        self.assertEqual(result['state'], 'present')
        self.assertEqual(result['reason'], 'resume-already-installed')
        self.assertTrue(all(context['policy_path'] == '/policy' for _, context in adapter.calls))
        adapter.calls.clear()
        result['reason'] = 'provided-by-host:host'
        self.assertEqual(NativeObservation(adapter, '', 'unix').observe(result, 'resume'), result)
        self.assertEqual(adapter.calls, [])

    def test_windows_inventory_and_unix_docker_target_check(self):
        adapter = FakeObservationAdapter({'install-state': {'state': ''}, 'install-target-check': {}})
        result = NativeObservation(adapter, {}, 'windows').observe({'id': 'tool', 'method': 'winget', 'probe_command': 'missing'}, 'resume')
        self.assertEqual(result['reason'], 'resume-recheck-required')
        self.assertEqual(len(adapter.calls), 1)
        NativeObservation(adapter, '', 'unix').observe({'id': 'docker', 'method': 'docker-ce'}, 'normal')
        self.assertEqual(adapter.calls[-1][0], 'install-target-check')
        adapter.answers['install-state'] = AdapterError('probe failed', 42)
        with self.assertRaises(AdapterError) as error:
            NativeObservation(adapter, '', 'unix').observe({'id': 'tool', 'method': 'apt'}, 'normal')
        self.assertEqual(error.exception.exit_code, 42)
        adapter.answers['install-state'] = {'state': [], 'extra': True}
        with self.assertRaises(ProtocolError):
            NativeObservation(adapter, '', 'unix').observe({'id': 'tool', 'method': 'apt'}, 'normal')
