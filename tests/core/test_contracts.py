"""External formats retain independent fixtures, including historical reports."""
import unittest

from dotfiles_core.contracts import Contract, ContractError, install_result_read, install_result_row, install_result_show
from dotfiles_core.install_config import ROOT, rows


class ContractTests(unittest.TestCase):
    def test_empty_envelope_and_invalid_record(self):
        schema = Contract.load('git-result')
        self.assertEqual(schema.write([]), '# dotfiles|git-result|1\nkey|status')
        self.assertEqual(schema.read(schema.write([])), [])
        with self.assertRaises(ContractError):
            schema.write([None])

    def test_envelopes(self):
        root = ROOT / 'tests/fixtures/contracts'
        schema = Contract.load('git-result')
        for name, outcome in rows(root / 'cases.tsv'):
            with self.subTest(name=name):
                text = (root / f'{name}.txt').read_text()
                if outcome == 'invalid':
                    with self.assertRaises(ContractError):
                        schema.read(text)
                else:
                    self.assertEqual(schema.read(text), [{'key': 'core.editor', 'status': 'success'}])

    def test_historical_reports(self):
        root = ROOT / 'tests/fixtures/install-reports'
        schema = Contract.load('install-result')
        for line in (root / 'cases.tsv').read_text().splitlines():
            if line.startswith('#'):
                continue
            name, expected = line.split('|', 1)
            with self.subTest(name=name):
                text = (root / f'{name}.txt').read_text()
                if expected == 'error':
                    with self.assertRaises(ContractError):
                        install_result_read(text)
                else:
                    records = install_result_read(text)
                    self.assertEqual([schema.row(record) for record in records], [expected])

    def test_failure_has_no_partial_rows(self):
        with self.assertRaises(ContractError):
            Contract.load('git-result').read('# dotfiles|git-result|1\nkey|status\nkey|success\nbroken')

    def test_writer_rejects_delimiters(self):
        for delimiter in '|\r\n\t':
            with self.subTest(delimiter=delimiter), self.assertRaises(ContractError):
                Contract.load('git-result').write([{'key': 'x' + delimiter, 'status': 'success'}])

    def test_plan_record_version(self):
        schema = Contract.load('apply-plan')
        record = {field: '' for field in schema.fields}
        record['schema_version'] = '99'
        with self.assertRaises(ContractError):
            schema.from_rows(schema.row(record), validate_plan=True)

    def test_observation_is_not_inferred(self):
        item = {'id': 'tool', 'method': 'brew', 'detected_method': 'manual', 'detected_paths': '["路径"]', 'decision_reason': 'discovered-installation'}
        row = install_result_row(item, 'failed', '1', 'probe-failed', observed=False)
        self.assertEqual(row, 'tool|failed|1|probe-failed|brew|||')
        self.assertEqual(install_result_show([{'id': 'tool', 'status': 'failed', 'reason': 'probe-failed'}]), ['  Item tool: failed (probe-failed)'])
