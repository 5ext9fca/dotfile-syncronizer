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
china_mirrors=1
results_path=''
stage_result_path=''
restore_journal=''
selection=''
mirror_config="${DOTFILES_MIRROR_CONFIG:-$repo_root/mirrors/current.conf}"
usage() {
  cat <<'HELP'
Usage: apply.sh [--dry-run|--plan] [--results FILE] [--no-mirrors] [component ...]
       apply.sh --restore JOURNAL [--dry-run|--plan]

Deploy declared components with complete preflight, backups and recovery journals.
Unix files are hard-linked; application-owned exclusions remain untouched.
Mirrors apply the repository's current configuration by default. --no-mirrors skips it.
--plan performs read-only inspection. --dry-run also prints planned operations.
HELP
}
while (( $# ));do
  case "$1" in
    --dry-run) dry_run=1 ;;
    --plan) plan_only=1 ;;
    --stage-result) stage_result_path="$2";shift ;;
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
if [[ -n "$restore_journal" ]];then
  [[ -z "$selection" ]] || { printf 'error: restore cannot select components\n' >&2;exit 2; }
  apply_restore "$restore_journal" "$((dry_run || plan_only))"
  exit
fi
config_home="$(apply_resolve_root "${XDG_CONFIG_HOME:-$HOME/.config}")"
backup_root="$(apply_resolve_root "${DOTFILES_BACKUP_DIR:-$HOME/.dotfiles-backups}")"
session="$(apply_session_path "$backup_root")"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
plan="$(apply_make_plan "$repo_root" "$script_dir/items" "$config_home" "$session" "$selection" "$scratch" "$((dry_run || plan_only))")"
if (( china_mirrors ));then
  plan="$(mirror_make_plan "$mirror_config" apply "$config_home" "$session" "$scratch" "$plan")"
fi
apply_validate_plan "$plan"
if (( plan_only ));then contract_write apply-plan "$plan";exit 0;fi
apply_execute_plan "$plan" "$session" "$dry_run" "$results_path" "$stage_result_path"
printf 'Configuration applied successfully.\n'
