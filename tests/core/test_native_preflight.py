from pathlib import Path
import os
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

from dotfiles_core.apply_planning import Entry, Paths
from dotfiles_core.errors import ProtocolError
from dotfiles_core.install_config import ROOT
from dotfiles_core.native_preflight import NativePreflight, request
from dotfiles_core.protocol import Result
from dotfiles_core.workflow_preflight import Inputs, Prepared, PreflightInputError
from dotfiles_core.workflow_rules import SelectedStage


class QueryAdapter:
    def __init__(self, value):
        self.value = value
        self.calls = []

    def invoke(self, operation, context):
        self.calls.append((operation, context))
        return Result(operation, 0, {'value': self.value})


class NativePreflightTests(unittest.TestCase):
    def setUp(self):
        # Construction only: these tests do not launch the native adapter.
        with patch('dotfiles_core.native_preflight.native_filesystem'):
            self.native = NativePreflight('unix', '/native-shell', Paths())
        self.inputs = Inputs(str(ROOT), 'macos', 'unix', 'macos', 'test', '/config', '/backup',
                             True, False, False, native={'brew_cmd': '/brew', 'brew_prefix': '/prefix'})

    def test_installation_uses_current_context_and_shared_selection(self):
        items = [{'id': 'tool'}]
        with patch('dotfiles_core.native_preflight.native_installation') as factory:
            factory.return_value.plan.return_value = items
            self.assertEqual(self.native.installation(self.inputs, {'install': 'tool'}, '/session', 'resume'), items)
        self.assertEqual(factory.call_args.args, ('unix', '/native-shell', 'macos|1|/brew|/prefix|/session/packages-backups|||'))
        factory.return_value.plan.assert_called_once_with(str(ROOT / 'software/items'), 'macos', False, False, 'tool', 'resume')

    def test_planning_scratch_is_temporary_and_uses_preview(self):
        observed = []
        self.native.filesystem.entry.return_value = Entry('absent')

        def planning(operation, context):
            self.assertEqual(operation, 'apply-plan-native')
            self.assertEqual(context['preview'], '1')
            self.assertEqual(context['selection'], ['fish'])
            directory = Path(context['render_scratch'])
            self.assertTrue(directory.is_dir())
            observed.append(directory)
            return [], []

        with patch('dotfiles_core.native_preflight.apply_request', side_effect=planning):
            self.assertEqual(self.native.configuration(self.inputs, '/session', ['fish']), [])
        self.assertFalse(observed[0].exists())

    def test_native_query_results_are_typed_and_arguments_remain_literal(self):
        adapter = QueryAdapter(True)
        self.native.adapter = adapter
        self.assertTrue(self.native.command_present('literal $command'))
        self.assertEqual(adapter.calls[0][1]['arguments'], ['literal $command'])
        adapter.value = 'true'
        with self.assertRaises(ProtocolError):
            self.native.command_present('tool')
        adapter.value = {}
        with self.assertRaises(ProtocolError):
            self.native.wsl(self.inputs, {'wsl': 'FedoraLinux-44'})

    def test_unix_preflight_request_writes_only_temporary_context(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            values = dict(assume_yes='1', inside_wsl='0', repo_root=str(ROOT), platform='macos',
                          profile_name='macos', session_id='test', config_home='/config', backup_root='/backup',
                          dry_run='1', plan_only='0', china_mirrors='0', results_path='', only_stage='', from_stage='')
            for name, value in values.items():
                (directory / name).write_text(value + '\n')
            prepared = Prepared(self.inputs, '/backup/workflow-test', {'install': 'all'},
                                (SelectedStage('configuration', True, '', 'configuration', 'configuration'),),
                                [], ['fish'], [], [], None, ())
            with patch('dotfiles_core.native_preflight.NativePreflight') as native, patch('dotfiles_core.workflow_preflight.prepare', return_value=prepared):
                native.return_value.install_context = 'macos|1||||||'
                value, lines = request('workflow-preflight-native', {'style': 'unix', 'directory': str(directory), 'native_shell': '/shell'})
            self.assertIsNone(value)
            self.assertEqual(lines, [])
            self.assertEqual((directory / 'stages.plan').read_text(), 'configuration|1||configuration|configuration\n')
            self.assertEqual((directory / 'components').read_text(), 'fish\n')
            self.assertFalse((directory / 'resume_stages').exists())
            self.assertFalse((directory / 'runtime').exists())
            (directory / 'assume_yes').write_text('invalid\n')
            with patch('dotfiles_core.native_preflight.NativePreflight'), patch('dotfiles_core.workflow_preflight.prepare') as prepare:
                with self.assertRaises(PreflightInputError):
                    request('workflow-preflight-native', {'style': 'unix', 'directory': str(directory), 'native_shell': '/shell'})
                prepare.assert_not_called()

    def test_windows_request_keeps_the_entry_resolved_session_root(self):
        values = dict(RepoRoot=str(ROOT), ProfileName='windows', SessionId='test', ConfigRoot='/config',
                      SessionPath='/resolved backup/workflow-test', BackupRoot='relative backup', DryRun=True,
                      PlanOnly=False, NoChinaMirrors=False, ProgramFiles='/programs', VsInstallerRoot='/vs',
                      GitConfigPaths=[], GitSettings=[])

        def prepared(inputs, operations, paths):
            self.assertEqual(inputs.backup, '/resolved backup')
            return Prepared(inputs, values['SessionPath'], {'install': 'all'}, (), [], [], [], [], None, ())

        with patch('dotfiles_core.native_preflight.NativePreflight') as native, patch('dotfiles_core.workflow_preflight.prepare', side_effect=prepared):
            native.return_value.install_context = {'DryRun': True}
            updates, lines = request('workflow-preflight-native', {'style': 'windows', 'native_context': values, 'native_shell': '/shell'})
        self.assertEqual(updates['SessionPath'], values['SessionPath'])
        self.assertEqual(updates['InstallContext'], {'DryRun': True})
        self.assertEqual(lines, [])

    @unittest.skipUnless(os.name != 'nt' and shutil.which('bash'), 'Unix native observation adapter')
    def test_real_unix_observation_boundary(self):
        native = NativePreflight('unix', shutil.which('bash'), Paths())
        with patch.dict(os.environ, {'DOTFILES_PYTHON': sys.executable}):
            self.assertTrue(native.command_present('bash'))
            self.assertFalse(native.command_present('dotfiles nonexistent literal $command'))
            prefix = "/literal 中文 'quoted' prefix"
            self.assertEqual(native.string('fish-path', ['macos', prefix]), prefix + '/bin/fish')


if __name__ == '__main__':
    unittest.main()
