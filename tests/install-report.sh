#!/usr/bin/env bash
# The fake handler/probe exercise publication, never actual installation.
# shellcheck disable=SC2317,SC2329
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
source "$repo_root/lib/workflow.sh"
test_tmp="$(mktemp -d)";trap 'rm -rf "$test_tmp"' EXIT
while IFS='|' read -r name expected;do
  [[ "$name" != \#* ]] || continue
  if install_result_read "$(cat "$repo_root/tests/fixtures/install-reports/$name.txt")" > "$test_tmp/actual" 2> "$test_tmp/error";then
    [[ "$expected" != error && "$(cat "$test_tmp/actual")" == "$expected" ]]
  else [[ "$expected" == error && ! -s "$test_tmp/actual" ]];fi
done < "$repo_root/tests/fixtures/install-reports/cases.tsv"
root="$test_tmp/space;中文"
mkdir -p "$root/Manual Tool.app"
touch "$root/Manual Tool.app/tool"
context="macos|0|$test_tmp/brew|$root|"
offline="$(install_items_plan "$repo_root/tests/fixtures/install/discovery" macos 0 0 0 "$context")"
[[ -z "$(install_field "$offline" detected_paths)" && -z "$(install_field "$offline" detected_method)" ]]
[[ "$(install_field "$offline" decision_reason)" == offline-preferred-method ]]
plan="$(install_items_plan "$repo_root/tests/fixtures/install/discovery" macos 0 0 1 "$context")"
paths='["'"$root"'/Manual Tool.app/tool","'"$root"'/Manual Tool.app"]'
[[ "$(install_field "$plan" detected_paths)" == "$paths" ]]
[[ "$(install_field "$plan" detected_method)" == manual ]]
install_items_execute "$plan" "$context" "$test_tmp/report" > "$test_tmp/output"
rows="$(install_result_read "$(cat "$test_tmp/report")")"
[[ "$rows" == "tool|skipped|0|discovered-installation|brew|manual|$paths|discovered-installation" ]]
# The status command consumes the structured report, not the console log.
mkdir "$test_tmp/session"
printf '%s\n' "$(contract_fields workflow-summary)" "test|macos|packages|success|0|0||$test_tmp/report|||1||" > "$test_tmp/session/workflow.tsv"
bash "$repo_root/workflow/status.sh" "$test_tmp/session" > "$test_tmp/status"
grep -Fq 'Item tool: skipped' "$test_tmp/status"
grep -Fq 'Preferred method: brew' "$test_tmp/status"
grep -Fq 'Matched method: manual' "$test_tmp/status"
grep -Fq "$paths" "$test_tmp/status"
cp "$repo_root/tests/fixtures/install-reports/legacy.txt" "$test_tmp/report"
bash "$repo_root/workflow/status.sh" "$test_tmp/session" > "$test_tmp/status"
grep -Fq 'Item tool: skipped (already-installed)' "$test_tmp/status"
if grep -q 'Matched method' "$test_tmp/status";then exit 1;fi
# When multiple methods match, record only the first matching method and its paths.
mkdir -p "$root/bin";touch "$root/bin/tool"
tie="$(install_items_plan "$repo_root/tests/fixtures/install/discovery" macos 0 0 1 "$context")"
[[ "$(install_field "$tie" detected_method)" == brew ]]
[[ "$(install_field "$tie" detected_paths)" == '["'"$root"'/bin/tool"]' ]]
rm "$root/bin/tool"
# PATH evidence records the actual first match and ignores empty PATH entries.
mkdir "$test_tmp/first" "$test_tmp/second";touch "$test_tmp/first/evidence-tool" "$test_tmp/second/evidence-tool"
path_record="$(install_record_update "$plan" discovery brew:file:path:evidence-tool)"
path_observation="$(PATH=":$test_tmp/first:$test_tmp/second:$PATH" install_discovery_observation "$path_record" "$context")"
[[ "$path_observation" == 'brew|["'"$test_tmp"'/first/evidence-tool"]' ]]
# Rechecking after removal clears old observations; partial matches never leak.
rm "$root/Manual Tool.app/tool"
fresh="$(install_resume_record "$plan" "$context")"
[[ -z "$(install_field "$fresh" detected_method)" && -z "$(install_field "$fresh" detected_paths)" ]]
[[ "$(install_field "$fresh" decision_reason)" == no-discovery-match ]]
# Running and failed reports retain the decision; blocked items carry no stale evidence.
export DOTFILES_TEST_NATIVE_REPORT="$test_tmp/report" DOTFILES_TEST_NATIVE_SNAPSHOT="$test_tmp/running" DOTFILES_TEST_NATIVE_EXIT=23
cat > "$test_tmp/brew" <<'BREW'
#!/usr/bin/env bash
set -euo pipefail
cat "$DOTFILES_TEST_NATIVE_REPORT" > "$DOTFILES_TEST_NATIVE_SNAPSHOT"
exit "$DOTFILES_TEST_NATIVE_EXIT"
BREW
chmod +x "$test_tmp/brew"
set +e
install_items_execute "$fresh"$'\n'"$(install_record_update "$plan" id later)" "$context" "$test_tmp/report" > "$test_tmp/output"
code=$?
set -e
[[ "$code" == 23 ]]
grep -Fq 'tool|running|0|resume-recheck-required|brew|||no-discovery-match' "$test_tmp/running"
grep -Eq '^tool\|failed\|[0-9]+\|exit-23\|brew\|\|\|no-discovery-match$' "$test_tmp/report"
grep -Eq '^later\|blocked\|[0-9]+\|previous-failure\|brew\|\|\|$' "$test_tmp/report"
# A failed resume probe retains identity but discards the previous plan evidence.
export DOTFILES_TEST_NATIVE_SNAPSHOT="$test_tmp/checking" DOTFILES_TEST_NATIVE_EXIT=42
# Keep stale evidence in the input while forcing a native inventory probe.
probe_plan="$(install_record_update "$plan" discovery '')"
set +e
install_items_execute "$probe_plan" "$context" "$test_tmp/report" 1 > "$test_tmp/output"
code=$?
set -e
[[ "$code" == 42 ]]
grep -Fq 'tool|running|0|checking-current-state|brew|||' "$test_tmp/checking"
grep -Eq '^tool\|failed\|[0-9]+\|exit-42\|brew\|\|\|$' "$test_tmp/report"
# JSON string escaping is independent of the outer record separators.
[[ "$(install_discovery_path_json $'/a|b"c\\d\te\nf')" == '"/a\u007cb\"c\\d\u0009e\u000af"' ]]
printf 'Installation evidence, atomic report snapshots, historical readers and status explanation passed.\n'
