import os
import sys
import unittest
from unittest.mock import patch

from dotfiles_core.errors import AdapterError, ProtocolError
from dotfiles_core.workflow_packages import prepare, run, stage_environment, request


class Preparation:
    def __init__(self):
        self.calls = []
        self.installed = []
        self.fail = False

    def packages(self):
        self.calls.append('inventory')
        return self.installed

    def command(self, action, dry):
        self.calls.append((action, dry))
        if self.fail:
            raise AdapterError('preparation failed', 23)


class WorkflowPackageTests(unittest.TestCase):
    def test_replans_after_preparation_without_post_install_observation(self):
        first = [{'method': 'apt', 'action': 'install'}]
        second = [{'method': 'apt', 'action': 'skip'}]
        plans = iter([first, second])
        calls = []
        native = Preparation()

        def refresh():
            calls.append('refresh')
            return next(plans)

        run('unix', 'linux.apt', False, refresh, lambda items: calls.append(items), native)
        self.assertEqual(calls, ['refresh', 'refresh', second])
        self.assertEqual(native.calls, [('apt-update', False)])

    def test_preparation_failure_stops_before_installation(self):
        native = Preparation()
        native.fail = True
        calls = []
        with self.assertRaises(AdapterError) as failure:
            run('unix', 'linux.apt', False, lambda: [{'method': 'apt', 'action': 'install'}], calls.append, native)
        self.assertEqual(failure.exception.exit_code, 23)
        self.assertEqual(calls, [])

    def test_conflict_inventory_is_requested_only_for_pending_rustup(self):
        native = Preparation()
        native.installed = ['rust-analyzer']
        prepare([{'method': 'rustup', 'action': 'skip'}], 'linux.pacman', True, native)
        self.assertEqual(native.calls, [])
        prepare([{'method': 'rustup', 'action': 'install'}], 'linux.pacman', True, native)
        self.assertEqual(native.calls, ['inventory', ('pacman-remove-rust-analyzer', True)])
        native.calls.clear()
        native.installed = ['other']
        prepare([{'method': 'rustup', 'action': 'install'}], 'linux.pacman', True, native)
        self.assertEqual(native.calls, ['inventory'])

    def test_preparation_uses_pending_recipe_and_preserves_dry_run(self):
        cases = [('linux.apt', 'apt', 'install', '', [('apt-update', True)]),
                 ('linux.apt', 'apt', 'skip', '', []),
                 ('linux.apt', 'cargo', 'install', '', []),
                 ('linux.apt', 'apt-or-snap', 'install', 'snap:tool', []),
                 ('linux.pacman', 'pacman', 'install', '', [('pacman-upgrade', True)]),
                 ('linux.pacman', 'pacman', 'skip', '', [])]
        for platform, method, action, state, expected in cases:
            with self.subTest(platform=platform, method=method, action=action):
                native = Preparation()
                prepare([dict(method=method, action=action, state=state)], platform, True, native)
                self.assertEqual(native.calls, expected)

    def test_windows_keeps_single_plan_and_no_unix_preparation(self):
        native = Preparation()
        with patch('dotfiles_core.workflow_packages.preparation') as preparation:
            plans = iter([[{'method': 'winget', 'action': 'install'}]])
            installed = []
            run('windows', 'windows', True, lambda: next(plans), installed.append, native)
            preparation.assert_not_called()
        self.assertEqual(installed, [[{'method': 'winget', 'action': 'install'}]])

    def test_download_environment_does_not_leak_to_later_stages(self):
        with patch.dict(os.environ, {'DOTFILES_TEST_ENV_EXISTING': 'original'}):
            os.environ.pop('DOTFILES_TEST_ENV_NEW', None)
            with self.assertRaises(RuntimeError):
                with stage_environment({'DOTFILES_TEST_ENV_EXISTING': 'download', 'DOTFILES_TEST_ENV_NEW': 'value'}):
                    self.assertEqual(os.environ['DOTFILES_TEST_ENV_EXISTING'], 'download')
                    raise RuntimeError('stage failed')
            self.assertEqual(os.environ['DOTFILES_TEST_ENV_EXISTING'], 'original')
            self.assertNotIn('DOTFILES_TEST_ENV_NEW', os.environ)

    def test_invalid_dry_run_flag_cannot_reach_native_preparation(self):
        with patch('dotfiles_core.workflow_packages.NativePreparation') as native:
            with self.assertRaises(ProtocolError):
                request('workflow-packages-native', dict(native_shell=sys.executable, style='windows',
                        native_context={'RepoRoot': '/repo', 'DryRun': 'invalid'}))
            native.return_value.command.assert_not_called()


if __name__ == '__main__':
    unittest.main()
