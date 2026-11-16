#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
# shellcheck source=../lib/workflow.sh
source "$repo_root/lib/workflow.sh"
plan="$(install_items_plan "$repo_root/tests/fixtures/install/dependencies" linux.apt 1 0 0)"
text="$(install_explain_plan "$plan" linux.apt leaf)"
[[ "$text" == *'selected-by=dependency'* && "$text" == *'depends-on:'* && "$text" == *'method=apt'* ]]
plan="$(install_items_plan "$repo_root/software/items" linux.apt 1 1 0)"
text="$(install_explain_plan "$plan" linux.apt all "$repo_root/software/items")"
[[ "$text" == *'provided-by-host:windows-docker-desktop'* && "$text" == *'msvc: excluded (platform-not-configured)'* && "$text" == *'Source: pypi-index (mirror)'* ]]
plan="$(install_items_plan "$repo_root/software/items" linux.apt 0 0 0)"
text="$(install_explain_plan "$plan" linux.apt)"
[[ "$text" == *'Source: pypi-index (config); url=https://pypi.org/simple'* && "$text" == *'Installation-only edges (omitted on skip unless independently selected):'* ]]
text="$(apply_explain_plan $'fish|hardlink|/source|/target|/backup|old|new|/|none|replace|1\nfish|skip|/source2|/target2||||/|none|unchanged|1')"
[[ "$text" == *'hardlink /target (replace)'* && "$text" == *'Existing target backup: /backup'* && "$text" == *'skip /target2 (unchanged)'* ]]
# Default offline CLI remains a machine-readable envelope.
contract_read install-plan "$(bash "$repo_root/install/plan.sh" --platform windows)" >/dev/null
printf 'Plan selection, sources, environment exclusions and configuration effect tests passed.\n'
