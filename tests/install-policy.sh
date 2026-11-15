#!/usr/bin/env bash
# Mock command execution is invoked through the imported install adapter.
# shellcheck disable=SC2317
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
# shellcheck source=../lib/install-items.sh
source "$repo_root/lib/install-items.sh"
while IFS=$'\t' read -r name expected;do
  if actual="$(install_execution_policy apt probe "$repo_root/tests/fixtures/install-policy/$name.tsv" 2>/dev/null)";then
    [[ "$expected" == valid ]]
    if [[ "$name" == override ]];then [[ "$actual" == '8|0' ]];else [[ "$actual" == '30|0' ]];fi
  else [[ "$expected" == invalid ]];fi
done < "$repo_root/tests/fixtures/install-policy/cases.tsv"
[[ "$(install_execution_policy msvc modify)" == '0|0,3010' ]]
[[ "$(install_execution_policy winget install)" == '0|0' ]]
# The sourced implementation is used before the deliberate override below.
# shellcheck disable=SC2218
[[ "$(install_execution_policy homebrew download)" == '120|0' ]]
# Verify the adapter uses method, timeout and accepted status from its policy.
install_execution_policy() { [[ "$1" == apt && "$2" == install ]];printf '60|0,23\n'; }
command_run() { [[ "$1" == mutation && "$2" == 0 && "$3" == 60 && "$6" == example ]];return 23; }
install_run 'linux.apt|0||||apt' example
printf 'Installation execution policy validation and adapter tests passed.\n'
