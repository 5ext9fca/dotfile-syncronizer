#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
suite=core strict=0 list=0 failed=0 passed=0 skipped=0
usage() { printf 'Usage: tests/check.sh [--suite core|cross|dry-run|lint|all] [--strict] [--list]\n'; }
while (( $# )); do
  case "$1" in
    --suite) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; suite="$2"; shift ;;
    --strict) strict=1 ;;
    --list) list=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done
case "$suite" in core|cross|dry-run|lint|all) ;; *) usage >&2; exit 2 ;; esac
case "$(uname -s)" in Linux) host=linux ;; Darwin) host=macos ;; *) printf 'Use tests/check.ps1 on Windows.\n' >&2; exit 2 ;; esac
bash_command="${DOTFILES_TEST_BASH:-$BASH}"
ps_command="${DOTFILES_TEST_POWERSHELL:-pwsh}"
python_command="${DOTFILES_TEST_PYTHON:-${DOTFILES_PYTHON:-$repo_root/.venv/bin/python}}"
cd "$repo_root"
while IFS=$'\t' read -r id group hosts runtime entry arguments; do
  [[ -n "$id" && "$id" != \#* ]] || continue
  [[ "$suite" == all || "$suite" == "$group" ]] || continue
  if [[ " $hosts " != *" $host "* ]]; then
    printf 'SKIP %s: host %s is outside [%s]\n' "$id" "$host" "$hosts"; skipped=$((skipped+1)); continue
  fi
  if (( list )); then printf '%s\t%s\t%s\t%s\n' "$id" "$group" "$runtime" "$entry"; continue; fi
  missing=''; command_args=()
  case "$runtime" in
    bash) command_args=("$bash_command" "$entry") ;;
    powershell) command_args=("$ps_command" -NoProfile -File "$entry") ;;
    python) if [[ -f "$entry" ]];then command_args=("$python_command" -B "$entry");else command_args=("$python_command" -B -m unittest discover -s "$entry" -p 'test_*.py');fi ;;
    *) printf 'error: unknown check runtime: %s\n' "$runtime" >&2; exit 2 ;;
  esac
  if ! command -v "${command_args[0]}" >/dev/null 2>&1; then missing="runtime ${command_args[0]}"; fi
  if [[ "$runtime" == python && -z "$missing" ]] && ! "$python_command" -c 'import sys; assert sys.version_info[:2] == (3, 14)' >/dev/null 2>&1; then missing='Python 3.14 (validation runtime)'; fi
  if [[ "$id" == install-parity ]] && ! command -v "$bash_command" >/dev/null 2>&1; then missing="Bash $bash_command"; fi
  if [[ "$id" == shell-lint ]] && ! command -v "${DOTFILES_TEST_SHELLCHECK:-shellcheck}" >/dev/null 2>&1; then missing='ShellCheck'; fi
  if [[ -n "$missing" ]]; then
    if (( strict )); then printf 'FAIL %s: missing %s\n' "$id" "$missing"; failed=$((failed+1))
    else printf 'SKIP %s: missing %s\n' "$id" "$missing"; skipped=$((skipped+1)); fi
    continue
  fi
  if [[ "$arguments" != - ]]; then
    IFS=' ' read -r -a extra_args <<< "$arguments"
    command_args+=("${extra_args[@]}")
  fi
  if [[ "$id" == install-parity ]]; then command_args+=(-Bash "$bash_command"); fi
  printf 'RUN %s\n' "$id"
  if "${command_args[@]}"; then passed=$((passed+1)); printf 'PASS %s\n' "$id"
  else code=$?; failed=$((failed+1)); printf 'FAIL %s: exit %s\n' "$id" "$code"; fi
 done < "$repo_root/tests/checks/manifest.tsv"
printf 'Checks: passed=%s failed=%s skipped=%s\n' "$passed" "$failed" "$skipped"
(( failed == 0 ))
