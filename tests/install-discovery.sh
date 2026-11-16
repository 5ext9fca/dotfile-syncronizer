#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
source "$repo_root/lib/install-items.sh"
test_tmp="$(mktemp -d)";trap 'rm -rf "$test_tmp"' EXIT
context="macos|0|$test_tmp/bin/brew|$test_tmp|"
fixtures="$repo_root/tests/fixtures/install/discovery"
# Discovery must not invoke application/version or package inventory probes.
mkdir "$test_tmp/bin"
export DOTFILES_TEST_NATIVE_CALLS="$test_tmp/dispatched" DOTFILES_TEST_NATIVE_EXIT=0
cat > "$test_tmp/bin/brew" <<'BREW'
#!/usr/bin/env bash
printf '%s %s\n' "$0" "$*" >> "$DOTFILES_TEST_NATIVE_CALLS"
[[ "$1" == install ]] || exit 99
exit "$DOTFILES_TEST_NATIVE_EXIT"
BREW
chmod +x "$test_tmp/bin/brew"
plan="$(install_items_plan "$fixtures" macos 0 0 1 "$context")"
[[ "$(install_field "$plan" method)" == brew && "$(install_field "$plan" action)" == install ]]
# A non-executable file satisfies file discovery; a directory at that path does not.
mkdir -p "$test_tmp/bin/tool"
[[ -z "$(install_discover "$plan" "$context")" ]]
rmdir "$test_tmp/bin/tool"
printf 'not an executable\n' > "$test_tmp/bin/tool"
[[ "$(install_discover "$plan" "$context")" == discovered:brew ]]
fresh="$(install_resume_record "$plan" "$context")"
[[ "$(install_field "$fresh" action)" == skip ]]
rm "$test_tmp/bin/tool"
# All paths belonging to one method are required. An alternate method can satisfy discovery.
mkdir "$test_tmp/Manual Tool.app"
[[ -z "$(install_discover "$plan" "$context")" ]]
touch "$test_tmp/Manual Tool.app/tool"
[[ "$(install_discover "$plan" "$context")" == discovered:manual ]]
fresh="$(install_items_plan "$fixtures" macos 0 0 1 "$context")"
[[ "$(install_field "$fresh" action)" == skip && "$(install_field "$fresh" state)" == discovered:manual ]]
# Offline plans never inspect; removed files invalidate both ordinary and resume decisions.
[[ "$(install_field "$(install_items_plan "$fixtures" macos 0 0 0 "$context")" action)" == install ]]
rm "$test_tmp/Manual Tool.app/tool"
[[ "$(install_field "$(install_resume_record "$fresh" "$context")" action)" == install ]]
# A broken symlink is absent; a symlink to a regular file is present.
ln -s "$test_tmp/missing" "$test_tmp/bin/tool"
[[ -z "$(install_discover "$plan" "$context")" ]]
touch "$test_tmp/missing"
[[ "$(install_discover "$plan" "$context")" == discovered:brew ]]
# Presence does not change which recipe is dispatched when no method is present.
rm "$test_tmp/bin/tool" "$test_tmp/missing"
# Called by the imported preferred-method dispatcher.
# shellcheck disable=SC2329
[[ ! -e "$test_tmp/dispatched" ]]
install_items_execute "$plan" "$context" > "$test_tmp/output"
[[ "$(cat "$test_tmp/dispatched")" == "$test_tmp/bin/brew install tool" ]]
# A failed preferred recipe is not retried through an alternate installer.
: > "$test_tmp/dispatched"
# Called by the imported preferred-method dispatcher.
# shellcheck disable=SC2329
export DOTFILES_TEST_NATIVE_EXIT=23
set +e
install_items_execute "$plan" "$context" > "$test_tmp/failed"
code=$?
set -e
[[ "$code" == 23 && "$(cat "$test_tmp/dispatched")" == "$test_tmp/bin/brew install tool" ]]
# Linux declarations use the same discovery engine, with literal rooted paths.
mkdir "$test_tmp/linux-items"
sed "s@home:@root:${test_tmp#/}/@g; s@root:usr/bin/tool@root:${test_tmp#/}/usr/bin/tool@g" "$repo_root/tests/fixtures/install/discovery-linux/tool.conf" > "$test_tmp/linux-items/tool.conf"
linux_plan="$(install_items_plan "$test_tmp/linux-items" linux.apt 0 0 1 'linux.apt|0|||')"
[[ "$(install_field "$linux_plan" method)" == cargo && "$(install_field "$linux_plan" action)" == install ]]
mkdir -p "$test_tmp/usr/bin"
touch "$test_tmp/usr/bin/tool"
[[ "$(install_discover "$linux_plan" 'linux.apt|0|||')" == discovered:apt ]]
# Serialized discovery data survives contract publication/reading.
[[ "$(contract_read install-plan "$(contract_write install-plan "$plan")")" == "$plan" ]]
printf 'Application discovery, preferred recipes, file types and current-state rechecks passed.\n'
# Inaccessible parents are discovery errors, never absence.
mkdir "$test_tmp/denied"
touch "$test_tmp/denied/tool"
chmod 000 "$test_tmp/denied"
set +e
install_discovery_match_path file root "${test_tmp#/}/denied/tool" "$context" > "$test_tmp/denied-result" 2>/dev/null
code=$?
set -e
chmod 700 "$test_tmp/denied"
[[ "$code" == 2 && ! -s "$test_tmp/denied-result" ]]
