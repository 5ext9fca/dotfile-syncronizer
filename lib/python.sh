# shellcheck shell=bash
python_library_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

# Call once in the owning shell before changing PATH; do not use command substitution.
dotfiles_python_init() {
  local selected resolved parent
  [[ -z "${dotfiles_python_executable:-}" ]] || return 0
  selected="${DOTFILES_PYTHON-$python_library_dir/../.venv/bin/python}"
  case "$OSTYPE" in
    msys*|cygwin*)
      selected="${DOTFILES_PYTHON-$python_library_dir/../.venv/Scripts/python.exe}"
      if [[ "$selected" == *[\\/]* ]]; then selected="$(cygpath -u "$selected")" || return; fi
      ;;
  esac
  [[ -n "$selected" ]] || { printf 'error: DOTFILES_PYTHON must name one interpreter\n' >&2; return 2; }
  if [[ "$selected" == */* ]]; then
    [[ -f "$selected" && -x "$selected" ]] || { printf 'error: Python interpreter unavailable: %s\n' "$selected" >&2; return 2; }
    resolved="$selected"
  else
    resolved="$(type -P -- "$selected")" || { printf 'error: Python interpreter unavailable: %s\n' "$selected" >&2; return 2; }
  fi
  parent="${resolved%/*}"
  [[ "$parent" != "$resolved" ]] || parent=.
  resolved="$(cd -- "$parent" && pwd -P)/${resolved##*/}"
  "$resolved" -X utf8 -B "$python_library_dir/../dotfiles_core/launch.py" runtime-check >/dev/null || return
  dotfiles_python_executable="$resolved"
  export DOTFILES_PYTHON="$resolved"
}

dotfiles_python() {
  dotfiles_python_init || return
  DOTFILES_PYTHON="$dotfiles_python_executable" "$dotfiles_python_executable" -X utf8 -B "$python_library_dir/../dotfiles_core/launch.py" "$@"
}

# Keep large documents out of argv and preserve stdin for platform commands.
dotfiles_request() (
  local operation="$1" scratch code
  shift
  [[ $(( $# % 2 )) == 0 ]] || return 2
  dotfiles_python_init || return
  scratch="$(mktemp -d)" || return
  # shellcheck disable=SC2064
  trap "$(printf 'rm -rf -- %q' "$scratch")" EXIT
  # printf is a Bash builtin: even large values never enter an external argv.
  printf '%s\0' "$operation" "$@" > "$scratch/arguments"
  if dotfiles_python core-request --arguments-file "$scratch/arguments" --request "$scratch/request.json" --result "$scratch/result.json";then code=0;else code=$?;fi
  dotfiles_python core-result --result "$scratch/result.json" --expected-operation "$operation" --code "$code"
)
