#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
# shellcheck source=../lib/apply-items.sh
source "$repo_root/lib/apply-items.sh"
work="$(mktemp -d)";work="$(cd -- "$work" && pwd -P)"
trap 'rm -rf "$work"' EXIT
count=0
while IFS=$'\t' read -r name initial unix_action _windows_action unix_backup _windows_backup guard;do
  [[ "$name" != \#* ]] || continue
  case_root="$work/$name space";mkdir -p "$case_root/repo" "$case_root/items" "$case_root/config"
  cp "$repo_root/tests/fixtures/apply-operations/tool.conf" "$case_root/items/"
  source_file="$case_root/repo/source.conf";target="$case_root/config/target.conf";session="$case_root/session"
  printf 'new\n' > "$source_file"
  case "$initial" in
    absent) ;;
    old) printf 'original\n' > "$target" ;;
    same) cp "$source_file" "$target" ;;
    linked) ln "$source_file" "$target" ;;
    directory) mkdir "$target";printf 'original\n' > "$target/nested" ;;
  esac
  before="$(apply_state "$target")"
  plan="$(apply_make_plan "$case_root/repo" "$case_root/items" "$case_root/config" "$session" '')"
  operation="$(printf '%s\n' "$plan" | awk -F '|' -v target="$target" '$4==target {print $2 "|" ($5!="" ? 1 : 0)}')"
  [[ "$operation" == "$unix_action|$unix_backup" ]] || { printf 'Wrong plan: %s %s\n' "$name" "$operation" >&2;exit 1; }
  apply_execute_plan "$plan" "$session" 0 > "$work/log"
  [[ "$source_file" -ef "$target" ]] || { printf 'Not linked: %s\n' "$name" >&2;exit 1; }
  repeated="$(apply_make_plan "$case_root/repo" "$case_root/items" "$case_root/config" "$case_root/repeated" '')"
  [[ "$repeated" != *'|hardlink|'* ]] || { printf 'Not idempotent: %s\n' "$name" >&2;exit 1; }
  if [[ "$guard" == 1 ]];then
    rm "$target";printf 'user change\n' > "$target"
    if apply_restore "$session/journal.tsv" 0 > "$work/log" 2>&1;then printf 'Overwrote user change\n' >&2;exit 1;fi
    [[ "$(cat "$target")" == 'user change' ]]
  else
    apply_restore "$session/journal.tsv" 0 > "$work/log"
    [[ "$(apply_state "$target")" == "$before" ]] || { printf 'Wrong restored state: %s\n' "$name" >&2;exit 1; }
  fi
  count=$((count+1))
done < "$repo_root/tests/fixtures/apply-operations/cases.tsv"
printf 'Apply filesystem contracts passed (%s shared cases).\n' "$count"
