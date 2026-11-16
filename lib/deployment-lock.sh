# shellcheck shell=bash
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/python.sh"
# Load the shared native facade only when an action needs a lease. Filesystem
# observation adapters source this file frequently but must remain lightweight.
deployment_run() {
  local viewer_lease_library
  dotfiles_python_init || return
  viewer_lease_library="$("$dotfiles_python_executable" -c 'from dotfiles_viewer.install_config import ROOT; print(ROOT / "native/deployment-lock.sh")')" || return
  source "$viewer_lease_library"
  deployment_run "$@"
}
