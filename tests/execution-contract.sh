#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
# shellcheck source=../lib/workflow.sh
source "$repo_root/lib/workflow.sh"
while IFS=$'\t' read -r code dry status reason;do
  [[ "$code" != \#* ]] || continue
  [[ "$(execution_result "$code" "$dry")" == "$status|$reason" ]]
done < "$repo_root/tests/fixtures/execution/outcomes.tsv"
while IFS=$'\t' read -r state action reason;do
  [[ "$state" != \#* ]] || continue
  [[ "$state" != '<empty>' ]] || state=''
  if [[ "$action" == invalid ]];then
    if install_probe_result "$state" >/dev/null 2>&1;then exit 1;fi
  else [[ "$(install_probe_result "$state")" == "$action|$reason" ]];fi
done < "$repo_root/tests/fixtures/execution/probes.tsv"
work="$(mktemp -d)";trap 'rm -rf "$work"' EXIT
context="$(install_context_make linux.apt 1 brew /usr/local 1)"
install_run "$context" missing-contract-command > "$work/dry"
grep -q 'DRY RUN:' "$work/dry"
set +e
install_run "$(install_context_make linux.apt 0 brew /usr/local "$work")" missing-contract-command 2> "$work/missing"
code=$?
set -e
[[ "$code" == 127 ]]
# Interrupted child status persists and prevents downstream mutation.
cat > "$work/session.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
source "$1/lib/workflow.sh"
workflow_preflight() { :; }
workflow_confirm() { :; }
context="$2/context";mkdir "$context"
workflow_context_set "$context" session_path "$2/session"
workflow_context_set "$context" results_path "$2/result.tsv"
workflow_context_set "$context" platform linux.apt
workflow_context_set "$context" china_mirrors 0
workflow_context_set "$context" profile_name test
workflow_context_set "$context" session_id test
workflow_context_set "$context" dry_run 0
workflow_context_set "$context" plan_only 0
printf 'packages|1|requested|none|packages\nconfiguration|1|requested|none|configuration\n' > "$context/stages.plan"
# The report is the third handler argument.
workflow_execute_stage() {
  grep -q '|packages|running|' "$(dirname "$3")/events.tsv"
  return 130
}
workflow_run "$context"
SCRIPT
set +e
"$BASH" "$work/session.sh" "$repo_root" "$work" > "$work/log" 2>&1
code=$?
set -e
[[ "$code" == 130 ]]
expected_fields="$(awk -F '\t' '!/^#/ {print $1}' "$repo_root/workflow/schema/report-fields.tsv" | paste -sd '|' -)"
[[ "$(head -n 1 "$work/result.tsv")" == "$expected_fields" ]]
grep -q '|packages|interrupted|130|' "$work/result.tsv"
grep -q '|configuration|blocked|' "$work/result.tsv"
awk -F '|' 'NR>1 && ($11!=1 || $13!="packages") {exit 1}' "$work/result.tsv"
"$BASH" "$repo_root/workflow/status.sh" "$work/session" > "$work/status"
grep -q -- '--resume ' "$work/status"
rm "$work/session/request.tsv"
"$BASH" "$repo_root/workflow/status.sh" "$work/session" > "$work/legacy-status"
grep -q -- '--from-stage packages' "$work/legacy-status"
printf 'Execution outcomes, probes, dry-run and interrupted-session contracts passed.\n'
