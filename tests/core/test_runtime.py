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
                                 'DOTFILES_PYTHON=/missing; dotfiles_python runtime-check',
                                 "test", str(ROOT)], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), sys.executable)

    @unittest.skipIf(os.name == "nt", "Unix wrapper")
    def test_missing_interpreter_has_no_fallback(self):
        for selected in ("", "/missing/python", sys.executable + " -B"):
            result = subprocess.run(["bash", "-c", 'source "$1/lib/python.sh"; dotfiles_python_init',
                                     "test", str(ROOT)], env=dict(os.environ, DOTFILES_PYTHON=selected),
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("error:", result.stderr)
