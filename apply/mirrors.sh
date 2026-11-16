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
dotfiles_python_init
deployment_run "$((dry_run || plan_only))" dotfiles_request apply-entry-native \
  style unix native_shell "$BASH" kind mirrors repo "$repo_root" owner_pid "$$" \
  dry "$dry_run" plan_only "$plan_only" mode "$mode" \
  config "${XDG_CONFIG_HOME:-$HOME/.config}" backup "${DOTFILES_BACKUP_DIR:-$HOME/.dotfiles-backups}" \
  results "$results" metadata "$stage_result_path" mirror_config "$mirror_config" \
  manager "$(china_mirror_detect_package_manager)" cargo_home "${CARGO_HOME:-$HOME/.cargo}" npm_config "${NPM_CONFIG_USERCONFIG:-$HOME/.npmrc}"
