from pathlib import Path
import unittest
from unittest.mock import patch

from dotfiles_core.apply_entry import request, session_path
from dotfiles_core.contracts import Contract
from dotfiles_core.errors import AdapterError
from dotfiles_core.protocol import Result
from test_apply_execution import row


class Native:
    def __init__(self):
        self.calls = []
        self.fs = self
        self.adapter = self
        self.operations = {'apply-query': ('shell',)}

    def value(self, query, path):
        self.calls.append((query, path))
        return path

    def entry(self, path):
        return type('Entry', (), {'kind': 'absent'})()

    def invoke(self, operation, context):
        self.calls.append((operation, context))
        return Result(operation, 0, {})


class ApplyEntryTests(unittest.TestCase):
    def context(self, **changes):
        return dict(style='unix', native_shell='/bin/bash', dry='0', plan_only='0',
                    config='/config', backup='/backup', owner_pid='123', repo='/repo',
                    selection=[], mirrors='0') | changes

    def test_candidates_survive_execution_and_are_cleaned_on_failure(self):
        scratch = []
        native = Native()

        def plan(operation, context):
            directory = Path(context['render_scratch'])
            self.assertTrue(directory.is_dir())
            scratch.append(directory)
            return [row('/target')], []

        def execute(*args):
            self.assertTrue(scratch[0].is_dir())
            raise AdapterError('failed', 23)

        with patch('dotfiles_core.apply_entry.NativeExecution', return_value=native), \
             patch('dotfiles_core.apply_entry.plan_request', side_effect=plan), \
             patch('dotfiles_core.apply_entry.execute', side_effect=execute):
            with self.assertRaises(AdapterError):
                request('apply-entry-native', self.context())
        self.assertFalse(scratch[0].exists())

    def test_plan_returns_contract_without_execution(self):
        with patch('dotfiles_core.apply_entry.NativeExecution', return_value=Native()), \
             patch('dotfiles_core.apply_entry.plan_request', return_value=([row('/target')], [])), \
             patch('dotfiles_core.apply_entry.execute') as execute:
            value, lines = request('apply-entry-native', self.context(plan_only='1'))
        self.assertEqual(value, '\n'.join(lines))
        self.assertEqual(Contract.load('apply-plan').read(value)[0]['target'], '/target')
        execute.assert_not_called()

    def test_workflow_configuration_keeps_its_existing_session_path(self):
        native = Native()
        with patch('dotfiles_core.apply_entry.NativeExecution', return_value=native), \
             patch('dotfiles_core.apply_entry.plan_request', return_value=([], [])) as plan, \
             patch('dotfiles_core.apply_entry.execute', return_value=0) as execute:
            context = self.context(style='windows', session='/workflow/configuration')
            del context['backup']
            request('apply-workflow-native', context)
        self.assertEqual(plan.call_args.args[1]['session'], '/workflow/configuration')
        self.assertEqual(execute.call_args.args[1], '/workflow/configuration')
        self.assertEqual(native.calls, []) # Only selected roots are resolved by the planner.

    def test_restore_uses_whole_native_boundary_without_planning(self):
        native = Native()
        with patch('dotfiles_core.apply_entry.NativeExecution', return_value=native):
            request('apply-entry-native', self.context(restore='/journal', plan_only='1'))
        self.assertEqual(native.calls, [('apply-restore', {'journal': '/journal', 'dry': True})])
        with patch('dotfiles_core.apply_entry.NativeExecution', return_value=Native()):
            with self.assertRaises(AdapterError) as failure:
                request('apply-entry-native', self.context(restore='/journal', selection=['tool']))
        self.assertEqual(failure.exception.exit_code, 2)

    def test_session_collision_uses_suffix_without_creating_directory(self):
        observed = []
        def exists(path):
            observed.append(path)
            return len(observed) == 1
        candidate = session_path('/backup', 'unix', '123', exists)
        self.assertTrue(candidate.endswith('-123.1'))
        self.assertEqual(candidate, observed[1])
