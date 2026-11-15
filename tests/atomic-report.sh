#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
# shellcheck source=../lib/atomic-report.sh
source "$repo_root/lib/atomic-report.sh"
work="$(mktemp -d)";trap 'rm -rf "$work"' EXIT
printf 'old\n' | atomic_report_write "$work/report" create
# A reader holding the old inode continues to see the complete old snapshot.
exec 8< "$work/report"
printf 'new\n' | atomic_report_write "$work/report"
[[ "$(cat <&8)" == old && "$(cat "$work/report")" == new ]]
exec 8<&-
if printf 'overwrite' | atomic_report_write "$work/report" create 2>/dev/null;then exit 1;fi
# This reads with the external cat before installing the fault-injection function.
# shellcheck disable=SC2218
[[ "$(cat "$work/report")" == new ]]
# Simulate a producer failing after a partial write, before publication.
# The imported writer calls this producer override.
# shellcheck disable=SC2317,SC2329
cat() { printf 'partial';return 42; }
if atomic_report_write "$work/report" </dev/null;then exit 1;fi
unset -f cat
[[ "$(cat "$work/report")" == new ]]
[[ -z "$(find "$work" -name '*.tmp.*' -print)" ]]
ln -s "$work/report" "$work/link"
if printf 'bad' | atomic_report_write "$work/link";then exit 1;fi
[[ "$(cat "$work/report")" == new ]]
printf 'Atomic report replacement, failed write and exclusive publication passed.\n'
