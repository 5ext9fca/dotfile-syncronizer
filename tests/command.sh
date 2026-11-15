#!/usr/bin/env bash
# Shell snippets and metacharacters are intentionally literal arguments.
# shellcheck disable=SC2016
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
# shellcheck source=../lib/command.sh
source "$repo_root/lib/command.sh"
work="$(mktemp -d)";trap 'rm -rf "$work"' EXIT
mkdir "$work/capture"
command_run mutation 1 0 '' -- touch "$work/mutated" > "$work/dry"
[[ ! -e "$work/mutated" ]]
command_run probe 0 3 "$work/capture" -- bash -c 'printf "%s\n" "$@";printf warning >&2' _ 'a b' '$(touch forbidden)' ''
[[ "$(cat "$work/capture/stdout")" == $'a b\n$(touch forbidden)' ]]
[[ "$(cat "$work/capture/stderr")" == warning ]]
contract_read command-result "$(cat "$work/capture/command.result")" | grep -q '^probe|success|0|'
set +e
command_run mutation 0 0 "$work/capture" -- bash -c 'exit 23'
code=$?
set -e
[[ "$code" == 23 ]]
# A timeout must terminate a descendant that ignores TERM before returning.
set +e
command_run probe 0 1 "$work/capture" -- bash -c 'bash -c '\''trap "" TERM; sleep 4; touch "$1"'\'' _ "$1" & wait' _ "$work/leaked"
code=$?
set -e
[[ "$code" == 124 ]]
contract_read command-result "$(cat "$work/capture/command.result")" | grep -q '^probe|timed-out|124|'
mkdir "$work/cancel"
command_run mutation 0 0 "$work/cancel" -- bash -c 'printf "%s" "$PPID" > "$1"; trap "" TERM; sleep 4; touch "$2"' _ "$work/ready" "$work/leaked-term" &
runner=$!
for ((attempt=0; attempt<200; attempt++));do
  [[ ! -s "$work/ready" ]] || break
  sleep 0.01
done
[[ -s "$work/ready" ]]
controller="$(cat "$work/ready")"
kill -TERM "$controller"
set +e
wait "$runner"
code=$?
set -e
[[ "$code" == 143 ]]
contract_read command-result "$(cat "$work/cancel/command.result")" | grep -q '^mutation|interrupted|143|'
sleep 4
[[ ! -e "$work/leaked" && ! -e "$work/leaked-term" ]]
[[ "$(command_capture 3 printf '%s' 'literal value')" == 'literal value' ]]
printf 'Command arguments, capture, dry-run, exit codes, timeout and cancellation cleanup passed.\n'
