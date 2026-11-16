# shellcheck shell=bash
# shellcheck source=python.sh
source "${install_library_dir:?}/python.sh"
install_probe_result() { dotfiles_python probe-result --state="$1"; }
