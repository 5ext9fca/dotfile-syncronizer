"""Independent expected plans and shared invalid declaration fixtures."""
from pathlib import Path
import tempfile
import unittest

from dotfiles_core.install_config import DeclarationError, ROOT, read_items

FIXTURES = ROOT / 'tests/fixtures/install'


def materialize(name: str, destination: Path) -> Path:
    source = FIXTURES / name
    edits_path = source / 'edits.tsv'
    if not edits_path.exists():
        return source
    lines = (FIXTURES / 'discovery/tool.conf').read_text().splitlines()
    deleted = {}
    inserted = {}
    for line in edits_path.read_text().splitlines():
        if line.startswith('#'):
            continue
        operation, number, old, new = line.split('\t')
        index = int(number)
        if not 1 <= index <= len(lines) + 1:
            raise AssertionError('Fixture edit is out of bounds')
        if operation == 'delete':
            if index in deleted or lines[index - 1] != old:
                raise AssertionError('Fixture deletion does not match source')
            deleted[index] = old
        elif operation == 'insert':
            inserted.setdefault(index, []).append(new)
        else:
            raise AssertionError('Unknown fixture operation')
    output = []
    for number, line in enumerate([*lines, None], 1):
        output.extend(inserted.get(number, []))
        if line is not None and number not in deleted:
            output.append(line)
    destination.mkdir()
    (destination / 'tool.conf').write_text('\n'.join(output) + '\n')
    return destination


class InstallConfigurationTests(unittest.TestCase):
    def test_shared_fixtures(self):
        fields = (ROOT / 'contracts/schema/install-plan.fields').read_text().splitlines()
        # These fields are assigned by planning, after declaration normalization.
        planning = {'action', 'reason', 'source_origin', 'state', 'schema_version', 'decision_reason', 'source_url'}
        with tempfile.TemporaryDirectory() as directory:
            for line in (FIXTURES / 'cases.tsv').read_text().splitlines():
                if line.startswith('#') or not line:
                    continue
                name, platform, mirrors, wsl, outcome = line.split('\t')
                with self.subTest(name=name):
                    path = materialize(name, Path(directory) / name)
                    if outcome == 'error':
                        with self.assertRaises(DeclarationError):
                            read_items(path, platform)
                    else:
                        actual = read_items(path, platform)
                        expected = [dict(zip(fields, row.split('|'), strict=True)) for row in (FIXTURES / name / 'expected.plan').read_text().splitlines()]
                        self.assertEqual([item['id'] for item in actual], [item['id'] for item in expected])
                        for item, row in zip(actual, expected, strict=True):
                            for field in set(fields) - planning:
                                self.assertEqual(item.get(field, ''), row[field], f'{name}/{field}')
                            source = item.get('mirror_url', '') if mirrors == '1' and item.get('mirror_url') else item.get('source_url', '')
                            self.assertEqual(source, row['source_url'])

    def test_invalid_unselected_platform_blocks_output(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / 'tool.conf').write_text('[macos]\norder=1\nmethod=brew\nsource_kind=default\npackages=tool\n[windows]\norder=1\nmethod=winget\nsource_kind=winget\nsource_repo=winget\npackages=Vendor.Tool\ndepends_on=missing\n')
            with self.assertRaises(DeclarationError):
                read_items(path, 'macos')

    def test_repository_all_platforms(self):
        for platform in ('linux.apt', 'linux.dnf', 'linux.pacman', 'macos', 'windows'):
            with self.subTest(platform=platform):
                self.assertTrue(read_items(ROOT / 'software/items', platform))
