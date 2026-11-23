import copy
import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from dotfiles_core.errors import CoreError
from dotfiles_core.snapshot import Platform, Snapshot, SnapshotError, capture, verify_archive
from dotfiles_core.software import read_catalog, select, installation, installation_roots, validate, profile_selection, write_catalog
from dotfiles_core.install_config import ROOT, PLATFORMS


class SnapshotTests(unittest.TestCase):
    def link_directory(self, link, target):
        try:
            link.symlink_to(target, target_is_directory=True)
        except OSError as exc:
            if getattr(exc, 'winerror', None) != 1314:
                raise
            import _winapi
            _winapi.CreateJunction(str(target), str(link))

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()
        self.home = self.base / 'home'
        self.config = self.home / '.config'
        (self.config / 'tool/empty').mkdir(parents=True)
        (self.config / 'tool/value').write_bytes(b'captured\x00contents')
        (self.config / 'tool/value').chmod(0o700)
        (self.config / 'tool/cache').write_text('excluded')
        self.roots = dict(home=str(self.home), config_home=str(self.config))
        self.platform = Platform('macos', 'arm64', 'native')
        self.catalog = {'tool': dict(schema_version=1, config=[dict(id='settings', platforms=['macos'], root='config_home', path='tool', exclude=['cache'])])}
        self.archive = self.base / 'snapshot.zip'

    def capture(self, **kwargs):
        return capture(self.catalog, self.platform, ['tool'], self.roots, self.archive, **kwargs)

    def rewrite(self, change, extra=None):
        with zipfile.ZipFile(self.archive) as z:
            files = {i.filename: z.read(i) for i in z.infolist()}
        manifest = json.loads(files['manifest.json'])
        change(manifest)
        files['manifest.json'] = json.dumps(manifest).encode()
        if extra:
            files.update(extra)
        with zipfile.ZipFile(self.archive, 'w') as z:
            for name, data in files.items():
                z.writestr(name, data)

    def test_roundtrip_and_independence(self):
        snapshot = self.capture()
        self.assertEqual(snapshot.document(), verify_archive(self.archive).document())
        target = self.base / 'unpacked'
        verify_archive(self.archive, target)
        payload = target / 'payload/tool/settings/root/value'
        self.assertEqual(payload.read_bytes(), b'captured\x00contents')
        self.assertTrue((payload.parent / 'empty').is_dir())
        self.assertFalse((payload.parent / 'cache').exists())
        self.assertEqual(payload.stat().st_mode & 0o111, (self.config / 'tool/value').stat().st_mode & 0o111)
        payload.write_text('changed')
        self.assertEqual(verify_archive(self.archive).document(), snapshot.document())

    def test_dry_run_no_archive(self):
        self.capture(dry=True)
        self.assertFalse(self.archive.exists())
        self.assertEqual(list(self.base.glob('.dotfiles-snapshot-*')), [])

    def test_missing_or_link_fail_without_publication(self):
        for kind in ['missing', 'link']:
            with self.subTest(kind=kind):
                catalog = copy.deepcopy(self.catalog)
                catalog['tool']['config'][0]['path'] = kind
                if kind == 'link':
                    self.link_directory(self.config / kind, self.config / 'tool')
                with self.assertRaises((OSError, SnapshotError)):
                    capture(catalog, self.platform, ['tool'], self.roots, self.archive)
                self.assertFalse(self.archive.exists())
        self.assertEqual(list(self.base.glob('.dotfiles-snapshot-*')), [])

    def test_excluded_link_not_followed(self):
        (self.config / 'tool/cache').unlink()
        target = self.base / 'excluded-target'
        target.mkdir()
        self.link_directory(self.config / 'tool/cache', target)
        target.rmdir()
        self.capture()

    def test_nested_new_file_is_collected(self):
        (self.config / 'tool/empty/new').write_text('new')
        snapshot = self.capture()
        self.assertIn('empty/new', [e['path'] for e in snapshot.entries])

    def test_capture_changes_fail(self):
        from dotfile_viewer import snapshot
        original = snapshot.inventory
        calls = 0
        def inventory(*args):
            nonlocal calls
            calls += 1
            if calls == 2:
                (self.config / 'tool/new').write_text('racing writer')
            return original(*args)
        with patch.object(snapshot, 'inventory', inventory):
            with self.assertRaisesRegex(SnapshotError, 'changed'):
                self.capture()
        self.assertFalse(self.archive.exists())

    def test_read_failure_no_publication(self):
        original_open = os.open
        def deny_read(path, flags, *args, **kwargs):
            if Path(path) == self.config / 'tool/value':
                raise PermissionError('denied')
            return original_open(path, flags, *args, **kwargs)
        with patch('dotfile_viewer.snapshot.os.open', new=deny_read):
            with self.assertRaises(PermissionError):
                self.capture()
        self.assertFalse(self.archive.exists())

    def test_output_overlap_and_no_clobber(self):
        with self.assertRaises(SnapshotError):
            capture(self.catalog, self.platform, ['tool'], self.roots, self.config / 'tool/snapshot.zip')
        self.capture()
        before = self.archive.read_bytes()
        with self.assertRaises(SnapshotError):
            self.capture()
        self.assertEqual(before, self.archive.read_bytes())

    def test_digest_mismatch(self):
        self.capture()
        self.rewrite(lambda m: next(e for e in m['entries'] if e['kind'] == 'file').update(sha256='0' * 64))
        with self.assertRaisesRegex(SnapshotError, 'digest'):
            verify_archive(self.archive)

    def test_bad_version_and_paths(self):
        for change in [lambda m: m.update(schema_version=1),
                       lambda m: m['entries'][0].update(path='../escape'),
                       lambda m: m['entries'][0].update(path='/absolute'),
                       lambda m: m['entries'][0].update(path='CON'),
                       lambda m: m['entries'].append(dict(m['entries'][0])),
                       lambda m: m['entries'].pop(0),
                       lambda m: m['software']['tool']['config'][0].update(path='../../escape')]:
            with self.subTest(change=change):
                self.archive.unlink(missing_ok=True)
                self.capture()
                self.rewrite(change)
                with self.assertRaises((CoreError, ValueError)):
                    verify_archive(self.archive)

    def test_unlisted_or_duplicate_archive_member(self):
        self.capture()
        with zipfile.ZipFile(self.archive, 'a') as z:
            z.writestr('../escape', 'bad')
        with self.assertRaises(SnapshotError):
            verify_archive(self.archive)

    def test_symlink_archive_member(self):
        self.capture()
        with zipfile.ZipFile(self.archive, 'a') as z:
            info = zipfile.ZipInfo('link')
            info.create_system = 3
            info.external_attr = 0o120777 << 16
            z.writestr(info, '/etc/passwd')
        with self.assertRaises(SnapshotError):
            verify_archive(self.archive)

    def test_single_file_and_empty_software_config(self):
        self.catalog['tool']['config'][0]['path'] = 'tool/value'
        snapshot = self.capture()
        self.assertEqual(len(snapshot.entries), 1)
        self.assertEqual(snapshot.entries[0]['path'], '')

    def test_overlap_rejected(self):
        self.catalog['tool']['config'].append(dict(id='nested', platforms=['macos'], root='config_home', path='tool/empty'))
        with self.assertRaises(SnapshotError):
            self.capture()

    def test_platform_validation(self):
        for p in [Platform('linux.none', 'arm64', 'native'), Platform('macos', 'arm64', 'wsl')]:
            with self.assertRaises(SnapshotError):
                p.validate()


