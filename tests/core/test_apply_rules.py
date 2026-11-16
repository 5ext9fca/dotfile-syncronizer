import unittest

from dotfiles_core.apply_rules import read_items, ApplyConfigError, excluded, relative, validate_plan
from dotfiles_core.install_config import ROOT


class ApplyRuleTests(unittest.TestCase):
    def test_final_plan_versions_actions_and_mirror_target_collisions(self):
        first = dict(schema_version='1', action='copy', target='/config/tool', reason='new')
        validate_plan([first], 'unix')
        validate_plan([first], 'windows')
        with self.assertRaisesRegex(ApplyConfigError, 'Overlapping'):
            validate_plan([first, dict(first, reason='replace')], 'unix')
        validate_plan([first, dict(first, action='skip', reason='excluded')], 'unix')
        for style in ('unix', 'windows'):
            for invalid in (dict(first, schema_version='99'), dict(first, action='unknown')):
                with self.assertRaises(ApplyConfigError):
                    validate_plan([first, invalid], style)
        with self.assertRaises(ApplyConfigError):
            validate_plan([dict(first, action='hardlink')], 'windows')

    def test_shared_declarations(self):
        fixtures = ROOT / 'tests/fixtures/apply'
        for line in (fixtures / 'cases.tsv').read_text().splitlines():
            if not line or line.startswith('#'):
                continue
            name, platform, outcome = line.split('\t')
            with self.subTest(name=name, platform=platform):
                if outcome == 'error':
                    with self.assertRaises((ApplyConfigError, OSError)):
                        read_items(fixtures / name, platform)
                else:
                    actual = '\n'.join(item.line() for item in read_items(fixtures / name, platform))
                    self.assertEqual(actual, (fixtures / name / 'expected.txt').read_text().rstrip('\n'))

    def test_exclusion_subtrees_and_relative_paths(self):
        self.assertTrue(excluded('private/file', 'private;cache'))
        self.assertTrue(excluded('cache', 'private;cache'))
        self.assertFalse(excluded('private-other/file', 'private;cache'))
        self.assertFalse(excluded('ordinary/file', ''))
        self.assertTrue(relative('中文/directory with spaces/file'))
        for path in ('', '/absolute', 'a//b', 'a/../b', 'a/./b', 'C:/path', 'a\\b', 'a/'):
            with self.subTest(path=path):
                self.assertFalse(relative(path))
