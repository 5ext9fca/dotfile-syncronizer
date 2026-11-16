"""Shared profile/stage fixtures retain independent expected wire output."""
import unittest

from dotfiles_core.install_config import ROOT, rows
from dotfiles_core.workflow_rules import WorkflowRuleError, profile_text, read_profile, stage_plan


class WorkflowRuleTests(unittest.TestCase):
    def test_profiles(self):
        root = ROOT / 'tests/fixtures/workflow'
        expected = (root / 'expected.txt').read_text().splitlines()
        for name, outcome in rows(root / 'cases.tsv'):
            with self.subTest(name=name):
                if outcome == 'invalid':
                    with self.assertRaises(WorkflowRuleError):
                        read_profile(root / f'{name}.conf')
                else:
                    self.assertEqual(profile_text(read_profile(root / f'{name}.conf')), expected)

    def test_stages(self):
        root = ROOT / 'tests/fixtures/workflow/stages'
        for name, platform, profile, only, start, mirrors, registry, outcome in rows(root / 'cases.tsv'):
            with self.subTest(name=name):
                path = ROOT / 'workflow/schema/stages.tsv' if registry == '-' else root / registry
                arguments = (platform, read_profile(root / f'{profile}.conf'), '' if only == '-' else only,
                             '' if start == '-' else start, mirrors == '1', path)
                if outcome == 'invalid':
                    with self.assertRaises(WorkflowRuleError):
                        stage_plan(*arguments)
                else:
                    self.assertEqual([stage.text() for stage in stage_plan(*arguments)],
                                     (root / f'{name}.expected').read_text().splitlines())

    def test_format_follows_registry_order(self):
        profile = {'shell': 'none', 'install': 'all', 'ignored': 'value'}
        self.assertEqual(profile_text(profile), ['install=all', 'shell=none'])
