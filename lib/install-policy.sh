# shellcheck shell=bash
install_policy_library_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=python.sh
source "$install_policy_library_dir/python.sh"
install_execution_policy() {
  dotfiles_python execution-policy --method="${1:-*}" --native-operation="$2" --path="${3:-${install_policy_file_override:-$install_policy_library_dir/../install/schema/execution.tsv}}"
}
install_probe_capture() {
  local method="$1" policy
  shift
  policy="$(install_execution_policy "$method" probe)" || return
  command_capture "${policy%%|*}" "$@"
}
