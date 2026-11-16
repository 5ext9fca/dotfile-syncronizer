import unittest

from dotfiles_core.contracts import Contract
from dotfiles_core.errors import AdapterError, ProtocolError
from dotfiles_core.install_execution import execute
from dotfiles_core.install_planning import prepare


class InstallationExecutionTests(unittest.TestCase):
    def test_damaged_adapter_result_fails_and_blocks(self):
        for resume in (False, True):
            snapshots, calls = [], []
            def damaged(item):
                calls.append(item['id'])
                raise ProtocolError('Damaged adapter result')
            result = execute(self.items(), dry=False, resume=resume, install=damaged,
                             observe=damaged, publish=snapshots.append, emit=lambda text: None)
            self.assertEqual(result.exit_code, 65)
            self.assertEqual(calls, ['first'])
            rows = Contract.load('install-result').read(snapshots[-1])
            self.assertEqual([row['status'] for row in rows], ['failed', 'blocked', 'blocked'])
            self.assertEqual(rows[0]['reason'], 'exit-65')
            if resume:
                self.assertEqual(rows[0]['decision_reason'], '')

    def test_native_optional_fields_keep_empty_defaults(self):
        received = []
        item = {'schema_version': Contract.load('install-plan').version, 'id': 'tool',
                'method': 'winget', 'action': 'install', 'reason': 'requested'}
        result = execute([item], dry=True, resume=False, install=received.append,
                         observe=lambda value: value, emit=lambda text: None)
        self.assertEqual(result.exit_code, 0)
        self.assertEqual(received[0]['source_origin'], '')
        self.assertEqual(received[0]['detected_paths'], '')

    def items(self):
        return prepare([dict(id=name, method='winget', detected_paths='["old"]') for name in ('first', 'second', 'third')], False, False)

    def test_command_success_does_not_trigger_post_install_probe(self):
        installed, snapshots = [], []
        def forbidden(item):
            self.fail('post-install observation is outside the contract')
        result = execute(self.items(), dry=False, resume=False, install=lambda item: installed.append(item['id']),
                         observe=forbidden, publish=snapshots.append, emit=lambda text: None)
        self.assertEqual(installed, ['first', 'second', 'third'])
        self.assertEqual(result.exit_code, 0)
        rows = Contract.load('install-result').read(snapshots[-1])
        self.assertEqual([row['status'] for row in rows], ['success'] * 3)
        self.assertEqual(Contract.load('install-result').read(snapshots[0])[0]['status'], 'running')

    def test_resume_rechecks_and_blocks_after_probe_error(self):
        observed, installed, snapshots = [], [], []
        def observe(item):
            observed.append(item['id'])
            if item['id'] == 'second':
                raise AdapterError('probe failed', 42)
            return {**item, 'action': 'skip', 'reason': 'resume-already-installed'}
        result = execute(self.items(), dry=False, resume=True, install=installed.append, observe=observe,
                         publish=snapshots.append, emit=lambda text: None)
        self.assertEqual(observed, ['first', 'second'])
        self.assertEqual(installed, [])
        self.assertEqual(result.exit_code, 42)
        schema = Contract.load('install-result')
        rows = schema.read(snapshots[-1])
        self.assertEqual([row['status'] for row in rows], ['skipped', 'failed', 'blocked'])
        self.assertEqual(rows[1]['reason'], 'exit-42')
        self.assertEqual(rows[2]['decision_reason'], '')
        self.assertEqual(schema.read(snapshots[0])[0]['reason'], 'checking-current-state')

    def test_install_failure_and_dry_run(self):
        installed = []
        def install(item):
            installed.append(item['id'])
            raise AdapterError('interrupted', 130)
        result = execute(self.items(), dry=False, resume=False, install=install, observe=lambda item: item,
                         emit=lambda text: None)
        self.assertEqual(result.exit_code, 130)
        self.assertEqual(installed, ['first'])
        schema = Contract.load('install-result')
        rows = schema.read(schema.from_rows('\n'.join(result.rows)))
        self.assertEqual([row['status'] for row in rows], ['interrupted', 'blocked', 'blocked'])
        result = execute(self.items(), dry=True, resume=False, install=lambda item: None, observe=lambda item: item,
                         emit=lambda text: None)
        rows = schema.read(schema.from_rows('\n'.join(result.rows)))
        self.assertEqual([row['status'] for row in rows], ['planned'] * 3)
