#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
dry=0 journal='' snapshot=''
usage() {
  printf '%s\n' 'Usage: apply.sh --snapshot FILE [--dry-run|--plan]' '       apply.sh --restore JOURNAL [--dry-run|--plan]' 'Configuration is copied from a snapshot. Use snapshot/snapshot.sh create to capture it.'
}
while (( $# ));do
  case "$1" in
    --snapshot|--restore)
      [[ $# -ge 2 && -n "$2" ]] || { usage >&2;exit 2; }
      case "$1" in --snapshot) snapshot="$2" ;; --restore) journal="$2" ;; esac
      shift 2 ;;
    --dry-run|--plan) dry=1;shift ;;
    -h|--help) usage;exit 0 ;;
    *) usage >&2;exit 2 ;;
  esac
done
if [[ -n "$journal" && -z "$snapshot" ]];then
  source "$repo_root/lib/apply-items.sh"
  dotfiles_python_init
  apply_restore "$journal" "$dry"
elif [[ -n "$snapshot" && -z "$journal" ]];then
  args=(restore --snapshot "$snapshot" --configuration-only)
  [[ "$dry" == 0 ]] || args+=(--dry-run)
  exec "$repo_root/snapshot/snapshot.sh" "${args[@]}"
else
  usage >&2;exit 2
fi
