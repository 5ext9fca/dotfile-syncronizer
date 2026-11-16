# shellcheck shell=bash
# Compatibility surface only: shared declaration rules live in Python.
# shellcheck source=python.sh
source "${install_library_dir:?}/python.sh"
install_items_read() {
  install_execution_policy '*' install >/dev/null || return
  dotfiles_python install-read --directory "$1" --platform "$2" --schema "$install_library_dir/../install/schema"
}
