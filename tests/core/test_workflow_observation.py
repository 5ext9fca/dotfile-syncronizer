from pathlib import Path
import tempfile
import unittest

from dotfiles_core.errors import ProtocolError
from dotfiles_core.workflow_observation import arguments, result, validate


class WorkflowObservationTests(unittest.TestCase):
    def test_operation_allowlist_and_literal_projection(self):
        context = dict(style='unix', query='command-present', arguments=['literal $command'], native_context={})
        self.assertEqual(arguments(context, 'unix'), ['workflow-query', 'command-present', 'literal $command', '', ''])
        for change in ({'query': 'arbitrary-command'}, {'arguments': ['a', 'b']},
                       {'arguments': ['a\0b']}, {'native_context': {'source': 'code'}}):
            with self.subTest(change=change), self.assertRaises(ProtocolError):
                validate({**context, **change})
        with self.assertRaises(ProtocolError):
            arguments(context, 'windows')

    def test_result_shapes_reject_partial_or_unexpected_output(self):
        with tempfile.TemporaryDirectory() as directory:
            payload = Path(directory) / 'result'
            context = dict(style='unix', query='command-present', arguments=['tool'], native_context={})
            payload.write_text('1\n')
            self.assertEqual(result(context, payload), {'value': True})
            payload.write_text('true')
            with self.assertRaises(ProtocolError):
                result(context, payload)
            context = dict(style='windows', query='wsl-plan', arguments=[], native_context={})
            payload.write_text('{"Arguments":[],"Text":[],"HostReport":"中文 path"}', encoding='utf-8')
            self.assertEqual(result(context, payload)['value']['HostReport'], '中文 path')
            payload.write_text('{"Arguments":[],"Text":"not an array","HostReport":""}')
            with self.assertRaises(ProtocolError):
                result(context, payload)
            context = dict(style='unix', query='shell-account', arguments=['macos', 'user'], native_context={})
            payload.write_text('unexpected output')
            with self.assertRaises(ProtocolError):
                result(context, payload)


if __name__ == '__main__':
    unittest.main()
