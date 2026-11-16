# shellcheck shell=bash
apply_library_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=command.sh
source "$apply_library_dir/command.sh"
# shellcheck source=atomic-report.sh
source "$apply_library_dir/atomic-report.sh"
# shellcheck source=stage-result.sh
source "$apply_library_dir/stage-result.sh"
# shellcheck source=apply-fs.sh
source "$apply_library_dir/apply-fs.sh"
# shellcheck source=apply-plan.sh
source "$apply_library_dir/apply-plan.sh"
# shellcheck source=../apply/handlers/files.sh
source "$apply_library_dir/../apply/handlers/files.sh"

apply_validate_plan() {
  dotfiles_request apply-validate style unix text "$1"
}

apply_execute_plan_unlocked() {
  dotfiles_request apply-execute-native style unix native_shell "$BASH" text "$1" session "$2" dry "$3" results "${4:-}" metadata "${5:-}"
}
# shellcheck source=apply-restore.sh
source "$apply_library_dir/apply-restore.sh"

# shellcheck source=deployment-lock.sh
source "$apply_library_dir/deployment-lock.sh"
apply_execute_plan() {
  dotfiles_python_init || return
  local plan="$1"
  shift
  if [[ "$plan" == '# dotfiles|'* ]];then plan="$(contract_read apply-plan "$plan")" || return;fi
  contract_validate_rows apply-plan "$plan" || return
  apply_validate_plan "$plan" || return
  deployment_run "$2" apply_execute_plan_unlocked "$plan" "$@"
}
apply_restore_request() { dotfiles_request apply-restore-native style unix native_shell "$BASH" journal "$1" dry "$2"; }
apply_restore() { dotfiles_python_init || return;deployment_run "$2" apply_restore_request "$@"; }
