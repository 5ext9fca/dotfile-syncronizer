import unittest

from dotfiles_core.contracts import Contract, ContractError
from dotfiles_core.stage_results import read_stage, initial_stage, update_stage, finish_stage


class StageResultTests(unittest.TestCase):
    def test_artifacts_and_completion(self):
        initial = initial_stage('packages', 'planned-report')
        text = update_stage(initial, 'recovery_journal', '中文/path,one', True)
        self.assertIsNone(update_stage(text, 'recovery_journal', '中文/path,one', True))
        text = update_stage(text, 'child_report', 'other/report', True)
        result = read_stage(finish_stage(text, 23, False, 'missing', False))
        values = {record['key']: record['value'] for record in result}
        self.assertEqual(values['status'], 'failed')
        self.assertEqual(values['retry_stage'], 'packages')
        self.assertEqual(values['exit_code'], '23')
        self.assertEqual(values['report'], '')
        self.assertEqual(values['recovery_journal'], '中文/path,one')
        self.assertEqual(values['child_report'], 'other/report')
        complete = {record['key']: record['value'] for record in read_stage(finish_stage(text, 0, True, 'present', True))}
        self.assertEqual(complete['status'], 'planned')
        self.assertEqual(complete['retry_stage'], '')
        self.assertEqual(complete['report'], 'present')

    def test_invalid_fields_and_duplicates(self):
        base = read_stage(initial_stage('packages', ''))
        schema = Contract.load('stage-result')
        for extra in ({'key': 'stage', 'value': 'other'}, {'key': 'unknown', 'value': 'x'}):
            with self.subTest(extra=extra), self.assertRaises(ContractError):
                read_stage(schema.write([*base, extra]))
        for key, value in (('stage', '../escape'), ('status', 'invented'), ('exit_code', '-1')):
            with self.subTest(key=key), self.assertRaises(ContractError):
                read_stage(update_stage(schema.write(base), key, value, False))
        with self.assertRaises(ContractError):
            read_stage(schema.write(base[:-1]))
        with self.assertRaises(ContractError):
            update_stage(schema.write(base), 'status', 'success', True)
