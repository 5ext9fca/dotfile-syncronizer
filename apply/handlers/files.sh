# shellcheck shell=bash
apply_command() {
  local privilege="$1"
  shift
  if [[ "$privilege" == sudo ]];then command_run mutation 0 0 '' -- sudo "$@";else command_run mutation 0 0 '' -- "$@";fi
}

apply_stage() {
  local action="$1" source="$2" destination="$3" privilege="$4"
  case "$action" in
    hardlink) apply_command "$privilege" ln "$source" "$destination" ;;
    copy) apply_command "$privilege" cp -p "$source" "$destination" ;;
    mkdir) apply_command "$privilege" mkdir "$destination" ;;
    *) printf 'error: unsupported apply action: %s\n' "$action" >&2;return 1 ;;
  esac
}

apply_publish() {
  local source="$1" target="$2" privilege="$3"
  if apply_exists "$target";then printf 'error: target appeared during replacement: %s\n' "$target" >&2;return 1;fi
  apply_command "$privilege" mv -n "$source" "$target" || return
  [[ ! -e "$source" && ! -L "$source" ]] || { printf 'error: publication refused: %s\n' "$target" >&2;return 1; }
}

apply_state_content() { local state="${1#*:}";printf '%s\n' "${state#*:}"; }

apply_undo_one() {
  local action="$1" target="$2" backup="$3" before="$4" after="$5" stage="$6" root="$7" privilege="$8"
  local current candidate='' expected recovery
  apply_parent_safe "$root" "$target" || return
  current="$(apply_state "$target")" || return
  # Failure before the original was moved: nothing to restore.
  if [[ "$current" == "$before" ]];then return 0;fi
  if [[ "$current" != absent && "$current" != "$after" ]];then
    printf 'error: refusing to overwrite modified target: %s\n' "$target" >&2;return 1
  fi
  if [[ "$before" != absent ]];then
    expected="$(apply_state_content "$before")"
    if apply_exists "$stage/old" && [[ "$(apply_content "$stage/old")" == "$expected" ]];then candidate="$stage/old"
    elif [[ -n "$backup" ]] && apply_exists "$backup" && [[ "$(apply_content "$backup")" == "$expected" ]];then candidate="$backup"
    else printf 'error: original backup is missing or modified: %s\n' "$target" >&2;return 1;fi
  fi
  # Keep the installed target available until restoration has succeeded.
  recovery="$(apply_command "$privilege" mktemp -d "$(dirname -- "$target")/.dotfiles-restore.XXXXXX")" || return
  if [[ "$current" != absent ]];then
    apply_command "$privilege" mv "$target" "$recovery/installed" || { apply_command "$privilege" rmdir "$recovery";return 1; }
  fi
  if [[ -n "$candidate" ]];then
    if ! apply_publish "$candidate" "$target" "$privilege";then
      if [[ "$current" != absent ]];then apply_publish "$recovery/installed" "$target" "$privilege" || return;fi
      apply_command "$privilege" rmdir "$recovery"
      return 1
    fi
  fi
  if [[ "$current" != absent ]];then
    # Directories may be removed only when empty; never erase application data.
    if [[ "$action" == mkdir ]];then apply_command "$privilege" rmdir "$recovery/installed" || return
    else apply_command "$privilege" rm -f "$recovery/installed" || return;fi
  fi
  apply_command "$privilege" rmdir "$recovery"
}

