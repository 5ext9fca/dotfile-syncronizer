#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
usage() {
  cat <<'HELP'
Usage: snapshot.sh create (--profile NAME | --software ID [ID ...]) --output FILE [--dry-run]
       snapshot.sh inspect --snapshot FILE
       snapshot.sh restore --snapshot FILE [--dry-run|--plan] [--configuration-only]

Capture declared local configuration into a new ZIP archive. Restore requires the
same installation branch, CPU architecture and native/WSL environment.
Stop applications that write configuration before capture. Missing paths fail.
HELP
}
[[ $# -gt 0 ]] || { usage >&2;exit 2; }
case "$1" in -h|--help) usage;exit 0 ;; create|inspect|restore) action="$1";shift ;; *) usage >&2;exit 2 ;; esac
profile='' software='' output='' snapshot='' dry=0 configuration_only=0 detach=0
while (( $# ));do
  case "$1" in
    --catalog|--profile|--output|--snapshot)
      [[ $# -ge 2 && -n "$2" ]] || { usage >&2;exit 2; }
      case "$1" in --catalog) export DOTFILES_CATALOG="$2" ;; --profile) profile="$2" ;; --output) output="$2" ;; --snapshot) snapshot="$2" ;; esac
      shift 2 ;;
    --software)
      shift
      [[ $# -gt 0 && "$1" != -* ]] || { usage >&2;exit 2; }
      while (( $# )) && [[ "$1" != -* ]];do software="${software}${software:+ }$1";shift;done ;;
    --dry-run|--plan) dry=1;shift ;;
    --configuration-only) configuration_only=1;shift ;;
    --detach-hardlink) detach=1;shift ;;
    -h|--help) usage;exit 0 ;;
    *) printf 'error: unknown option: %s\n' "$1" >&2;exit 2 ;;
  esac
done
case "$action" in
  create) [[ -n "$output" && -z "$snapshot" && "$configuration_only" == 0 ]] || { usage >&2;exit 2; } ;;
  inspect|restore) [[ -n "$snapshot" && -z "$output$profile$software" ]] || { usage >&2;exit 2; } ;;
esac
source "$repo_root/lib/python.sh"
source "$repo_root/lib/deployment-lock.sh"
dotfiles_python_init
lock_dry="$dry"
[[ "$action" == inspect ]] && lock_dry=1
deployment_run "$lock_dry" dotfiles_request snapshot-native action "$action" native_shell "$BASH" \
  dry "$dry" profile "$profile" software "$software" output "$output" snapshot "$snapshot" configuration_only "$configuration_only" detach_hardlink "$detach"
