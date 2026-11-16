#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'error: macos.sh must be run on macOS\n' >&2
  exit 1
fi

dry_run=0
plan_only=0
results_path=
only_stage=
from_stage=
resume_session=
mirrors_explicit=0
profile_override=
session_id="${DOTFILES_WORKFLOW_SESSION_ID:-$(date +%Y%m%d-%H%M%S)-$$-$RANDOM}"
china_mirrors=1

usage() {
  cat <<'EOF'
Usage: ./install/macos.sh [--profile NAME] [--dry-run|--plan] [--results FILE] [--china-mirrors|--no-china-mirrors]

Stages: --only-stage NAME or --from-stage NAME (packages).
--resume SESSION continues a failed session with its saved stage selection and mirror mode.
--results FILE writes the workflow summary; component reports live in the session directory.

Profiles select software IDs for installation only.
Configuration migration uses snapshot/snapshot.sh; mirrors and shell are not initialized.
--china-mirrors / --no-china-mirrors override the selected profile.
Profiles are read only from workflow/profiles/NAME.conf.
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --dry-run) dry_run=1 ;;
    --plan) plan_only=1 ;;
    --profile|--results|--only-stage|--from-stage|--session-id|--resume)
      [[ $# -ge 2 && -n "$2" ]] || { usage >&2; exit 2; }
      case "$1" in
        --profile) profile_override="$2" ;;
        --resume) resume_session="$2" ;;
        --results) results_path="$2" ;;
        --only-stage) only_stage="$2" ;;
        --from-stage) from_stage="$2" ;;
        --session-id) session_id="$2" ;;
      esac
      shift ;;
    --china-mirrors) china_mirrors=1;mirrors_explicit=1 ;;
    --no-china-mirrors) china_mirrors=0;mirrors_explicit=1 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'error: unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

script_dir="$(cd -- "$(dirname -- "$0")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"
# shellcheck source=../lib/workflow.sh
source "$repo_root/lib/workflow.sh"
dotfiles_python_init
config_home="${XDG_CONFIG_HOME:-${HOME:+$HOME/.config}}"
backup_root="${DOTFILES_BACKUP_DIR:-$HOME/.dotfiles-backups}"

find_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    command -v brew
  elif [[ -x /opt/homebrew/bin/brew ]]; then
    printf '%s\n' /opt/homebrew/bin/brew
  elif [[ -x /usr/local/bin/brew ]]; then
    printf '%s\n' /usr/local/bin/brew
  fi
}

selected_profile="${profile_override:-macos}"
if [[ -n "$resume_session" ]];then
  saved_request="$(workflow_request_read "$resume_session")"
  selected_profile="$(printf '%s\n' "$saved_request" | cut -d '|' -f2)"
fi
profile="$(workflow_read_profile "$(workflow_profile_path "$repo_root" "$selected_profile")")"
brew_cmd=''
if [[ "$(workflow_profile_value "$profile" install)" != none || "$(workflow_profile_value "$profile" shell)" != none ]];then brew_cmd="$(find_homebrew)";fi
if [[ -n "$brew_cmd" ]]; then brew_prefix="$("$brew_cmd" --prefix)"
elif [[ "$(uname -m)" == arm64 ]]; then brew_prefix=/opt/homebrew;brew_cmd="$brew_prefix/bin/brew"
else brew_prefix=/usr/local;brew_cmd="$brew_prefix/bin/brew"; fi
export PATH="$brew_prefix/bin:$HOME/.cargo/bin:$PATH"
workflow_main repo_root "$repo_root" platform macos profile_name "${profile_override:-macos}" \
  dry_run "$dry_run" plan_only "$plan_only" results_path "$results_path" only_stage "$only_stage" from_stage "$from_stage" \
  profile_explicit "${profile_override:+1}" resume_session "$resume_session" mirrors_explicit "$mirrors_explicit" \
  session_id "$session_id" config_home "$config_home" backup_root "$backup_root" brew_cmd "$brew_cmd" brew_prefix "$brew_prefix" \
  assume_yes 1 user "$USER" china_mirrors "$china_mirrors" inside_wsl 0 \
  mirror_config "${DOTFILES_MIRROR_CONFIG:-$repo_root/mirrors/current.conf}"
