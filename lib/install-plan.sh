# shellcheck shell=bash
# The complete declaration/observation request is coordinated by Python.
install_items_plan() {
  dotfiles_request install-plan-native style unix native_shell "$BASH" directory "$1" platform "$2" mirrors "${3:-1}" wsl "${4:-0}" inspect "${5:-1}" native_context "${6:-}" policy_path "${install_policy_file_override:-$install_policy_library_dir/../install/schema/execution.tsv}"
}
