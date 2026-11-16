from dataclasses import replace
import unittest

from dotfiles_core.apply_planning import Entry, Paths
from dotfiles_core.install_config import ROOT
from dotfiles_core.workflow_preflight import Inputs, PreflightError, prepare, assert_output, validate_plan_outputs


class Observations:
    def __init__(self):
        self.calls = []
        self.entries = {'/': Entry('directory', writable=True), '/backup': Entry('directory', writable=True)}
        self.present = {'sudo', 'winget.exe'}
    def resolve_root(self, path): return path
    def entry(self, path): return self.entries.get(path, Entry('absent'))
    def anchor(self, path): return '/'
    def command_present(self, name):
        self.calls.append(name)
        return name in self.present
    def installation(self, inputs, profile, session, mode):
        self.calls.append(('install', mode))
        return [{'id': name, 'action': 'install', 'reason': 'requested'} for name in profile['install'].split()]
    def mirror_config(self, inputs): self.calls.append('mirror-config')


class PreflightTests(unittest.TestCase):
    def setUp(self):
        self.inputs = Inputs(str(ROOT), 'macos', 'unix', 'macos-full', 'test', '/config', '/backup', False, False, True)
        self.operations = Observations()

    def test_installation_only(self):
        result = prepare(self.inputs, self.operations, Paths())
        self.assertEqual([s.Id for s in result.stages if s.Enabled], ['packages'])
        self.assertFalse(result.inputs.mirrors)
        self.assertEqual(result.configuration, [])
        self.assertEqual(result.components, [])
        self.assertIsNone(result.wsl)
        self.assertEqual(self.operations.calls, [('install', 'normal'), 'sudo'])

    def test_real_packages_require_sudo_but_preview_does_not(self):
        self.operations.present.clear()
        with self.assertRaisesRegex(PreflightError, 'sudo'):
            prepare(self.inputs, self.operations, Paths())
        self.operations.calls.clear()
        prepare(replace(self.inputs, plan_only=True), self.operations, Paths())
        self.assertNotIn('sudo', self.operations.calls)

    def test_full_windows_is_host_only(self):
        inputs = replace(self.inputs, platform='windows', style='windows', profile='windows-full')
        result = prepare(inputs, self.operations, Paths(case_insensitive=True))
        self.assertEqual(self.operations.calls, [('install', 'normal'), 'winget.exe'])
        self.assertIsNone(result.wsl)

    def test_existing_outputs_and_overlap(self):
        self.operations.entries['/backup/report'] = Entry('link')
        with self.assertRaisesRegex(PreflightError, 'already exists'):
            prepare(replace(self.inputs, results='/backup/report'), self.operations, Paths())
        with self.assertRaisesRegex(PreflightError, 'planned file'):
            validate_plan_outputs(['/backup/report'], [dict(source='', target='/backup/report/child')], Paths())
        with self.assertRaisesRegex(PreflightError, 'overlaps'):
            assert_output('/Data/Output', ['/data/output/child'], self.operations, Paths(case_insensitive=True), 'windows')
        assert_output('/Data/Output-two', ['/data/output'], self.operations, Paths(case_insensitive=True), 'windows')

    def test_invalid_identity_precedes_observation(self):
        with self.assertRaises(PreflightError) as failure:
            prepare(replace(self.inputs, session_id='../invalid'), self.operations, Paths())
        self.assertEqual(failure.exception.exit_code, 2)
        self.assertEqual(self.operations.calls, [])

    def test_output_ancestor_and_caller_directory(self):
        def reject(path): raise PreflightError('Root ancestor is not a real directory')
        self.operations.resolve_root = reject
        with self.assertRaisesRegex(PreflightError, 'ancestor'):
            assert_output('/linked/child/report', [], self.operations, Paths(case_insensitive=True), 'windows')
        self.operations.resolve_root = lambda path: '/reports' if path == '.' else path
        self.operations.entries['/reports'] = Entry('directory', writable=True)
        result = prepare(replace(self.inputs, results='report.tsv'), self.operations, Paths())
        self.assertEqual(result.inputs.results, '/reports/report.tsv')
