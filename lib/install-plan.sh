# shellcheck shell=bash
# The complete declaration/observation request is coordinated by Python.
install_items_plan() {
  local shell="$BASH" directory="$1" policy="${install_policy_file_override:-$install_policy_library_dir/../install/schema/execution.tsv}"
  # Fields in the framed request bypass MSYS argv path conversion.
  case "$OSTYPE" in
    msys*|cygwin*)
      shell="$(cygpath -am "${BASH%.exe}.exe")" || return
      directory="$(cygpath -am "$directory")" || return
      policy="$(cygpath -am "$policy")" || return
      ;;
  esac
  dotfiles_request install-plan-native style unix native_shell "$shell" directory "$directory" platform "$2" mirrors "${3:-1}" wsl "${4:-0}" inspect "${5:-1}" native_context "${6:-}" policy_path "$policy"
}
