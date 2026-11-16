import unittest

from dotfiles_core.apply_planning import Entry, Paths, Planner, desktop_fonts
from dotfiles_core.apply_rules import ApplyItem, ApplyConfigError


class Observations:
    def __init__(self):
        self.entries = {'/': Entry('directory', True, True, True), '/repo': Entry('directory'),
                        '/config': Entry('directory', True, True, True), '/repo/source': Entry('file', True)}
        self.states = {'/repo/source': '1:12:f:payload'}
        self.identities = {'/repo/source': '1:12', '/config': '1:13', '/': '1:1'}
        self.children = {}
        self.matches = set()
        self.calls = []

    def entry(self, path):
        self.calls.append(('entry', path))
        return self.entries.get(path, Entry('absent'))

    def state(self, path):
        self.calls.append(('state', path))
        return self.states.get(path, 'absent')

    def tree(self, path):
        return self.children.get(path, [])

    def anchor(self, path):
        return '/config'

    def identity(self, path):
        return self.identities[path]

    def equal(self, source, target, method):
        return (source, target, method) in self.matches


class ApplyPlanningTests(unittest.TestCase):
    def test_desktop_candidates_require_fonts_and_guard_current_settings(self):
        fs = Observations()
        planner = Planner(fs, '/backup')
        rendered, messages = [], []
        def render(kind, target, candidate):
            rendered.append(kind)
            fs.entries[candidate] = Entry('file', True)
            fs.states[candidate] = '1:20:f:rendered'
        with self.assertRaisesRegex(ApplyConfigError, 'fonts are missing'):
            desktop_fonts(planner, 'fonts', '/config', '/scratch', False, '', render, messages.append, ['Sample Sans'])
        self.assertEqual(rendered, [])
        desktop_fonts(planner, 'fonts', '/config', '/scratch', True, '', render, messages.append, ['Sample Sans'])
        self.assertEqual(rendered, ['kdeglobals', 'gtk-3.0/settings.ini', 'gtk-4.0/settings.ini'])
        self.assertEqual([row['action'] for row in planner.rows], ['copy', 'mkdir', 'copy', 'mkdir', 'copy'])
        def changed(kind, target, candidate):
            fs.states[target] = 'user-edit'
        with self.assertRaisesRegex(ApplyConfigError, 'changed during rendering'):
            desktop_fonts(Planner(fs, '/backup'), 'fonts', '/config', '/scratch', True, '', changed, messages.append, ['Sample Sans'])

    def test_conflicting_parent_is_backed_up_once_and_children_are_virtual(self):
        fs = Observations()
        fs.entries['/config/tool'] = Entry('link')
        fs.states['/config/tool'] = '1:14:l:old'
        planner = Planner(fs, '/backups/session')
        planner.file('tool', 'hardlink', '/repo/source', '/config/tool/one', '/config')
        planner.file('tool', 'copy', '/repo/source', '/config/tool/two', '/config')
        self.assertEqual([(row['action'], row['target'], row['before']) for row in planner.rows],
                         [('mkdir', '/config/tool', '1:14:l:old'), ('hardlink', '/config/tool/one', 'absent'),
                          ('copy', '/config/tool/two', 'absent')])
        self.assertEqual(planner.rows[0]['backup'], '/backups/session/files/tool/config/tool')
        self.assertNotIn(('state', '/config/tool/one'), fs.calls)
        self.assertNotIn(('state', '/config/tool/two'), fs.calls)

    def test_unchanged_files_and_cross_volume_rejection(self):
        for method in ('hardlink', 'copy'):
            fs = Observations()
            fs.entries['/config/tool'] = Entry('file', True)
            fs.states['/config/tool'] = '1:12:f:payload'
            fs.matches.add(('/repo/source', '/config/tool', method))
            planner = Planner(fs, '/backups/session')
            planner.file('tool', method, '/repo/source', '/config/tool', '/config')
            self.assertEqual((planner.rows[0]['action'], planner.rows[0]['reason'], planner.rows[0]['backup']),
                             ('skip', 'unchanged', ''))
        fs.identities['/repo/source'] = '2:12'
        with self.assertRaisesRegex(ApplyConfigError, 'crosses filesystems'):
            Planner(fs, '/backup').file('tool', 'hardlink', '/repo/source', '/config/tool', '/config')
        fs.entries['/config'] = Entry('directory', True, False, True)
        with self.assertRaisesRegex(ApplyConfigError, 'not writable'):
            Planner(fs, '/backup').file('tool', 'copy', '/repo/source', '/config/tool', '/config')

    def test_exclusions_preserve_unknown_sources_and_conflicts_fail(self):
        fs = Observations()
        fs.entries['/repo/tree'] = Entry('directory')
        fs.entries['/repo/tree/unknown'] = Entry('link')
        fs.children['/repo/tree'] = ['/repo/tree/unknown']
        item = ApplyItem('tool', 'tree', 'config_home', 'tool', 'hardlink', 'unknown')
        rows = Planner(fs, '/backup').components([item], '/repo', '/config', None)
        self.assertEqual([row['reason'] for row in rows], ['directory', 'excluded'])
        with self.assertRaisesRegex(ApplyConfigError, 'Overlapping'):
            Planner(fs, '/backup').components([item, ApplyItem('other', 'source', 'config_home', 'tool/child', 'copy')], '/repo', '/config', None)
        with self.assertRaisesRegex(ApplyConfigError, 'Unknown component'):
            Planner(fs, '/backup').components([item], '/repo', '/config', ['typo'])
        with self.assertRaisesRegex(ApplyConfigError, 'paths overlap'):
            Planner(fs, '/config/tool/backup').components([item], '/repo', '/config', None)
        item = ApplyItem('tool', 'tree', 'config_home', 'tool', 'hardlink')
        with self.assertRaisesRegex(ApplyConfigError, 'Unsupported source'):
            Planner(fs, '/backup').components([item], '/repo', '/config', None)

    def test_windows_backup_sequence_and_path_case(self):
        fs = Observations()
        fs.entries['/config/tool'] = Entry('file')
        fs.states['/config/tool'] = 'old-file'
        fs.states['/config/other'] = 'old-other'
        planner = Planner(fs, '/backup', 'windows', Paths(case_insensitive=True))
        planner.file('tool', 'copy', '/repo/source', '/config/tool/child', '/config')
        planner.file('tool', 'copy', '/repo/source', '/config/other', '/config')
        self.assertEqual([row['backup'] for row in planner.rows], ['/backup/files/tool/1', '', '/backup/files/tool/3'])
        self.assertTrue(planner.virtual('/CONFIG/TOOL/child'))
        paths = Paths(windows=True, case_insensitive=True)
        self.assertTrue(paths.within(r'C:\Config\tool', r'c:\config'))
        self.assertFalse(paths.within(r'C:\Configuration', r'c:\config'))
        self.assertTrue(paths.within(r'\\server\share\config\tool', r'\\SERVER\SHARE\config'))

    def test_unsupported_condition_performs_no_filesystem_queries(self):
        fs = Observations()
        item = ApplyItem('fonts', 'missing', 'config_home', 'fontconfig', 'hardlink', condition='linux-kde')
        rows = Planner(fs, '/backup').components([item], '/repo', '/config', None)
        self.assertEqual(rows[0]['reason'], 'requires-native-linux-kde')
        self.assertEqual(fs.calls, [])
