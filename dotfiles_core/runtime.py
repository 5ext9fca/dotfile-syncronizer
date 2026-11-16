"""Runtime policy. No downloads, package installation, or PATH fallback."""

import sys
from collections.abc import Sequence

from dotfiles_core.errors import RuntimeRequirementError

MINIMUM_VERSION = (3, 14)


def require_runtime(version: Sequence[int] | None = None) -> None:
    actual = sys.version_info if version is None else version
    if tuple(actual[:2]) < MINIMUM_VERSION:
        raise RuntimeRequirementError(
            "Python >=3.14 is required; prepare the checkout .venv or set "
            "DOTFILES_PYTHON to a single interpreter path or command name."
        )
