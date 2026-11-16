#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "$0")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"
# shellcheck source=../lib/apply-items.sh
source "$repo_root/lib/apply-items.sh"
# shellcheck source=../lib/mirrors.sh
source "$repo_root/lib/mirrors.sh"
dry_run=0
plan_only=0
china_mirrors=0
results_path=''
stage_result_path=''
restore_journal=''
selection=''
profile_name=''
# shellcheck source=../lib/workflow-profile.sh
source "$repo_root/lib/workflow-profile.sh"
mirror_config="${DOTFILES_MIRROR_CONFIG:-$repo_root/mirrors/current.conf}"
usage() {
  cat <<'HELP'
Usage: apply.sh [--dry-run|--plan] [--results FILE] [--china-mirrors] [--profile NAME | component ...]
       apply.sh --restore JOURNAL [--dry-run|--plan]

Deploy declared components with complete preflight, backups and recovery journals.
Unix files are hard-linked; application-owned exclusions remain untouched.
Without components, use the platform default profile. Only configurations are applied.
Mirrors require --china-mirrors; --no-mirrors remains an explicit opt-out.
--plan performs read-only inspection. --dry-run also prints planned operations.
HELP
}
while (( $# ));do
  case "$1" in
    --dry-run) dry_run=1 ;;
    --plan) plan_only=1 ;;
    --stage-result) stage_result_path="$2";shift ;;
    --profile) [[ $# -ge 2 && -n "$2" ]] || { usage >&2;exit 2; };profile_name="$2";shift ;;
    --results) [[ $# -ge 2 ]] || { usage >&2;exit 2; };results_path="$2";shift ;;
    --restore) [[ $# -ge 2 ]] || { usage >&2;exit 2; };restore_journal="$2";shift ;;
    --mirror-config) [[ $# -ge 2 ]] || { usage >&2;exit 2; };mirror_config="$2";shift ;;
    --china-mirrors) china_mirrors=1 ;;
    --no-mirrors) china_mirrors=0 ;;
    -h|--help) usage;exit 0 ;;
    -*) printf 'error: unknown option: %s\n' "$1" >&2;exit 2 ;;
    *) selection="${selection}${1}"$'\n' ;;
  esac
  shift
done
dotfiles_python_init
if [[ -n "$restore_journal" ]];then
  [[ -z "$selection" && -z "$profile_name" ]] || { printf 'error: restore cannot select components\n' >&2;exit 2; }
  apply_restore "$restore_journal" "$((dry_run || plan_only))"
  exit
fi
[[ -z "$selection" || -z "$profile_name" ]] || { printf 'error: components and --profile are mutually exclusive\n' >&2;exit 2; }
if [[ -z "$selection" ]];then
  if [[ -z "$profile_name" ]];then
    case "$(uname -s)" in Darwin) profile_name=macos ;; *) profile_name=linux ;; esac
    if [[ -r /proc/sys/kernel/osrelease ]] && grep -qi microsoft /proc/sys/kernel/osrelease;then profile_name=wsl;fi
  fi
  profile="$(workflow_read_profile "$(workflow_profile_path "$repo_root" "$profile_name")")"
  selection="$(workflow_profile_value "$profile" components | tr ' ' '\n' | cut -d : -f1)"
fi
deployment_run "$((dry_run || plan_only))" dotfiles_request apply-entry-native \
  style unix native_shell "$BASH" kind configuration repo "$repo_root" owner_pid "$$" \
  dry "$dry_run" plan_only "$plan_only" restore "$restore_journal" selection "$selection" \
  roots "$(printf 'home|%s\nconfig_home|%s\n' "${HOME:-}" "${XDG_CONFIG_HOME:-${HOME:+$HOME/.config}}")" config "${XDG_CONFIG_HOME:-${HOME:+$HOME/.config}}" backup "${DOTFILES_BACKUP_DIR:-$HOME/.dotfiles-backups}" \
  results "$results_path" metadata "$stage_result_path" mirrors "$china_mirrors" mirror_config "$mirror_config" \
  manager "$(china_mirror_detect_package_manager)" cargo_home "${CARGO_HOME:-$HOME/.cargo}" npm_config "${NPM_CONFIG_USERCONFIG:-$HOME/.npmrc}"
