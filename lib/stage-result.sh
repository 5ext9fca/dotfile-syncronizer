# shellcheck shell=bash
stage_result_library_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=data-contract.sh
source "$stage_result_library_dir/data-contract.sh"
# shellcheck source=atomic-report.sh
source "$stage_result_library_dir/atomic-report.sh"
stage_result_read() { dotfiles_request stage-read text "$(cat "$1")"; }
stage_result_init() {
  local document
  document="$(dotfiles_request stage-init stage "$2" report "$3")" || return
  printf '%s\n' "$document" | atomic_report_write "$1" create
}
stage_result_ensure() {
  [[ -n "$1" ]] || return 0
  if [[ -f "$1" ]];then stage_result_read "$1" >/dev/null
  else stage_result_init "$1" "$2" "$3";fi
}
stage_result_get() { dotfiles_request stage-get text "$(cat "$1")" key "$2"; }
stage_result_artifact() {
  local document
  [[ -n "$1" ]] || return 0
  document="$(dotfiles_request stage-update text "$(cat "$1")" key "$2" value "$3" append 1)" || return
  [[ -n "$document" ]] || return 0
  printf '%s\n' "$document" | atomic_report_write "$1"
}
stage_result_finish() {
  local document exists=0
  [[ ! -f "$4" ]] || exists=1
  document="$(dotfiles_request stage-finish text "$(cat "$1")" code "$2" dry "$3" report "$4" report_exists "$exists")" || return
  printf '%s\n' "$document" | atomic_report_write "$1"
}
