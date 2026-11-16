from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from dotfiles_core.apply_planning import Entry, Planner
from dotfiles_core.install_config import ROOT
from dotfiles_core.mirror_planning import Mirrors, cargo_owned, npm_owned, pacman_text, read_text, has_marker
from dotfiles_core.mirror_rules import read_config, render


class MirrorPlanningTests(unittest.TestCase):
    def test_unreadable_ownership_is_unrecognized(self):
        with patch('dotfiles_core.mirror_planning.read_text', side_effect=PermissionError('unreadable')):
            with patch('sys.stderr'):
                self.assertFalse(has_marker('/config', '# Managed by dotfiles mirrors'))

    def setUp(self):
        self.current = read_config((ROOT / 'mirrors/current.conf').read_text())
        self.legacy = read_config((ROOT / 'mirrors/legacy.conf').read_text())

    def test_ownership_keeps_unknown_registries_and_accepts_missing_keys(self):
        self.assertTrue(cargo_owned('[source.rsproxy-sparse]\nreplace-with = "rsproxy-sparse"\n'))
        self.assertFalse(cargo_owned('[build]\njobs=7\n'))
        self.assertFalse(cargo_owned('[source.rsproxy-sparse]\r\nreplace-with = "rsproxy-sparse"\r\n'))
        for mode in ('initialize', 'apply'):
            self.assertTrue(npm_owned('save-exact=true\n', mode, self.current, {}, self.legacy))
            self.assertFalse(npm_owned('registry=https://private.test\n', mode, self.current, {}, self.legacy))
        known = 'registry=' + self.legacy['npm'] + '\n'
        self.assertFalse(npm_owned(known, 'initialize', self.current, {}, self.legacy))
        self.assertTrue(npm_owned(known, 'apply', self.current, {}, self.legacy))

    def test_pacman_preserves_fallbacks_branch_and_initialized_bytes(self):
        old = 'Server = ' + self.legacy['arch'] + '/$repo/os/$arch\n'
        fallback = 'Server = https://private.test/$repo/os/$arch\n'
        current = dict(self.current, arch='https://arch.test')
        self.assertEqual(pacman_text(old + fallback, 'apply', 'arch', '', current, {}, self.legacy),
                         'Server = https://arch.test/$repo/os/$arch\n' + fallback)
        text = '# keep CRLF\r\n' + old.rstrip('\n')
        self.assertEqual(pacman_text(text, 'initialize', 'arch', '', current, {}, self.legacy), text)
        current['manjaro'] = 'https://manjaro.test'
        self.assertEqual(pacman_text(fallback, 'apply', 'manjaro', '/stable', current, {}, self.legacy),
                         'Server = https://manjaro.test/stable/$repo/$arch\n' + fallback)

    def test_unknown_parent_and_explicit_component_replacement(self):
        with tempfile.TemporaryDirectory() as directory:
            candidate = str(Path(directory) / 'candidate')
            Path(candidate).write_text('mirror')
            class FS:
                def entry(self, path):
                    if path == candidate:
                        return Entry('file', True)
                    if path == '/config':
                        return Entry('directory', True, True, True)
                    if path == '/config/fish':
                        return Entry('link')
                    return Entry('absent')
                def state(self, path):
                    if path != candidate:
                        raise AssertionError('Virtual target was inspected')
                    return '1:2:f:content'
                def value(self, *args, **kwargs):
                    raise AssertionError('Unmanaged/virtual target was queried')
            fs = FS()
            mirrors = Mirrors.__new__(Mirrors)
            mirrors.fs = fs
            mirrors.planner = Planner(fs, '/backup')
            mirrors.add(candidate, '/config/fish/mirrors', '/config', 'apply')
            self.assertEqual(mirrors.planner.rows[0]['reason'], 'unmanaged-parent')
            mirrors.planner = Planner(fs, '/backup', directories={'/config/fish': True})
            mirrors.add(candidate, '/config/fish/mirrors', '/config', 'initialize', owned=False)
            self.assertEqual(mirrors.planner.rows[0]['action'], 'copy')
            self.assertEqual(mirrors.planner.rows[0]['before'], 'absent')

    def test_unrelated_payload_bytes_are_not_normalized(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'npmrc'
            original = b'# unknown \xff\r\nsave-exact=true\r\n'
            path.write_bytes(original)
            self.assertEqual(read_text(path).encode('utf-8', errors='surrogateescape'), original)
            actual = render('npm', 'apply', read_text(path), self.current, {}, self.legacy)
            self.assertEqual(actual.encode('utf-8', errors='surrogateescape'),
                             original + ('registry=' + self.current['npm'] + '\n').encode())
