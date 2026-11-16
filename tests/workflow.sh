#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
# shellcheck source=../lib/install-items.sh
source "$repo_root/lib/install-items.sh"
# shellcheck source=../lib/workflow.sh
source "$repo_root/lib/workflow.sh"
test_tmp="$(mktemp -d)"
trap 'rm -rf "$test_tmp"' EXIT
for profile_name in linux wsl macos windows; do
  profile="$(workflow_read_profile "$repo_root/workflow/profiles/$profile_name.conf")"
  platform="$profile_name"; wsl=0
  case "$profile_name" in linux) platform=linux.apt ;; wsl) platform=linux.dnf;wsl=1 ;; esac
  plan="$(install_items_plan "$repo_root/software/items" "$platform" 1 "$wsl" 0)"
  components="$(workflow_profile_components "$profile" "$plan")"
  [[ -z "$components" ]]
done
# Item selection includes dependencies and rejects misspelled references.
profile=$'install=leaf\ncomponents=leaf:leaf\nshell=none\nmirrors=none\nwsl=none'
prototype="$(install_items_plan "$repo_root/tests/fixtures/install/dependencies" linux.apt 0 0 0 | head -n 1)"
base="$(install_record_update "$prototype" id base depends_on '' install_depends_on '')"
leaf="$(install_record_update "$prototype" id leaf depends_on base install_depends_on '')"
other="$(install_record_update "$prototype" id other depends_on '' install_depends_on '')"
plan="$base"$'\n'"$leaf"$'\n'"$other"
[[ "$(workflow_profile_install_plan "$profile" "$plan")" == "$base"$'\n'"$leaf" ]]
if workflow_profile_install_plan 'install=missing' "$plan" >/dev/null 2>&1; then exit 1; fi
# Reject values as data rather than executing or silently ignoring them.
# shellcheck disable=SC2016
for invalid in 'unknown=value' 'shell=bash' 'mirrors=apply' 'components=fish:fish  git:git' 'wsl=$(touch bad)' 'install='; do
  printf 'schema_version=2\ninstall=all\ncomponents=fish:fish\nshell=fish\nmirrors=initialize\nwsl=none\nwsl_profile=none\n%s\n' "$invalid" > "$test_tmp/invalid.conf"
  if workflow_read_profile "$test_tmp/invalid.conf" >/dev/null 2>&1; then printf 'Accepted invalid profile: %s\n' "$invalid" >&2; exit 1; fi
done
profile="$(workflow_read_profile "$repo_root/workflow/profiles/macos.conf")"
workflow_stage_plan unix "$profile" packages '' 0 > "$test_tmp/stages"
[[ "$(cat "$test_tmp/stages")" == 'packages|1||packages|packages' ]]
if workflow_stage_plan unix "$profile" configuration '' 0 >/dev/null 2>&1;then exit 1;fi
printf 'Unified profiles, dependency selection and installation-only stages passed.\n'
