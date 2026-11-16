# shellcheck shell=bash
# Session lifetime and durable stage reports.
# shellcheck source=atomic-report.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/atomic-report.sh"
workflow_run_unlocked() {
  dotfiles_python_init || return
  local context="$1"
  workflow_preflight "$context"
  if [[ "$(workflow_context_get "$context" plan_only)" == 1 ]];then workflow_print_plan "$context";return;fi
  workflow_confirm "$context"
  dotfiles_request workflow-session-native style unix native_shell "$BASH" directory "$context"
}

workflow_run() {
  dotfiles_python_init || return
  local dry
  dry="$(workflow_context_get "$1" dry_run)"
  if [[ "$(workflow_context_get "$1" plan_only)" == 1 ]];then dry=1;fi
  deployment_run "$dry" workflow_run_unlocked "$1"
}
