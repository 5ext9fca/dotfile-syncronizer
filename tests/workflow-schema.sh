#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
# shellcheck source=../lib/workflow-profile.sh
source "$repo_root/lib/workflow-profile.sh"
# shellcheck source=../lib/workflow-stages.sh
source "$repo_root/lib/workflow-stages.sh"
fixtures="$repo_root/tests/fixtures/workflow"
test_tmp="$(mktemp -d)"
trap 'rm -rf "$test_tmp"' EXIT
count=0
while IFS=$'\t' read -r name expected; do
  if workflow_read_profile "$fixtures/$name.conf" > "$test_tmp/actual" 2> "$test_tmp/error"; then
    [[ "$expected" == valid ]] || { printf 'Unexpected valid profile: %s\n' "$name" >&2; exit 1; }
    diff -u "$fixtures/expected.txt" "$test_tmp/actual"
  else
    [[ "$expected" == invalid && ! -s "$test_tmp/actual" ]] || { printf 'Unexpected invalid/partial profile: %s\n' "$name" >&2; exit 1; }
  fi
  count=$((count+1))
done < "$fixtures/cases.tsv"
printf 'Workflow schema tests passed (%s shared fixtures).\n' "$count"

count=0
while IFS=$'\t' read -r name platform profile only from mirrors registry expected; do
  [[ "$only" != - ]] || only=''
  [[ "$from" != - ]] || from=''
  if [[ "$registry" == - ]];then registry="$repo_root/workflow/schema/stages.tsv";else registry="$fixtures/stages/$registry";fi
  profile="$(workflow_read_profile "$fixtures/stages/$profile.conf")"
  if workflow_stage_plan "$platform" "$profile" "$only" "$from" "$mirrors" "$registry" > "$test_tmp/actual" 2> "$test_tmp/error";then
    [[ "$expected" == valid ]] || { printf 'Accepted invalid stage case: %s\n' "$name" >&2;exit 1; }
    diff -u "$fixtures/stages/$name.expected" "$test_tmp/actual"
  else
    [[ "$expected" == invalid && ! -s "$test_tmp/actual" ]] || { printf 'Invalid/partial stage case: %s\n' "$name" >&2;exit 1; }
  fi
  count=$((count+1))
done < "$fixtures/stages/cases.tsv"
printf 'Workflow stage tests passed (%s shared fixtures).\n' "$count"