class SoftwareTests(unittest.TestCase):
    def test_catalog_all_platforms(self):
        catalog = read_catalog()
        for platform in PLATFORMS:
            items = installation(catalog, platform)
            seen = set()
            for item in items:
                self.assertTrue(set(item.get('depends_on', '').split()) <= seen)
                seen.add(item['id'])
            self.assertTrue(select(catalog, platform, 'native', ['all']))
        self.assertFalse((ROOT / 'configs').exists())
        self.assertFalse((ROOT / 'install/items').exists())
        self.assertFalse((ROOT / 'apply/items').exists())

    def test_profile_selection(self):
        for path in (ROOT / 'workflow/profiles').glob('*.conf'):
            self.assertTrue(profile_selection(path))

    def test_copied_declarations_do_not_change(self):
        catalog = read_catalog()
        chosen = select(catalog, 'macos', 'native', ['fish'])
        original = copy.deepcopy(chosen)
        catalog['fish']['install']['macos']['packages'] = 'changed'
        self.assertEqual(chosen, original)
        with tempfile.TemporaryDirectory() as d:
            write_catalog(chosen, Path(d) / 'items')
            self.assertEqual(installation(chosen, 'macos'), installation(read_catalog(Path(d) / 'items'), 'macos'))

    def test_install_roots_preserve_demand_driven_dependencies(self):
        catalog = read_catalog()
        self.assertEqual(installation_roots(catalog, 'macos', 'native', ['fish']), ['fish'])
        self.assertEqual(installation_roots(catalog, 'macos', 'native', ['git']), ['xcode-command-line-tools'])
        self.assertIn('homebrew', select(catalog, 'macos', 'native', ['fish']))

    def test_unknown_and_cycles(self):
        catalog = read_catalog()
        with self.assertRaises(CoreError):
            select(catalog, 'macos', 'native', ['nonexistent'])
        catalog['fish']['requires'] = {'macos': ['fish']}
        with self.assertRaisesRegex(CoreError, 'cycle'):
            select(catalog, 'macos', 'native', ['fish'])

    def test_unknown_config_fields(self):
        with self.assertRaises(CoreError):
            validate('test', {'schema_version': 1, 'config': [{'command': 'unsafe'}]})



