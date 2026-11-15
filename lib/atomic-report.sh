# shellcheck shell=bash
# Publish complete contents on the destination filesystem. Existing readers see
# either the old inode or the new inode; an interrupted writer cannot truncate it.
atomic_report_write() (
  local destination="$1" mode="${2:-replace}" temporary
  [[ "$mode" == replace || "$mode" == create ]] || return 2
  [[ ! -L "$destination" && ! -d "$destination" ]] || return 1
  temporary="$(mktemp "${destination}.tmp.XXXXXX")" || return
  # shellcheck disable=SC2064
  trap "$(printf 'rm -f -- %q' "$temporary")" EXIT
  cat > "$temporary" || return
  if [[ "$mode" == create ]];then
    # link(2) fails atomically if another writer claimed this destination.
    ln -- "$temporary" "$destination" || return
  else
    mv -f -- "$temporary" "$destination" || return
  fi
)
