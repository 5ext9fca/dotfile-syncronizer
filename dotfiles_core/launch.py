"""Absolute-path source launcher; works outside the checkout and without pip."""

import os
import sys

# Resolve the source checkout, not the working directory or an installed package.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.dont_write_bytecode = True


def main():
    # Keep the bootstrap parseable by older interpreters so rejection is explicit.
    if sys.version_info[:2] < (3, 15):
        print("error: Python >=3.15 is required; prepare .venv or set DOTFILES_PYTHON.", file=sys.stderr)
        return 2
    from dotfiles_core.cli import main as core_main
    return core_main()


if __name__ == "__main__":
    sys.exit(main())
