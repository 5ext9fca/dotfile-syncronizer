import os
import unittest

from dotfiles_core.apply_execution import execute, summaries
from dotfiles_core.errors import AdapterError, ProtocolError
from dotfiles_core.stage_results import read_stage
from dotfiles_core.contracts import Contract


def row(target, action='copy', reason='new'):
    return dict(component='tool', action=action, source='/source', target=target,
                backup='', before='absent', source_state='1:2:f:hash', root='/',
                privilege='none', reason=reason, schema_version='1')


class Operations:
    def __init__(self):
        self.documents = {}
        self.calls = []
        self.failure = None

    def validate_outputs(self, *args):
        self.calls.append('validate')

    def exists(self, path):
        return path in self.documents

    is_file = exists

    def read(self, path):
        return self.documents[path]

    def publish(self, path, text, mode='replace'):
        self.calls.append(('publish', path, mode))
        if mode == 'create' and path in self.documents:
            raise AdapterError('occupied', 1)
        self.documents[path] = text

    def start(self, session):
        self.calls.append(('start', session))

    def transaction(self, row, journal, sequence):
        self.calls.append(('transaction', row['target'], sequence))
        if self.failure:
            raise self.failure

    def preview(self, row):
        self.calls.append(('preview', row['target']))


class ApplyExecutionTests(unittest.TestCase):
    def test_failure_blocks_work_but_preserves_skip_and_reports(self):
        for style, failure, code in [('unix', AdapterError('failed', 23), 23),
                                     ('windows', AdapterError('failed', 23), 1),
                                     ('unix', ProtocolError('missing result'), 65)]:
            with self.subTest(style=style, code=code):
                native = Operations()
                native.failure = failure
                actual = execute([row('/a'), row('/b', 'skip'), row('/c')], '/session', False,
                                 '/report', '/metadata', style, native, emit=lambda _: None)
                self.assertEqual(actual, code)
                records = Contract.load('apply-result').read(native.documents['/report'])
                self.assertEqual([r['status'] for r in records], ['failed', 'skipped', 'blocked'])
                self.assertEqual([c for c in native.calls if isinstance(c, tuple) and c[0] == 'transaction'],
                                 [('transaction', '/a', 1)])
                values = {r['key']: r['value'] for r in read_stage(native.documents['/metadata'])}
                self.assertEqual(values['exit_code'], str(code))
                filename = 'journal.tsv' if style == 'unix' else 'journal.jsonl'
                self.assertEqual(values['recovery_journal'], os.path.join('/session', filename))
                self.assertEqual(native.calls[0:2], ['validate', ('publish', '/metadata', 'create')])

    def test_dry_run_and_empty_plan_do_not_create_journal(self):
        for rows, dry in [([row('/a')], True), ([], False)]:
            native = Operations()
            self.assertEqual(execute(rows, '/session', dry, '/report', '', 'unix', native,
                                     emit=lambda _: None), 0)
            self.assertFalse(any(c[0] in ('start', 'transaction') for c in native.calls if isinstance(c, tuple)))

    def test_platform_summaries_retain_directory_and_replace_semantics(self):
        rows = [row('/a', 'mkdir', 'replace') | {'status': 'success', 'elapsed_seconds': '2'},
                row('/b') | {'status': 'planned', 'elapsed_seconds': '1'}]
        self.assertEqual(summaries(rows, 'unix'), ['tool: new=1 replaced=0 skipped=0 directories=1 failed=0 blocked=0 elapsed=3s'])
        self.assertEqual(summaries(rows, 'windows'), ['tool: new=1 replaced=1 skipped=0 failed=0 blocked=0 elapsed=3s'])

    def test_existing_metadata_is_validated_before_session_creation(self):
        native = Operations()
        native.documents['/metadata'] = 'corrupt'
        with self.assertRaises(Exception):
            execute([row('/a')], '/session', False, '', '/metadata', 'unix', native)
        self.assertEqual(native.calls, ['validate'])
