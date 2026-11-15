# shellcheck shell=bash
apply_journal_active() {
  [[ "$(head -n 1 "$1")" == '# dotfiles-apply-journal-v1' ]] || { printf 'error: unsupported recovery journal\n' >&2;return 1; }
  awk -F '|' '
    /^#/ {next}
    NF!=12 || $1 !~ /^[0-9]+$/ || $2 !~ /^(prepared|applied|rolled-back|restored)$/ {bad=1;next}
    {rows[$1]=$0;states[$1]=$2}
    END {if(bad) exit 1;for(id in rows) if(states[id]=="prepared" || states[id]=="applied") print rows[id]}
  ' "$1" | LC_ALL=C sort -t '|' -k1,1nr
}

apply_restore_validate() {
  local records="$1" session="$2" sequence state component action source target backup before after stage root privilege current expected entries entry allowed record_target record_stage path
  while IFS='|' read -r sequence state component action source target backup before after stage root privilege;do
    [[ -n "$sequence" ]] || continue
    case "$action" in mkdir|copy|hardlink) ;; *) printf 'error: invalid journal action\n' >&2;return 1 ;; esac
    [[ "$privilege" == none || "$privilege" == sudo ]] || return 1
    [[ "$stage" == "$(dirname -- "$target")/.dotfiles-apply."* ]] || { printf 'error: invalid staging path\n' >&2;return 1; }
    [[ -z "$backup" || "$backup" == "$session/files/"* ]] || { printf 'error: backup outside journal session\n' >&2;return 1; }
    for path in "$target" "$stage" "$root" "$backup";do
      [[ -n "$path" ]] || continue
      apply_safe_path "$path" || return
      case "$path/" in */../*|*/./*) printf 'error: dot segment in recovery path\n' >&2;return 1 ;; esac
      [[ "$path" == /* ]] || return 1
    done
    if apply_exists "$stage" && [[ -L "$stage" || ! -d "$stage" ]];then printf 'error: staging directory was replaced\n' >&2;return 1;fi
    if [[ -n "$backup" ]] && apply_exists "$backup";then apply_parent_safe "$session" "$backup" || return;fi
    apply_parent_safe "$root" "$target" || return
    current="$(apply_state "$target")" || return
    if [[ "$state" == prepared && "$current" == "$before" ]];then :
    elif [[ "$action" == mkdir && -d "$target" && ! -L "$target" && "$(apply_stat "$target")" == "${after%:d:*}" ]];then
      entries="$(apply_list "$target")" || return
      while IFS= read -r entry;do
        [[ -n "$entry" ]] || continue
        allowed=0
        while IFS='|' read -r _ _ _ _ _ record_target _ _ _ record_stage _ _;do
          if [[ "$entry" == "$record_target" || "$entry" == "$record_stage" || "$entry" == "$record_stage/"* ]];then allowed=1;break;fi
        done <<< "$records"
        (( allowed )) || { printf 'error: directory has untracked content: %s\n' "$entry" >&2;return 1; }
      done <<< "$entries"
    elif [[ "$current" != "$after" && ! ( "$state" == prepared && "$current" == absent ) ]];then
      printf 'error: refusing to restore modified target: %s\n' "$target" >&2;return 1
    fi
    if [[ "$before" != absent && "$current" != "$before" ]];then
      expected="$(apply_state_content "$before")"
      if [[ -n "$backup" ]] && apply_exists "$backup" && [[ "$(apply_content "$backup")" == "$expected" ]];then :
      elif apply_exists "$stage/old" && [[ "$(apply_content "$stage/old")" == "$expected" ]];then :
      else printf 'error: backup is missing or changed: %s\n' "$backup" >&2;return 1;fi
    fi
    if apply_exists "$stage/new" && [[ "$(apply_state "$stage/new")" != "$after" ]];then printf 'error: staging content changed: %s\n' "$stage/new" >&2;return 1;fi
  done <<< "$records"
}

apply_restore_unlocked() {
  local journal="$1" dry="$2" records session sequence state component action source target backup before after stage root privilege
  [[ -f "$journal" && ! -L "$journal" ]] || { printf 'error: journal must be a regular file\n' >&2;return 1; }
  session="$(cd -- "$(dirname -- "$journal")" && pwd -P)" || return
  records="$(apply_journal_active "$journal")" || { printf 'error: corrupt recovery journal\n' >&2;return 1; }
  apply_restore_validate "$records" "$session" || return
  while IFS='|' read -r sequence state component action source target backup before after stage root privilege;do
    [[ -n "$sequence" ]] || continue
    if [[ "$dry" == 1 ]];then printf 'DRY RUN: restore %q from %q\n' "$target" "$backup";continue;fi
    apply_undo_one "$action" "$target" "$backup" "$before" "$after" "$stage" "$root" "$privilege" || return
    if [[ -d "$stage" && ! -L "$stage" ]];then
      if apply_exists "$stage/new";then
        if [[ "$action" == mkdir ]];then apply_command "$privilege" rmdir "$stage/new" || return
        else apply_command "$privilege" rm -f "$stage/new" || return;fi
      fi
      apply_command "$privilege" rmdir "$stage" || return
    fi
    printf '%s|restored|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' "$sequence" "$component" "$action" "$source" "$target" "$backup" "$before" "$after" "$stage" "$root" "$privilege" >> "$journal"
    printf '%s: restored\n' "$target"
  done <<< "$records"
}
