from pathlib import Path
import tempfile
import unittest

from dotfiles_core.errors import ProtocolError
from dotfiles_core.native_protocol import arguments, finish
from dotfiles_core.native_workflow import NativeSession
from dotfiles_core.protocol import Request, Result, write_json


class AdapterFixture:
    def __init__(self, data):
        self.data = data
        self.calls = []

    def invoke(self, operation, context):
        self.calls.append((operation, context))
        return Result(operation, 0, self.data)


class NativeWorkflowTests(unittest.TestCase):
    def test_stage_result_requires_structured_code_and_reason(self):
        for data in ({}, {'exit_code': 0}, {'exit_code': True, 'reason': ''},
                     {'exit_code': 256, 'reason': ''}, {'exit_code': 0, 'reason': []}):
            with self.subTest(data=data), self.assertRaises(ProtocolError):
                NativeSession(AdapterFixture(data), '/context').execute('configuration', Path('report'), Path('metadata'), Path('log'))
        adapter = AdapterFixture({'exit_code': 130, 'reason': ''})
        result = NativeSession(adapter, '/context').execute('configuration', Path('report'), Path('metadata'), Path('log'))
        self.assertEqual(result.exit_code, 130)
        self.assertEqual(adapter.calls[0][1]['directory'], '/context')

    def test_windows_signed_process_codes_reach_existing_report_policy(self):
        for code in (-1978335212, -0x80000000, 0xffffffff):
            adapter = AdapterFixture({'exit_code': code, 'reason': 'native failure'})
            result = NativeSession(adapter, '', 'windows').execute('packages', Path('report'), Path('metadata'), Path('log'))
            self.assertEqual(result.exit_code, code)
        for code in (-0x80000001, 0x100000000):
            with self.assertRaises(ProtocolError):
                NativeSession(AdapterFixture({'exit_code': code, 'reason': ''}), '', 'windows').execute(
                    'packages', Path('report'), Path('metadata'), Path('log'))

    def test_native_boundary_rejects_unknown_actions_and_preserves_literal_paths(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            request, output, result, payload = [root / name for name in ('request', 'output', 'result', 'payload')]
            context = dict(directory='/context 中文', action='configuration', report='literal $() report',
                           metadata='metadata', log='log', style='unix', native_context={})
            write_json(request, Request('workflow-stage', context).document())
            arguments(request, output, 'unix')
            self.assertEqual(output.read_bytes().decode().split('\0')[:-1],
                             ['workflow-stage', '/context 中文', 'configuration', 'literal $() report', 'metadata', 'log'])
            payload.write_text('75')
            finish(request, result, 0, payload, 'unix')
            self.assertEqual(Result.read(result, 'workflow-stage').data['exit_code'], 75)
            payload.write_text('not a result')
            with self.assertRaises(ProtocolError):
                finish(request, result, 0, payload, 'unix')
            context['action'] = 'arbitrary-command'
            write_json(request, Request('workflow-stage', context).document())
            with self.assertRaises(ProtocolError):
                arguments(request, output, 'unix')


if __name__ == '__main__':
    unittest.main()