class NativeSnapshotTests(unittest.TestCase):
    def setUp(self):
        import subprocess
        import sys
        from dotfiles_core.snapshot_entry import host
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()
        self.source = self.base / 'source'
        self.target = self.base / 'target'
        (self.source / 'tool/empty').mkdir(parents=True)
        (self.source / 'tool/value').write_text('captured')
        self.target.mkdir()
        self.platform = host()
        self.archive = self.base / 'snapshot.zip'
        catalog = {'tool': dict(schema_version=1, config=[dict(id='settings', platforms=[self.platform.branch], root='home', path='tool')])}
        capture(catalog, self.platform, ['tool'], dict(home=str(self.source)), self.archive)
        self.env = dict(os.environ, HOME=str(self.target), USERPROFILE=str(self.target),
                        DOTFILES_PYTHON=sys.executable, DOTFILES_BACKUP_DIR=str(self.base / 'backups'), XDG_STATE_HOME=str(self.base / 'state'),
                        DOTFILES_DEPLOYMENT_LOCK=str(self.base / 'lease'), DOTFILES_DEPLOYMENT_TOKEN='')
        self.original = hashlib.sha256(self.archive.read_bytes()).hexdigest()

    def invoke(self, *args):
        import subprocess
        if os.name == 'nt':
            import shutil
            shell = shutil.which('powershell.exe') or shutil.which('pwsh')
            command = [shell, '-NoProfile', '-File', str(ROOT / 'apply/windows.ps1'), '-Snapshot', str(self.archive)]
            if args:
                command.append('-DryRun')
        else:
            command = ['bash', str(ROOT / 'apply/apply.sh'), '--snapshot', str(self.archive), *args]
        result = subprocess.run(command, env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def test_viewer_copy_backup_idempotence_and_removed_recovery(self):
        import subprocess
        (self.target / 'tool').mkdir()
        (self.target / 'tool/value').write_text('old')
        (self.target / 'tool/extra').write_text('keep')
        self.invoke('--dry-run')
        self.assertEqual((self.target / 'tool/value').read_text(), 'old')
        self.assertFalse((self.base / 'backups').exists())
        self.invoke()
        self.assertEqual((self.target / 'tool/value').read_text(), 'captured')
        self.assertEqual((self.target / 'tool/extra').read_text(), 'keep')
        self.assertTrue((self.target / 'tool/empty').is_dir())
        self.assertFalse((self.base / 'lease').exists())
        before = (self.target / 'tool/value').stat().st_ino
        self.invoke()
        self.assertEqual((self.target / 'tool/value').stat().st_ino, before)
        journal_name = '*.original'
        journals = list((self.base / 'backups').rglob(journal_name))
        self.assertTrue(journals)
        (self.target / 'tool/value').write_text('application edited')
        self.assertEqual(hashlib.sha256(self.archive.read_bytes()).hexdigest(), self.original)
        if os.name != 'nt':
            first = min(journals, key=lambda p: p.stat().st_mtime_ns)
            guarded = subprocess.run(['bash', str(ROOT / 'apply/apply.sh'), '--restore', str(first)],
                                     env=self.env, text=True, capture_output=True)
            self.assertNotEqual(guarded.returncode, 0)
            self.assertEqual((self.target / 'tool/value').read_text(), 'application edited')

    def test_mismatch_precedes_mutation(self):
        with zipfile.ZipFile(self.archive) as z:
            files = {i.filename: z.read(i) for i in z.infolist()}
        document = json.loads(files['manifest.json'])
        document['platform']['architecture'] = 'x86_64' if self.platform.architecture != 'x86_64' else 'arm64'
        files['manifest.json'] = json.dumps(document).encode()
        with zipfile.ZipFile(self.archive, 'w') as z:
            for name, data in files.items():
                z.writestr(name, data)
        from dotfiles_core.snapshot_entry import restore_snapshot
        shell = '/bin/bash' if os.name != 'nt' else __import__('shutil').which('powershell.exe')
        with self.assertRaisesRegex(SnapshotError, 'mismatch'):
            restore_snapshot(self.archive, self.platform, shell, dict(home=str(self.target)), self.base / 'backups')
        self.assertFalse((self.target / 'tool').exists())
        self.assertFalse((self.base / 'backups').exists())

    @unittest.skipUnless(__import__('platform').system() == 'Darwin', 'macOS fake Homebrew boundary')
    def test_full_restore_uses_archived_recipe_and_blocks_config_after_failure(self):
        import subprocess
        catalog = {'tool': dict(schema_version=1,
            install={'macos': dict(order='1', method='brew', packages='snapshot.fixture', source_kind='default')},
            config=[dict(id='settings', platforms=['macos'], root='home', path='tool')])}
        self.archive.unlink()
        capture(catalog, self.platform, ['tool'], dict(home=str(self.source)), self.archive)
        # The archive must remain usable without a matching current repository ID.
        catalog['tool']['install']['macos']['packages'] = 'changed.recipe'
        binary = self.base / 'bin'
        binary.mkdir()
        brew = binary / 'brew'
        brew.write_text('#!/bin/sh\ncase "$1" in\n--prefix) dirname \"$(dirname \"$0\")\" ;;\nlist) exit 1 ;;\ninstall) printf "%s\\n" "$*" >> "$FIXTURE_LOG"; exit "$FIXTURE_EXIT" ;;\n*) exit 99 ;;\nesac\n')
        brew.chmod(0o700)
        env = dict(self.env, PATH=str(binary) + os.pathsep + os.environ['PATH'], FIXTURE_LOG=str(self.base / 'commands'), FIXTURE_EXIT='23')
        command = ['bash', str(ROOT / 'snapshot/snapshot.sh'), 'restore', '--snapshot', str(self.archive)]
        failed = subprocess.run(command, env=env, text=True, capture_output=True)
        self.assertEqual(failed.returncode, 23, failed.stdout + failed.stderr)
        self.assertFalse((self.target / 'tool').exists())
        self.assertIn('install snapshot.fixture', (self.base / 'commands').read_text())
        reports = list((self.base / 'backups').rglob('workflow.tsv'))
        self.assertTrue(any('|configuration|blocked|' in p.read_text() for p in reports))
        env['FIXTURE_EXIT'] = '0'
        success = subprocess.run(command, env=env, text=True, capture_output=True)
        self.assertEqual(success.returncode, 0, success.stdout + success.stderr)
        self.assertEqual((self.target / 'tool/value').read_text(), 'captured')
        self.assertNotIn('changed.recipe', (self.base / 'commands').read_text())
        self.assertFalse((self.base / 'lease').exists())


if __name__ == '__main__':
    unittest.main()
