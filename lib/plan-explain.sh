# shellcheck shell=bash
# Shared formatting preserves human output independently of persisted contracts.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/python.sh"
install_explain_plan() {
  dotfiles_request install-explain text "$1" platform "$2" selection "${3:-all}" directory "${4:-}"
}
apply_explain_plan() {
  dotfiles_request apply-explain text "$1"
}
