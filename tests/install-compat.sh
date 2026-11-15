#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
source "$repo_root/lib/install-items.sh"
test_tmp="$(mktemp -d)";trap 'rm -rf "$test_tmp"' EXIT
mkdir "$test_tmp/items" "$test_tmp/bin"
cat > "$test_tmp/items/tool.conf" <<CONF
[linux.apt]
order=1
method=apt
packages=tool
source_kind=default
scope=desktop
check=$test_tmp/bin/legacy-tool
CONF
cat > "$test_tmp/bin/legacy-tool" <<'COMMAND'
#!/bin/sh
[ "$1" = --version ] || exit 33
exit 0
COMMAND
chmod +x "$test_tmp/bin/legacy-tool"
plan="$(install_items_plan "$test_tmp/items" linux.apt 0 0 1 'linux.apt|0|||')"
[[ "$(install_field "$plan" action)" == skip ]]
[[ "$(install_field "$plan" probe_command)" == "$test_tmp/bin/legacy-tool" ]]
[[ "$(install_field "$plan" environments)" == native ]]
[[ "$(install_field "$plan" methods)" == apt && "$(install_field "$plan" preferred_method)" == apt ]]
[[ " ${install_field_names:?} " != *' scope '* && " ${install_field_names:?} " != *' check '* ]]
# The legacy declaration normalizes to exactly the same environment gate.
wsl="$(install_items_plan "$test_tmp/items" linux.apt 0 1 1 'linux.apt|0|||')"
[[ "$(install_field "$wsl" reason)" == environment-not-selected:wsl ]]
rm "$test_tmp/bin/legacy-tool"
[[ "$(install_field "$(install_items_plan "$test_tmp/items" linux.apt 0 0 1 'linux.apt|0|||')" action)" == install ]]
printf 'Legacy declarations normalize once and retain command/environment behavior.\n'
