"""Internal core entry point. Public script CLIs remain platform-owned."""

import argparse
import sys

from dotfiles_core.errors import CoreError
from dotfiles_core.runtime import require_runtime


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("runtime-check",))
    args = parser.parse_args()
    try:
        require_runtime()
        if args.operation == "runtime-check":
            # Do not resolve symlinks: a venv executable must retain its venv path.
            print(sys.executable)
        return 0
    except CoreError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