apply_transaction_cleanup() {
  local record="$1" journal="$2" sequence="$3" stage="$4" after="$5" prepared="$6" status="$7"
  local component action source target backup before source_state root privilege _reason
  IFS='|' read -r component action source target backup before source_state root privilege _reason <<< "$record"
  if (( status != 0 && prepared ));then
    if apply_undo_one "$action" "$target" "$backup" "$before" "$after" "$stage" "$root" "$privilege";then
      printf '%s|rolled-back|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' "$sequence" "$component" "$action" "$source" "$target" "$backup" "$before" "$after" "$stage" "$root" "$privilege" >> "$journal"
    else printf 'error: automatic restoration incomplete; retained %s and journal %s\n' "$stage" "$journal" >&2;exit "$status";fi
  fi
  if [[ -n "$stage" && -d "$stage" ]];then
    if apply_exists "$stage/new";then
      if [[ "$action" == mkdir ]];then apply_command "$privilege" rmdir "$stage/new";else apply_command "$privilege" rm -f "$stage/new";fi
    fi
    apply_command "$privilege" rmdir "$stage" || true
  fi
  exit "$status"
}

apply_set_cleanup() {
  local cleanup_command
  # Quote immutable arguments now: Bash discards dynamic/local scope before EXIT.
  printf -v cleanup_command '%q ' apply_transaction_cleanup "$@"
  # Arguments are deliberately captured now; only the exit status is deferred.
  # shellcheck disable=SC2064
  trap "${cleanup_command} \"\$?\"" EXIT
}

# A transaction stages the new object, journals intent, preserves the original,
# then publishes. EXIT handles command failures/signals before returning.
apply_transaction() (
  set -e
  # Subshell-scoped assignments survive until EXIT; function-local variables do not.
  record="$1" journal="$2" sequence="$3"
  stage='' after=''
  IFS='|' read -r component action source target backup before source_state root privilege _reason <<< "$record"
  apply_parent_safe "$root" "$target"
  [[ "$(apply_state "$target")" == "$before" ]] || { printf 'error: target changed since planning: %s\n' "$target" >&2;exit 1; }
  if [[ -n "$source" ]];then [[ "$(apply_state "$source")" == "$source_state" ]] || { printf 'error: source changed since planning: %s\n' "$source" >&2;exit 1; };fi
  stage="$(apply_command "$privilege" mktemp -d "$(dirname -- "$target")/.dotfiles-apply.XXXXXX")"
  apply_set_cleanup "$record" "$journal" "$sequence" "$stage" "" 0
  if [[ "$privilege" == sudo ]];then apply_command "$privilege" chmod 0711 "$stage";fi
  apply_stage "$action" "$source" "$stage/new" "$privilege"
  if [[ "$privilege" == sudo && "$action" == copy ]];then
    # Generated content is user-owned; system files must retain their original owner.
    if [[ -e "$target" ]];then
      if [[ "$(uname -s)" == Darwin ]];then owner="$(stat -f '%u:%g' "$target")";else owner="$(stat -c '%u:%g' "$target")";fi
    else owner=0:0;fi
    apply_command "$privilege" chown "$owner" "$stage/new"
  fi
  after="$(apply_state "$stage/new")"
  printf '%s|prepared|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' "$sequence" "$component" "$action" "$source" "$target" "$backup" "$before" "$after" "$stage" "$root" "$privilege" >> "$journal"
  apply_set_cleanup "$record" "$journal" "$sequence" "$stage" "$after" 1
  apply_parent_safe "$root" "$target"
  [[ "$(apply_state "$target")" == "$before" ]] || { printf 'error: target changed before backup\n' >&2;exit 1; }
  if [[ "$before" != absent ]];then
    [[ -n "$backup" ]] || { printf 'error: missing backup destination\n' >&2;exit 1; }
    apply_exists "$backup" && { printf 'error: backup path already exists\n' >&2;exit 1; }
    mkdir -p "$(dirname -- "$backup")"
    apply_command "$privilege" mv "$target" "$stage/old"
    apply_command "$privilege" mv "$stage/old" "$backup"
  fi
  apply_parent_safe "$root" "$target"
  apply_publish "$stage/new" "$target" "$privilege"
  printf '%s|applied|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' "$sequence" "$component" "$action" "$source" "$target" "$backup" "$before" "$after" "$stage" "$root" "$privilege" >> "$journal"
)
