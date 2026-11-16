# shellcheck shell=bash
execution_result_library_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=python.sh
source "$execution_result_library_dir/python.sh"
execution_result() {
  [[ "$1" =~ ^[0-9]+$ && "$2" =~ ^[01]$ ]] || return 1
  dotfiles_python execution-result --code="$1" --dry="$2"
}
