#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "$0")" && pwd -P)"
# shellcheck source=../lib/install-items.sh
source "$script_dir/../lib/install-items.sh"
# shellcheck source=../lib/plan-explain.sh
source "$script_dir/../lib/plan-explain.sh"
explain=0
platform='' mirrors=1 wsl=0 items="$script_dir/items"
while (( $# )); do
  case "$1" in
    --platform) platform="$2"; shift ;;
    --items) items="$2"; shift ;;
    --no-china-mirrors) mirrors=0 ;;
    --wsl) wsl=1 ;;
    --explain) explain=1 ;;
    *) printf 'Usage: plan.sh --platform linux.apt|linux.dnf|linux.pacman|macos|windows [--items DIR] [--no-china-mirrors] [--wsl] [--explain]\n' >&2; exit 2 ;;
  esac
  shift
done
[[ -n "$platform" ]] || { printf 'error: --platform is required\n' >&2; exit 2; }
plan="$(install_items_plan "$items" "$platform" "$mirrors" "$wsl" 0)"
if [[ "$explain" == 1 ]];then install_explain_plan "$plan" "$platform" all "$items"
else contract_write install-plan "$plan";fi
