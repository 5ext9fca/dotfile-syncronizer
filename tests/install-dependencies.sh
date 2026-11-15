#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
source "$repo_root/lib/workflow.sh"
test_tmp="$(mktemp -d)";trap 'rm -rf "$test_tmp"' EXIT
fixture="$repo_root/tests/fixtures/install/method-dependencies"
cp "$fixture/"*.conf "$test_tmp/"
base="$(cat "$fixture/tool.conf")"
while IFS='|' read -r name search replacement outcome dependencies closure failure_hint;do
  [[ "$name" != \#* ]] || continue
  [[ "$base" == *"$search"* ]]
  replacement="${replacement//\\n/$'\n'}"
  printf '%s\n' "$base" | DOTFILES_FIXTURE_SEARCH="$search" DOTFILES_FIXTURE_REPLACEMENT="$replacement" awk '
    BEGIN {search=ENVIRON["DOTFILES_FIXTURE_SEARCH"];replacement=ENVIRON["DOTFILES_FIXTURE_REPLACEMENT"]}
    {pos=index($0,search);if(pos) {count++;print substr($0,1,pos-1) replacement substr($0,pos+length(search))} else print}
    END {if(count!=1) exit 1}
  ' > "$test_tmp/tool.conf"
  if plan="$(install_items_plan "$test_tmp" macos 0 0 0 2> "$test_tmp/error")";then
    [[ "$outcome" == ok ]] || { printf 'Accepted invalid dependency case: %s\n' "$name" >&2;exit 1; }
    tool="$(printf '%s\n' "$plan" | awk -F '|' '$1=="tool"')"
    [[ "$(install_field "$tool" depends_on)" == "$dependencies" ]]
    selected="$(workflow_profile_install_plan 'install=tool' "$plan")"
    [[ "$(printf '%s\n' "$selected" | cut -d '|' -f1 | paste -sd ' ' -)" == "$closure" ]]
  else
    [[ "$outcome" == error ]] || { cat "$test_tmp/error" >&2;exit 1; }
    grep -qiF "$failure_hint" "$test_tmp/error"
  fi
done < "$fixture/cases.tsv"
printf 'Method dependency merging, selected graphs and profile closures passed.\n'
# Dynamic closure: shared dependencies survive a skip; recipe-only tools do not.
cp "$fixture/tool.conf" "$test_tmp/tool.conf"
plan="$(install_items_plan "$test_tmp" macos 0 0 0)"
tool="$(printf '%s\n' "$plan" | awk -F '|' '$1=="tool"')"
[[ "$(install_field "$tool" install_depends_on)" == build-brew ]]
skipped="$(install_record_update "$tool" action skip reason discovered-installation)"
plan="$(printf '%s\n' "$plan" | awk -F '|' '$1!="tool"')"$'\n'"$skipped"
selected="$(workflow_profile_install_plan 'install=tool' "$plan")"
[[ "$(printf '%s\n' "$selected" | cut -d '|' -f1 | paste -sd ' ' -)" == 'shared tool' ]]
selected="$(workflow_profile_install_plan 'install=tool build-brew' "$plan")"
[[ "$(printf '%s\n' "$selected" | cut -d '|' -f1 | paste -sd ' ' -)" == 'shared build-brew tool' ]]
[[ "$(workflow_profile_install_plan 'install=all' "$plan" | wc -l | tr -d ' ')" == 4 ]]
# Real discovery happens before expanding dependencies, so an unused failing
# probe cannot prevent an externally installed target from being selected.
mkdir "$test_tmp/lazy" "$test_tmp/home"
export HOME="$test_tmp/home"
touch "$HOME/tool" "$HOME/runtime"
cat > "$test_tmp/probe" <<'PROBE'
#!/bin/bash
exit 42
PROBE
chmod +x "$test_tmp/probe"
for id in tool runtime builder;do
  detection="detect_files=home:$id"
  [[ "$id" != builder ]] || detection="check=$test_tmp/probe"
  printf '[linux.apt]\norder=10\nmethod=script\nsource_kind=download\nsource_url=https://example.test/install\nshell=sh\n%s\n' "$detection" > "$test_tmp/lazy/$id.conf"
done
printf 'depends_on=runtime\ninstall_depends_on=builder\n' >> "$test_tmp/lazy/tool.conf"
plan="$(install_items_plan "$test_tmp/lazy" linux.apt 0 0 0)"
selected="$(workflow_profile_install_plan 'install=tool' "$plan" 'linux.apt|0|||' normal)"
[[ "$(printf '%s\n' "$selected" | cut -d '|' -f1 | paste -sd ' ' -)" == 'runtime tool' ]]
if workflow_profile_install_plan 'install=tool builder' "$plan" 'linux.apt|0|||' normal > "$test_tmp/failed-plan";then exit 1;else [[ "$?" == 42 ]];fi
[[ ! -s "$test_tmp/failed-plan" ]]
rm "$HOME/tool"
if workflow_profile_install_plan 'install=tool' "$plan" 'linux.apt|0|||' normal > "$test_tmp/failed-plan";then exit 1;else [[ "$?" == 42 ]];fi
[[ ! -s "$test_tmp/failed-plan" ]]
printf 'State-aware dependencies preserve shared/explicit roots and avoid unused probes.\n'
