#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
if [[ "${1:-}" == --help || "${1:-}" == -h ]];then
  printf 'Usage: apply.sh --snapshot FILE [--dry-run|--plan] [--detach-hardlink]\n'
  exit 0
fi
source "$repo_root/lib/python.sh"
dotfiles_python_init
args=()
for arg in "$@";do
  [[ "$arg" != --plan ]] || arg=--dry-run
  args+=("$arg")
done
exec "$dotfiles_python_executable" -m dotfile_viewer snapshot apply "${args[@]}"
