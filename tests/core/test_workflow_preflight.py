from dataclasses import replace
import unittest

from dotfiles_core.apply_planning import Entry, Paths
from dotfiles_core.install_config import ROOT
from dotfiles_core.workflow_preflight import Inputs, PreflightError, prepare, assert_output


class Observations:
    def __init__(self):
        self.calls = []
        self.entries = {'/': Entry('directory', writable=True), '/backup': Entry('directory', writable=True)}
        self.present = {'sudo', 'winget.exe'}
        self.plan = []

    def resolve_root(self, path):
        return path

    def entry(self, path):
        return self.entries.get(path, Entry('absent'))

    def anchor(self, path):
        return '/'

    def command_present(self, name):
        self.calls.append(name)
        return name in self.present

    def installation(self, inputs, profile, session, mode):
        self.calls.append(('install', mode))
        return [{'id': pair.split(':')[1], 'action': 'install', 'reason': 'requested'}
                for pair in profile['components'].split()]

    def configuration(self, inputs, session, selection):
        self.calls.append('configuration')
        return self.plan

    def mirrors(self, inputs, session):
        self.calls.append('mirrors')
        return []

    def mirror_config(self, inputs):
        self.calls.append('mirror-config')

    def shell(self, inputs, installing_fish):
        self.calls.append(('shell', installing_fish))

    def git_path(self, inputs):
        self.calls.append('git-path')
        return '/git.exe'

    def git_probe(self, inputs, executable, key):
        self.calls.append(('git', key))

    def wsl(self, inputs, profile):
        self.calls.append('wsl')
        return {'Text': ['guest plan']}


class PreflightTests(unittest.TestCase):
    def setUp(self):
        self.inputs = Inputs(str(ROOT), 'macos', 'unix', 'macos-full', 'test', '/config', '/backup', False, False, True)
        self.operations = Observations()

    def test_selection_limits_prerequisites_before_any_session_exists(self):
        prepared = prepare(replace(self.inputs, only='configuration'), self.operations, Paths())
        self.assertEqual(self.operations.calls, [('install', 'normal'), 'configuration'])
        self.assertEqual([stage.Id for stage in prepared.stages if stage.Enabled], ['configuration'])
        self.assertEqual(prepared.session, '/backup/workflow-test')

    def test_real_packages_require_sudo_but_preview_does_not(self):
        self.operations.present.clear()
        with self.assertRaisesRegex(PreflightError, 'sudo'):
            prepare(replace(self.inputs, only='packages'), self.operations, Paths())
        self.operations.calls.clear()
        prepare(replace(self.inputs, only='packages', plan_only=True), self.operations, Paths())
        self.assertNotIn('sudo', self.operations.calls)
        self.assertIn('mirror-config', self.operations.calls)

    def test_unselected_git_does_not_protect_or_probe_git_paths(self):
        windows = replace(self.inputs, platform='windows', style='windows', profile='windows-full',
                          only='configuration', results='/backup/report',
                          native={'git_config_paths': ['/backup/report']})
        prepare(windows, self.operations, Paths(case_insensitive=True))
        self.assertNotIn('git-path', self.operations.calls)
        with self.assertRaisesRegex(PreflightError, 'overlaps'):
            prepare(replace(windows, only='git'), self.operations, Paths(case_insensitive=True))

    def test_existing_report_and_planned_file_conflicts_stop_before_execution(self):
        self.operations.entries['/backup/report'] = Entry('link')
        with self.assertRaisesRegex(PreflightError, 'already exists'):
            prepare(replace(self.inputs, results='/backup/report'), self.operations, Paths())
        self.operations.entries.pop('/backup/report')
        self.operations.plan = [dict(source='/source', target='/backup/workflow-test/file', reason='new', privilege='none')]
        with self.assertRaisesRegex(PreflightError, 'planned file'):
            prepare(replace(self.inputs, only='configuration'), self.operations, Paths())

    def test_windows_comparison_handles_case_and_component_boundaries(self):
        with self.assertRaisesRegex(PreflightError, 'overlaps'):
            assert_output('/Data/Output', ['/data/output/child'], self.operations,
                          Paths(case_insensitive=True), 'windows')
        assert_output('/Data/Output-two', ['/data/output'], self.operations,
                      Paths(case_insensitive=True), 'windows')

    def test_invalid_identity_fails_before_observation_and_preserves_exit_code(self):
        with self.assertRaises(PreflightError) as failure:
            prepare(replace(self.inputs, session_id='../invalid'), self.operations, Paths())
        self.assertEqual(failure.exception.exit_code, 2)
        self.assertEqual(self.operations.calls, [])

    def test_result_may_not_occupy_a_planned_directory(self):
        self.operations.plan = [dict(source='', target='/backup/report', reason='directory', privilege='none')]
        with self.assertRaisesRegex(PreflightError, 'planned file'):
            prepare(replace(self.inputs, only='configuration', results='/backup/report'), self.operations, Paths())

    def test_full_windows_preflight_checks_wsl_before_returning_runnable_state(self):
        windows = replace(self.inputs, platform='windows', style='windows', profile='windows-full')
        self.operations.entries['/git.exe'] = Entry('file')

        def fail_wsl(inputs, profile):
            self.operations.calls.append('wsl')
            raise PreflightError('injected WSL preflight failure')

        self.operations.wsl = fail_wsl
        with self.assertRaisesRegex(PreflightError, 'injected WSL'):
            prepare(windows, self.operations, Paths(case_insensitive=True))
        self.assertEqual(self.operations.calls, [('install', 'normal'), 'winget.exe', 'git-path', 'configuration', 'wsl'])
        self.operations.wsl = lambda inputs, profile: {'Text': ['Nested Linux plan'], 'Arguments': [], 'HostReport': ''}
        prepared = prepare(replace(windows, plan_only=True), self.operations, Paths(case_insensitive=True))
        self.assertEqual([stage.Id for stage in prepared.stages if stage.Enabled], ['packages', 'git', 'configuration', 'wsl'])
        self.assertEqual(prepared.wsl['Text'], ['Nested Linux plan'])
        self.assertEqual(self.operations.entry(prepared.session).kind, 'absent')

    def test_shell_preflight_knows_whether_packages_will_supply_fish(self):
        prepare(self.inputs, self.operations, Paths())
        self.assertIn(('shell', True), self.operations.calls)
        self.operations.calls.clear()
        prepare(replace(self.inputs, only='shell'), self.operations, Paths())
        self.assertIn(('shell', False), self.operations.calls)

    def test_windows_output_observes_all_parent_ancestors(self):
        def reject_link_parent(path):
            self.assertEqual(path, '/linked/child')
            raise PreflightError('Root ancestor is not a real directory')

        self.operations.resolve_root = reject_link_parent
        self.operations.entries['/linked/child'] = Entry('directory')
        with self.assertRaisesRegex(PreflightError, 'ancestor'):
            assert_output('/linked/child/report', [], self.operations, Paths(case_insensitive=True), 'windows')

    def test_unix_report_basename_resolves_the_callers_directory(self):
        self.operations.resolve_root = lambda path: '/reports' if path == '.' else path
        self.operations.entries['/reports'] = Entry('directory', writable=True)
        prepared = prepare(replace(self.inputs, only='configuration', results='report.tsv'), self.operations, Paths())
        self.assertEqual(prepared.inputs.results, '/reports/report.tsv')


if __name__ == '__main__':
    unittest.main()
