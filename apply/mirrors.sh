#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "$0")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"
# shellcheck source=../lib/apply-items.sh
source "$repo_root/lib/apply-items.sh"
# shellcheck source=../lib/mirrors.sh
source "$repo_root/lib/mirrors.sh"
mode=apply dry_run=0 plan_only=0
mirror_config="${DOTFILES_MIRROR_CONFIG:-$repo_root/mirrors/current.conf}"
results=''
stage_result_path=''
while (( $# ));do
  case "$1" in
    --initialize) mode=initialize ;;
    --dry-run) dry_run=1 ;;
    --plan) plan_only=1 ;;
    --config) mirror_config="$2";shift ;;
    --stage-result) stage_result_path="$2";shift ;;
    --results) results="$2";shift ;;
    *) printf 'Usage: mirrors.sh [--initialize] [--dry-run|--plan] [--config FILE] [--results FILE]\n' >&2;exit 2 ;;
  esac
  shift
done
config_home="$(apply_resolve_root "${XDG_CONFIG_HOME:-$HOME/.config}")"
backup_root="$(apply_resolve_root "${DOTFILES_BACKUP_DIR:-$HOME/.dotfiles-backups}")"
session="$(apply_session_path "$backup_root")"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
plan="$(mirror_make_plan "$mirror_config" "$mode" "$config_home" "$session" "$scratch" '')"
apply_validate_plan "$plan"
if (( plan_only ));then contract_write apply-plan "$plan";exit 0;fi
apply_execute_plan "$plan" "$session" "$dry_run" "$results" "$stage_result_path"
