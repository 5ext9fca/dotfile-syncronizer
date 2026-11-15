#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
# shellcheck source=../lib/apply-items.sh
source "$repo_root/lib/apply-items.sh"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
count=0
while IFS=$'\t' read -r name platform outcome;do
  [[ "$name" != \#* && -n "$name" ]] || continue
  if apply_read_items "$repo_root/tests/fixtures/apply/$name" "$platform" > "$scratch/actual" 2> "$scratch/error";then
    [[ "$outcome" == ok ]] || { printf 'FAIL accepted %s\n' "$name" >&2;exit 1; }
    sed '/^$/d' "$scratch/actual" > "$scratch/nonempty"
    diff -u "$repo_root/tests/fixtures/apply/$name/expected.txt" "$scratch/nonempty"
  else [[ "$outcome" == error && ! -s "$scratch/actual" ]];fi
  count=$((count+1))
done < "$repo_root/tests/fixtures/apply/cases.tsv"
printf 'Apply schema tests passed (%s shared cases).\n' "$count"
