"""Run the core from this checkout without installing a package."""

from dotfiles_core.launch import main


if __name__ == "__main__":
    raise SystemExit(main())
