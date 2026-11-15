#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
  printf 'error: linux.sh must be run on Linux or inside WSL\n' >&2
  exit 1
fi

dry_run=0
plan_only=0
results_path=
only_stage=
from_stage=
resume_session=
mirrors_explicit=0
session_id="${DOTFILES_WORKFLOW_SESSION_ID:-$(date +%Y%m%d-%H%M%S)-$$-$RANDOM}"
assume_yes=0
china_mirrors=1
package_manager=

usage() {
  cat <<'EOF'
Usage: ./install/linux.sh [--dry-run|--plan] [--results FILE] [--yes] [--china-mirrors|--no-china-mirrors]

Stages: --only-stage NAME or --from-stage NAME (packages, configuration, mirrors, shell).
--resume SESSION continues a failed session with its saved stage selection and mirror mode.
--results FILE writes the workflow summary; component reports live in the session directory.

Installs the active dotfiles dependencies using whichever package manager is
available (Pacman, APT, or DNF), hard-links configurations, and changes the
login shell to Fish. WezTerm is skipped inside WSL.

Mainland China download mirrors are used during installation; persistent
settings are initialized after installation. --no-china-mirrors skips mirror
setup without reverting existing settings.
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --dry-run) dry_run=1 ;;
    --plan) plan_only=1 ;;
    --results|--only-stage|--from-stage|--session-id|--resume)
      [[ $# -ge 2 && -n "$2" ]] || { usage >&2; exit 2; }
      case "$1" in
        --resume) resume_session="$2" ;;
        --results) results_path="$2" ;;
        --only-stage) only_stage="$2" ;;
        --from-stage) from_stage="$2" ;;
        --session-id) session_id="$2" ;;
      esac
      shift ;;
    --yes) assume_yes=1 ;;
    --china-mirrors) china_mirrors=1;mirrors_explicit=1 ;;
    --no-china-mirrors) china_mirrors=0;mirrors_explicit=1 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'error: unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

[[ -r /etc/os-release ]] || {
  printf 'error: /etc/os-release is required for distribution detection\n' >&2
  exit 1
}
# shellcheck disable=SC1091
source /etc/os-release
distro_name="${PRETTY_NAME:-Linux}"

if command -v pacman >/dev/null 2>&1; then
  package_manager=pacman
elif command -v apt-get >/dev/null 2>&1; then
  package_manager=apt
elif command -v dnf >/dev/null 2>&1; then
  package_manager=dnf
else
  printf 'error: no supported package manager found (pacman, apt-get, or dnf) on %s\n' "$distro_name" >&2
  exit 1
fi

inside_wsl=0
if [[ -r /proc/sys/kernel/osrelease ]] && grep -qi microsoft /proc/sys/kernel/osrelease; then
  inside_wsl=1
fi

printf 'Detected Linux distribution: %s (package manager: %s)\n' "$distro_name" "$package_manager" >&2

script_dir="$(cd -- "$(dirname -- "$0")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"
# shellcheck source=../lib/workflow.sh
source "$repo_root/lib/workflow.sh"
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
backup_root="${DOTFILES_BACKUP_DIR:-$HOME/.dotfiles-backups}"

export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
profile_name=linux
if (( inside_wsl ));then profile_name=wsl;fi
workflow_main repo_root "$repo_root" platform "linux.$package_manager" profile_name "$profile_name" \
  distro_id "${ID:-}" distro_codename "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}" \
  dry_run "$dry_run" plan_only "$plan_only" results_path "$results_path" only_stage "$only_stage" from_stage "$from_stage" \
  resume_session "$resume_session" mirrors_explicit "$mirrors_explicit" \
  session_id "$session_id" config_home "$config_home" backup_root "$backup_root" brew_cmd '' brew_prefix '' \
  assume_yes "$assume_yes" user "$USER" china_mirrors "$china_mirrors" inside_wsl "$inside_wsl" \
  mirror_config "${DOTFILES_MIRROR_CONFIG:-$repo_root/mirrors/current.conf}"
