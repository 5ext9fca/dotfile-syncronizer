#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
# shellcheck source=../lib/install-items.sh
source "$repo_root/lib/install-items.sh"
while IFS='|' read -r state mode check legacy action reason result_state;do
  [[ "$state" != \#* ]] || continue
  [[ "$(install_decide "$state" "$mode" "$check" "$legacy")" == "$action|$reason|$result_state|$reason" ]]
done < "$repo_root/tests/fixtures/install/decisions.tsv"
if install_decide unknown normal '' 0 >/dev/null 2>&1;then exit 1;fi
if install_decide '' invalid '' 0 >/dev/null 2>&1;then exit 1;fi
printf 'Pure installation decision policy passed.\n'
