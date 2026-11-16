"""Execution decisions consume supplied observations, never install software."""
import unittest

from dotfiles_core.install_config import ROOT, rows
from dotfiles_core.execution_rules import PolicyError, execution_policy, execution_result, install_decision, probe_result


class ExecutionRuleTests(unittest.TestCase):
    def test_policies(self):
        root = ROOT / 'tests/fixtures/install-policy'
        for name, outcome in rows(root / 'cases.tsv'):
            with self.subTest(name=name):
                if outcome == 'invalid':
                    with self.assertRaises(PolicyError):
                        execution_policy('apt', 'probe', root / f'{name}.tsv')
                else:
                    policy = execution_policy('apt', 'probe', root / f'{name}.tsv')
                    self.assertEqual(policy.TimeoutSeconds, 8 if name == 'override' else 30)
                    self.assertEqual(policy.SuccessCodes, [0])
        self.assertEqual(execution_policy('msvc', 'modify').SuccessCodes, [0, 3010])
        self.assertEqual(execution_policy('winget', 'install').SuccessCodes, [0])
        self.assertEqual(execution_policy('homebrew', 'download').TimeoutSeconds, 120)

    def test_probes(self):
        for state, action, reason in rows(ROOT / 'tests/fixtures/execution/probes.tsv'):
            with self.subTest(state=state):
                if action == 'invalid':
                    with self.assertRaises(PolicyError):
                        probe_result(state)
                else:
                    self.assertEqual(probe_result('' if state == '<empty>' else state), {'Action': action, 'Reason': reason})

    def test_decisions(self):
        for line in (ROOT / 'tests/fixtures/install/decisions.tsv').read_text().splitlines():
            if line.startswith('#'):
                continue
            state, mode, command, present, action, reason, output_state = line.split('|')
            with self.subTest(line=line):
                decision = install_decision(state, mode, command, present == '1')
                self.assertEqual(decision.text(), '|'.join((action, reason, output_state, reason)))
        self.assertEqual(install_decision('', 'normal', discovery=True).DecisionReason, 'no-discovery-match')
        for state, mode in (('unknown', 'normal'), ('', 'bad-mode')):
            with self.assertRaises(PolicyError):
                install_decision(state, mode)

    def test_outcomes(self):
        for code, dry, status, reason in rows(ROOT / 'tests/fixtures/execution/outcomes.tsv'):
            with self.subTest(code=code, dry=dry):
                self.assertEqual(execution_result(int(code), dry == '1'), {'Status': status, 'Reason': reason})
