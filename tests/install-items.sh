#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
# shellcheck source=../lib/install-items.sh
source "$repo_root/lib/install-items.sh"
fixture_root="$repo_root/tests/fixtures/install"
test_tmp="$(mktemp -d)"
trap 'rm -rf "$test_tmp"' EXIT
# shellcheck source=fixtures/install/materialize.sh
source "$fixture_root/materialize.sh"
count=0
while IFS=$'\t' read -r name platform mirrors wsl outcome; do
  [[ "$name" == \#* || -z "$name" ]] && continue
  fixture_directory="$(materialize_install_fixture "$fixture_root" "$name" "$test_tmp/fixtures")"
  if install_items_plan "$fixture_directory" "$platform" "$mirrors" "$wsl" 0 > "$test_tmp/actual" 2> "$test_tmp/error"; then
    [[ "$outcome" == ok ]] || { printf 'FAIL accepted %s\n' "$name" >&2; exit 1; }
    diff -u "$fixture_root/$name/expected.plan" "$test_tmp/actual"
  else
    [[ "$outcome" == error && ! -s "$test_tmp/actual" ]] || { cat "$test_tmp/error" >&2; printf 'FAIL rejected %s\n' "$name" >&2; exit 1; }
  fi
  count=$((count+1))
done < "$fixture_root/cases.tsv"
for platform in linux.apt linux.dnf linux.pacman macos windows; do
  install_items_plan "$repo_root/install/items" "$platform" 1 0 0 > "$test_tmp/$platform.plan"
  [[ -s "$test_tmp/$platform.plan" ]]
done
# Plan/execution use the same resolved URL; execution does not inspect again.
plan="$(install_items_plan "$fixture_root/mirror" linux.apt 1 0 0)"
install_run() { shift; printf 'COMMAND';printf ' <%s>' "$@";printf '\n'; }
output="$(install_items_execute "$plan" 'linux.apt|1|||' "$test_tmp/results")"
[[ "$output" == *'<PIP_INDEX_URL=https://mirror.example/simple>'* ]]
grep -q '^sample|planned|' "$test_tmp/results"
# A failed handler must stop immediately, record failure and block subsequent work.
plan="$(install_items_plan "$fixture_root/dependencies" linux.apt 0 0 0)"
# shellcheck disable=SC2317,SC2329
install_dispatch() { false; printf 'ERROR: continued after failure\n' > "$test_tmp/leaked"; }
set +e
install_items_execute "$plan" 'linux.apt|0|||' "$test_tmp/failure" > "$test_tmp/output"
status=$?
set -e
[[ "$status" == 1 && ! -e "$test_tmp/leaked" ]]
grep -q '^first|failed|' "$test_tmp/failure"
grep -q '^middle|blocked|' "$test_tmp/failure"
grep -q '^last|blocked|' "$test_tmp/failure"
# A GUI bootstrap may defer installation without deploying later items.
install_dispatch() { return 75; }
set +e
install_items_execute "$plan" 'macos|0|||' "$test_tmp/deferred" > "$test_tmp/output"
status=$?
set -e
[[ "$status" == 75 ]]
grep -q '^first|deferred|' "$test_tmp/deferred"
grep -q '^middle|blocked|' "$test_tmp/deferred"
printf 'Install item tests passed (%s shared cases plus execution checks).\n' "$count"
