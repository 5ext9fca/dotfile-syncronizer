from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

from dotfiles_core.apply_planning import Entry
from dotfiles_core.protocol import Result
from dotfiles_core.workflow_preflight import PreflightError
from dotfiles_core.workflow_rules import parse_stage_plan, will_install
from dotfiles_core.workflow_shell import ShellSettings, preflight, request


class Native:
    def __init__(self):
        self.commands = {'chsh', 'sudo'}
        self.executable = True
        self.calls = []
        self.adapter = self
        self.operations = {'workflow-query': ('shell',)}

    def entry(self, path):
        return Entry('file', readable=True)

    def query(self, name, arguments):
        self.calls.append((name, arguments))
        return None

    def command_present(self, name):
        self.calls.append(name)
        return name in self.commands

    def string(self, name, arguments):
        self.calls.append((name, arguments))
        return '/bin/fish'

    def boolean(self, name, arguments):
        self.calls.append((name, arguments))
        return self.executable

    def invoke(self, operation, context):
        self.calls.append((operation, context))
        return Result(operation, 0, {})


class WorkflowShellTests(unittest.TestCase):
    def test_future_installation_is_allowed_only_when_packages_selected(self):
        native = Native()
        native.executable = False
        settings = ShellSettings('linux.apt', 'user', '', True, False)
        stages = parse_stage_plan('packages|0|selection||packages\nshell|1|||shell')
        self.assertFalse(will_install(stages, [{'id': 'fish'}], 'fish'))
        with self.assertRaises(PreflightError):
            preflight(settings, False, native)
        native.calls.clear()
        stages = parse_stage_plan('packages|1|||packages\nshell|1|||shell')
        self.assertTrue(will_install(stages, [{'id': 'fish'}], 'fish'))
        preflight(settings, True, native)
        self.assertFalse(any(isinstance(call, tuple) and call[0] == 'executable' for call in native.calls))

    def test_sudo_is_required_only_for_mutating_shell_stage(self):
        native = Native()
        native.commands.remove('sudo')
        for dry, plan in [(True, False), (False, True)]:
            preflight(ShellSettings('macos', 'user', '/brew', dry, plan), False, native)
        with self.assertRaises(PreflightError):
            preflight(ShellSettings('macos', 'user', '/brew', False, False), False, native)

    def test_stage_dispatch_follows_preflight_and_stops_on_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, value in {'platform': 'macos', 'user': 'literal user', 'brew_prefix': '/brew',
                                'dry_run': '1', 'plan_only': '0', 'stages.plan': 'shell|1|||shell',
                                'install.plan': ''}.items():
                (root / name).write_text(value)
            native = Native()
            with patch('dotfiles_core.native_preflight.NativePreflight', return_value=native):
                request('workflow-shell-native', {'directory': directory, 'native_shell': sys.executable})
            self.assertEqual(native.calls[-1], ('workflow-shell-command', {'directory': directory}))
            native.calls.clear()
            native.commands.remove('chsh')
            with patch('dotfiles_core.native_preflight.NativePreflight', return_value=native):
                with self.assertRaises(PreflightError):
                    request('workflow-shell-native', {'directory': directory, 'native_shell': sys.executable})
            self.assertFalse(any(isinstance(call, tuple) and call[0] == 'workflow-shell-command' for call in native.calls))
