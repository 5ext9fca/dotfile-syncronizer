#!/usr/bin/env bash
# Overrides are invoked through the deployment lease wrapper.
# shellcheck disable=SC2317
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
# shellcheck source=../lib/apply-items.sh
source "$repo_root/lib/apply-items.sh"
work="$(mktemp -d)"
work="$(cd -- "$work" && pwd -P)"
other_fs=''
trap 'rm -rf "$work"; if [[ -n "$other_fs" ]];then rm -rf "$other_fs";fi' EXIT
fail() { printf 'FAIL: %s\n' "$1" >&2;exit 1; }
new_case() {
  case_root="$work/$1";mkdir -p "$case_root/repo/tool/nested" "$case_root/config" "$case_root/items"
  printf '[unix]\nsource=tool\ntarget_root=config_home\ntarget=tool\nmethod=hardlink\nexclude=runtime\n' > "$case_root/items/tool.conf"
  printf 'new\n' > "$case_root/repo/tool/nested/a file"
  printf 'state\n' > "$case_root/repo/tool/runtime"
  session="$case_root/backups/session"
}
build() { apply_make_plan "$case_root/repo" "$case_root/items" "$case_root/config" "$session" "${1:-}"; }
new_case dry
plan="$(build)"
apply_execute_plan "$plan" "$session" 1 > "$work/log"
[[ ! -e "$case_root/config/tool" && ! -e "$session" ]] || fail 'dry-run mutated the filesystem'
if build $'tool\nunknown' > "$work/invalid" 2> "$work/error";then fail 'accepted unknown component';fi
[[ ! -s "$work/invalid" ]] || fail 'leaked a partial plan'
new_case results-alias
plan="$(build)"
ln "$case_root/repo/tool/nested/a file" "$case_root/report"
if apply_execute_plan "$plan" "$session" 0 "$case_root/report" > "$work/log" 2> "$work/error";then fail 'report alias accepted';fi
[[ ! -e "$session" && "$(cat "$case_root/report")" == new ]] || fail 'report validation was too late'
new_case basic
plan="$(build)";apply_execute_plan "$plan" "$session" 0 > "$work/log"
[[ "$case_root/repo/tool/nested/a file" -ef "$case_root/config/tool/nested/a file" ]] || fail 'not hard-linked'
[[ ! -e "$case_root/config/tool/runtime" ]] || fail 'runtime state deployed'
plan="$(build)";[[ "$plan" != *'|hardlink|'* && "$plan" != *'|mkdir|'* ]] || fail 'not idempotent'
printf 'user data\n' > "$case_root/config/tool/new-user-file"
if apply_restore "$session/journal.tsv" 0 > "$work/log" 2> "$work/error";then fail 'restored over new application data';fi
[[ -f "$case_root/config/tool/nested/a file" ]] || fail 'partial restore before validation'
rm "$case_root/config/tool/new-user-file"
apply_restore "$session/journal.tsv" 1 > "$work/log"
[[ -f "$case_root/config/tool/nested/a file" ]] || fail 'restore dry-run mutated files'
apply_restore "$session/journal.tsv" 0 > "$work/log"
[[ ! -e "$case_root/config/tool" ]] || fail 'new directory not removed'
apply_restore "$session/journal.tsv" 0 > "$work/log"
new_case nested-symlink
mkdir -p "$case_root/config/tool" "$case_root/external"
printf 'external\n' > "$case_root/external/a file"
ln -s "$case_root/external" "$case_root/config/tool/nested"
plan="$(build)";apply_execute_plan "$plan" "$session" 0 > "$work/log"
[[ ! -L "$case_root/config/tool/nested" && "$(cat "$case_root/external/a file")" == external ]] || fail 'followed a destination symlink'
apply_restore "$session/journal.tsv" 0 > "$work/log"
[[ -L "$case_root/config/tool/nested" ]] || fail 'did not restore symlink'
new_case directory-conflict
mkdir -p "$case_root/config/tool/nested/a file"
printf 'old\n' > "$case_root/config/tool/nested/a file/old"
plan="$(build)";apply_execute_plan "$plan" "$session" 0 > "$work/log"
apply_restore "$session/journal.tsv" 0 > "$work/log"
[[ "$(cat "$case_root/config/tool/nested/a file/old")" == old ]] || fail 'directory backup lost'
new_case stale-source
mkdir -p "$case_root/config/tool/nested"
printf 'old\n' > "$case_root/config/tool/nested/a file"
plan="$(build)";printf 'changed\n' > "$case_root/repo/tool/nested/a file"
set +e
apply_execute_plan "$plan" "$session" 0 > "$work/log" 2> "$work/error"
status=$?
set -e
[[ "$status" != 0 && "$(cat "$case_root/config/tool/nested/a file")" == old ]] || fail 'stale source was used'
new_case "rollback's"
mkdir -p "$case_root/config/tool/nested"
printf 'old\n' > "$case_root/config/tool/nested/a file"
plan="$(build)"
apply_publish() {
  [[ "$1" != */new ]] || return 23
  apply_exists "$2" && return 1
  apply_command "$3" mv -n "$1" "$2"
}
set +e
apply_execute_plan "$plan" "$session" 0 "$work/results" > "$work/log" 2> "$work/error"
status=$?
set -e
[[ "$status" == 23 && "$(cat "$case_root/config/tool/nested/a file")" == old ]] || fail 'failed replacement was not rolled back'
grep -q '|rolled-back|' "$session/journal.tsv" || fail 'missing rollback journal'
# shellcheck source=../apply/handlers/files.sh
source "$repo_root/apply/handlers/files.sh"
new_case changed-after-apply
plan="$(build)";apply_execute_plan "$plan" "$session" 0 > "$work/log"
printf 'user edit\n' > "$case_root/config/tool/nested/a file"
if apply_restore "$session/journal.tsv" 0 > "$work/log" 2> "$work/error";then fail 'overwrote user edit';fi
[[ "$(cat "$case_root/config/tool/nested/a file")" == 'user edit' ]] || fail 'user edit lost'
new_case interrupted
mkdir -p "$case_root/config/tool/nested"
printf 'old\n' > "$case_root/config/tool/nested/a file"
plan="$(build)"
record="$(printf '%s\n' "$plan" | awk -F '|' '$2=="hardlink" {print;exit}')"
IFS='|' read -r component action source target backup before _source_state root privilege _reason <<< "$record"
stage="$(mktemp -d "$(dirname -- "$target")/.dotfiles-apply.XXXXXX")"
ln "$source" "$stage/new";after="$(apply_state "$stage/new")"
mkdir -p "$(dirname -- "$backup")"
mv "$target" "$backup"
printf '# dotfiles-apply-journal-v1\n1|prepared|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' "$component" "$action" "$source" "$target" "$backup" "$before" "$after" "$stage" "$root" "$privilege" > "$session/journal.tsv"
apply_restore "$session/journal.tsv" 0 > "$work/log"
[[ "$(cat "$target")" == old && ! -d "$stage" ]] || fail 'interrupted transaction not recovered'
new_case modified-backup
mkdir -p "$case_root/config/tool/nested"
printf 'old\n' > "$case_root/config/tool/nested/a file"
plan="$(build)";apply_execute_plan "$plan" "$session" 0 > "$work/log"
backup="$(awk -F '|' '$2=="applied" && $4=="hardlink" {print $7;exit}' "$session/journal.tsv")"
printf 'modified backup\n' > "$backup"
if apply_restore "$session/journal.tsv" 0 > "$work/log" 2> "$work/error";then fail 'modified backup accepted';fi
[[ "$(cat "$case_root/config/tool/nested/a file")" == new ]] || fail 'modified-backup preflight changed target'
new_case source-symlink
ln -s "$case_root/repo/tool/nested/a file" "$case_root/repo/tool/link"
if build > "$work/invalid" 2> "$work/error";then fail 'source symlink accepted';fi
[[ ! -s "$work/invalid" ]] || fail 'partial source validation'
new_case overlap
cp "$case_root/items/tool.conf" "$case_root/items/other.conf"
if build > "$work/invalid" 2> "$work/error";then fail 'overlapping destinations accepted';fi
new_case cross-device
if [[ -d /dev/shm && -w /dev/shm ]];then
  other_fs="$(mktemp -d /dev/shm/dotfiles-apply.XXXXXX)"
  source_device="$(apply_stat "$case_root/repo/tool/nested/a file")";target_device="$(apply_stat "$other_fs")"
  if [[ "${source_device%%:*}" != "${target_device%%:*}" ]];then
    if apply_make_plan "$case_root/repo" "$case_root/items" "$other_fs" "$session" '' > "$work/invalid" 2> "$work/error";then fail 'cross-filesystem hardlink accepted';fi
    [[ ! -e "$other_fs/tool" && ! -s "$work/invalid" ]] || fail 'cross-filesystem validation mutated target'
  fi
fi
new_case privileged-copy
mkdir -p "$case_root/config/tool/nested"
printf 'old\n' > "$case_root/config/tool/nested/a file"
plan="$(build)"
record="$(printf '%s\n' "$plan" | awk -F '|' -v OFS='|' '$2=="hardlink" {$2="copy";$9="sudo";print;exit}')"
if [[ "$(uname -s)" == Darwin ]];then expected_owner="$(stat -f '%u:%g' "$case_root/config/tool/nested/a file")"
else expected_owner="$(stat -c '%u:%g' "$case_root/config/tool/nested/a file")";fi
apply_command() {
  local privilege="$1"
  shift
  if [[ "$privilege" == sudo && "$1" == chown ]];then printf '%s\n' "$2" > "$work/chown-owner";return 0;fi
  "$@"
}
apply_execute_plan "$record" "$session" 0 > "$work/log"
[[ "$(cat "$work/chown-owner")" == "$expected_owner" ]] || fail 'system replacement ownership was not preserved'
printf 'Unix apply planning, transaction and recovery tests passed.\n'
