# shellcheck shell=bash
# The shared Python core validates profiles without evaluating their values.
workflow_profile_library_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=python.sh
source "$workflow_profile_library_dir/python.sh"
workflow_read_profile() {
  dotfiles_python profile-read --path="$1"
}

workflow_profile_value() {
  printf '%s\n' "$1" | awk -v key="$2" 'index($0,key "=")==1 {print substr($0,length(key)+2)}'
}

workflow_profile_components() {
  dotfiles_request install-components associations "$(workflow_profile_value "$1" components)" items "$2"
}

# Python observes selected roots before expanding installation-only edges.
workflow_profile_install_plan() {
  dotfiles_request install-select-native style unix native_shell "$BASH" items "$2" native_context "${3:-}" roots "$(workflow_profile_value "$1" install)" mode "${4:-offline}" policy_path "${install_policy_file_override:-$install_policy_library_dir/../install/schema/execution.tsv}"
}

workflow_profile_path() {
  [[ "$2" =~ ^[a-z][a-z0-9-]*$ ]] || { printf 'error: invalid profile name\n' >&2;return 2; }
  printf '%s/workflow/profiles/%s.conf\n' "$1" "$2"
}
