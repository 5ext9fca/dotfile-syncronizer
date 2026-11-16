import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from dotfiles_core.errors import RuntimeRequirementError
from dotfiles_core.runtime import require_runtime

ROOT = Path(__file__).resolve().parents[2]


class RuntimeTests(unittest.TestCase):
    @unittest.skipIf(os.name == 'nt', 'Unix entry points')
    def test_missing_runtime_precedes_deployment(self):
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / 'lease-attempt'
            env = dict(os.environ, DOTFILES_PYTHON='/missing/python')
            for action in ('apply_execute_plan "" "$2/session" 0', 'apply_restore "$2/journal" 0'):
                script = ('source "$1/lib/apply-items.sh"; marker="$2/lease-attempt"; '
                          'deployment_run() { : > "$marker"; }; ' + action)
                result = subprocess.run(['bash', '-c', script, 'test', str(ROOT), directory],
                                        env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertFalse(marker.exists())
                self.assertEqual(list(Path(directory).iterdir()), [])

    @unittest.skipIf(os.name == 'nt', 'Unix entry points')
    def test_help_does_not_require_python(self):
        result = subprocess.run(['bash', str(ROOT / 'apply/apply.sh'), '--help'],
                                env=dict(os.environ, DOTFILES_PYTHON='/missing/python'),
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Usage:', result.stdout)

    def test_powershell_wrapper(self):
        powershell = shutil.which(os.environ.get('DOTFILES_TEST_POWERSHELL', 'pwsh'))
        if powershell is None:
            self.skipTest('PowerShell runtime unavailable')
        script = '''param([string]$Repo, [string]$Python)
$ErrorActionPreference = 'Stop'
$env:DOTFILES_PYTHON = $Python
. (Join-Path $Repo 'lib/python.ps1')
Initialize-DotfilesPython
$env:DOTFILES_PYTHON = '/missing'
Invoke-DotfilesPython -Arguments @('runtime-check')
exit $LASTEXITCODE
'''
        with tempfile.TemporaryDirectory(prefix='dotfiles 中文 ') as directory:
            path = Path(directory) / 'runtime test.ps1'
            path.write_text(script, encoding='utf-8-sig')
            result = subprocess.run([powershell, '-NoProfile', '-File', str(path), str(ROOT), sys.executable],
                                    capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), sys.executable)

    def test_version_policy(self):
        for version in ((2, 7), (3, 11), (3, 14)):
            with self.subTest(version=version), self.assertRaises(RuntimeRequirementError):
                require_runtime(version)
        for version in ((3, 15), (3, 16), (4, 0)):
            require_runtime(version)

    def test_absolute_launcher_outside_checkout(self):
        with tempfile.TemporaryDirectory(prefix="dotfiles 中文 ") as directory:
            result = subprocess.run([sys.executable, "-B", str(ROOT / "dotfiles_core/launch.py"),
                                     "runtime-check"], cwd=directory, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), sys.executable)

    def test_checkout_path_with_unicode_and_spaces(self):
        with tempfile.TemporaryDirectory(prefix="dotfiles 中文 ") as directory:
            checkout = Path(directory)
            shutil.copytree(ROOT / "dotfiles_core", checkout / "dotfiles_core")
            result = subprocess.run([sys.executable, "-B", str(checkout / "dotfiles_core/launch.py"),
                                     "runtime-check"], cwd=checkout.parent, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), sys.executable)

    def test_bootstrap_rejects_simulated_old_version(self):
        code = "import runpy, sys; sys.version_info=(3,14,0); runpy.run_path(sys.argv[1], run_name='__main__')"
        result = subprocess.run([sys.executable, "-B", "-c", code,
                                 str(ROOT / "dotfiles_core/launch.py")], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("Python >=3.15", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    @unittest.skipIf(os.name == "nt", "Unix wrapper")
    def test_single_interpreter_and_fixed_path(self):
        env = dict(os.environ, DOTFILES_PYTHON=sys.executable)
        result = subprocess.run(["bash", "-c", 'source "$1/lib/python.sh"; '
                                 'dotfiles_python_init || exit; '
                                 'DOTFILES_PYTHON=/missing; PATH=/missing; dotfiles_python runtime-check',
                                 "test", str(ROOT)], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), sys.executable)

    @unittest.skipIf(os.name == 'nt', 'Unix wrapper')
    def test_fixed_interpreter_reaches_nested_native_adapter(self):
        with tempfile.TemporaryDirectory() as directory:
            (Path(directory) / 'probe').write_text('present')
            script = ('source "$1/lib/install-items.sh"; dotfiles_python_init || exit; '
                      'DOTFILES_PYTHON=/missing/python; '
                      'dotfiles_request install-discover-native style unix native_shell "$BASH" '
                      'specification manual:file:home:probe native_context ""')
            result = subprocess.run(['bash', '-c', script, 'test', str(ROOT)],
                                    env=dict(os.environ, DOTFILES_PYTHON=sys.executable, HOME=directory),
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('manual|[', result.stdout)

    @unittest.skipIf(os.name == "nt", "Unix wrapper")
    def test_missing_interpreter_has_no_fallback(self):
        for selected in ("", "/missing/python", sys.executable + " -B"):
            result = subprocess.run(["bash", "-c", 'source "$1/lib/python.sh"; dotfiles_python_init',
                                     "test", str(ROOT)], env=dict(os.environ, DOTFILES_PYTHON=selected),
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("error:", result.stderr)
