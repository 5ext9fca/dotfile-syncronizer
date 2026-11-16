# shellcheck shell=bash
python_library_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

# Call once in the owning shell before changing PATH; do not use command substitution.
dotfiles_python_init() {
  local selected resolved
  [[ -z "${dotfiles_python_executable:-}" ]] || return 0
  selected="${DOTFILES_PYTHON-$python_library_dir/../.venv/bin/python}"
  [[ -n "$selected" ]] || { printf 'error: DOTFILES_PYTHON must name one interpreter\n' >&2; return 2; }
  if [[ "$selected" == */* ]]; then
    [[ -f "$selected" && -x "$selected" ]] || { printf 'error: Python interpreter unavailable: %s\n' "$selected" >&2; return 2; }
    resolved="$(cd -- "$(dirname -- "$selected")" && pwd -P)/$(basename -- "$selected")"
  else
    resolved="$(type -P -- "$selected")" || { printf 'error: Python interpreter unavailable: %s\n' "$selected" >&2; return 2; }
    resolved="$(cd -- "$(dirname -- "$resolved")" && pwd -P)/$(basename -- "$resolved")"
  fi
  "$resolved" -B "$python_library_dir/../dotfiles_core/launch.py" runtime-check >/dev/null || return
  dotfiles_python_executable="$resolved"
}

dotfiles_python() {
  dotfiles_python_init || return
  "$dotfiles_python_executable" -B "$python_library_dir/../dotfiles_core/launch.py" "$@"
}
