# shellcheck shell=bash
# One user-wide deployment lease covers workflow, apply, mirrors and recovery.
# Deliberately fail closed after an unclean exit: never infer that orphaned child
# processes stopped merely because the owner PID disappeared.
deployment_release() {
  local path="$1" owner="$2"
  if [[ -f "$path/owner" && "$(cat "$path/owner")" == "$owner" ]];then
    rm -f "$path/owner";rmdir "$path"
  fi
}
deployment_run() (
  local dry="$1" path token owner existing
  shift
  if [[ "$dry" == 1 ]];then "$@";exit;fi
  path="${DOTFILES_DEPLOYMENT_LOCK:-${TMPDIR:-/tmp}/dotfiles-deployment-$UID.lock}"
  if [[ -n "${DOTFILES_DEPLOYMENT_TOKEN:-}" && -f "$path/owner" && ! -L "$path" ]];then
    existing="$(cat "$path/owner")"
    if [[ "${existing##*|}" == "$DOTFILES_DEPLOYMENT_TOKEN" ]];then "$@";exit;fi
  fi
  token="$$-$RANDOM-$RANDOM"
  owner="$(sh -c 'echo "$PPID"')|$(uname -n)|$token" || exit "$?"
  if ! (umask 077;mkdir "$path") 2>/dev/null;then
    printf 'error: deployment lock exists: %s\nInspect its owner and stop all related writers before recovery; do not automatically remove stale locks.\n' "$path" >&2
    [[ ! -f "$path/owner" ]] || cat "$path/owner" >&2
    exit 73
  fi
  printf '%s\n' "$owner" > "$path/owner"
  # Only this acquisition may release the directory; inherited children do not.
  # Freeze ownership now: errexit can unwind local variables before EXIT runs.
  # shellcheck disable=SC2064
  trap "$(printf 'deployment_release %q %q' "$path" "$owner")" EXIT
  export DOTFILES_DEPLOYMENT_LOCK="$path" DOTFILES_DEPLOYMENT_TOKEN="$token"
  "$@"
)
