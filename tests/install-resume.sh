#!/usr/bin/env bash
# Mock functions are called by the imported executor.
# shellcheck disable=SC2317
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
# shellcheck source=../lib/install-items.sh
source "$repo_root/lib/install-items.sh"
test_tmp="$(mktemp -d)";trap 'rm -rf "$test_tmp"' EXIT
mkdir "$test_tmp/items"
source "$repo_root/tests/fixtures/install/commands/setup.sh"
setup_fake_package_commands "$test_tmp/commands" "$repo_root"
state="$DOTFILES_TEST_PACKAGE_STATE"
for id in first second third;do
  dependency='';order=30
  case "$id" in second) dependency=first;order=1 ;; third) dependency=second;order=2 ;; esac
  printf '[linux.apt]\norder=%s\nmethod=apt\npackages=%s\nsource_kind=default\ndepends_on=%s\n' "$order" "$id" "$dependency" > "$test_tmp/items/$id.conf"
done
plan="$(install_items_plan "$test_tmp/items" linux.apt 0 0 0)"
touch "$state/fail-second"
set +e
install_items_execute "$plan" 'linux.apt|0|||' "$state/results" > "$test_tmp/first.log"
code=$?
set -e
[[ "$code" == 23 ]]
[[ "$(cat "$state/installs")" == $'first\nsecond' ]]
grep -q '^third|blocked|' "$state/results"
rm "$state/fail-second";: > "$state/installs"
install_items_execute "$plan" 'linux.apt|0|||' "$state/results" 1 > "$test_tmp/resume.log"
[[ "$(cat "$state/installs")" == $'second\nthird' ]]
grep -q '^first|skipped|.*|resume-already-installed|' "$state/results"
# A previously successful package removed by the user must be reinstalled.
rm "$state/installed-first";: > "$state/installs"
install_items_execute "$plan" 'linux.apt|0|||' "$state/results" 1 > "$test_tmp/recheck.log"
[[ "$(cat "$state/installs")" == first ]]
# A timeout must stop and block later items, never be interpreted as absence.
touch "$state/probe-delay"
: > "$state/installs"
set +e
install_items_execute "$plan" 'linux.apt|0|||' "$state/results" 1 > "$test_tmp/timeout.log"
code=$?
set -e
[[ "$code" == 124 && ! -s "$state/installs" ]]
grep -q '^second|blocked|' "$state/results"
rm "$state/probe-delay"
# An unexpected native error also fails closed, rather than requesting installation.
printf '42\n' > "$state/probe-exit"
set +e
install_items_execute "$plan" 'linux.apt|0|||' "$state/results" 1 > "$test_tmp/error.log"
code=$?
set -e
[[ "$code" == 42 && ! -s "$state/installs" ]]
rm "$state/probe-exit"
# Uninspectable mechanisms retain normal execution on every resume.
record="$(printf '%s\n' "$plan" | head -n 1)"
record="$(printf '%s\n' "$record" | awk -F '|' -v OFS='|' '{$3="script";print}')"
refreshed="$(install_resume_record "$record" 'linux.apt|0|||')"
[[ "$(install_field "$refreshed" action)" == install ]]
[[ "$(install_field "$refreshed" reason)" == resume-recheck-required ]]
# Mechanism-specific probes use the same real command boundary and fixture state.
touch "$state/installed-sample"
for method in docker-ce apt apt-repository dnf dnf-copr pacman brew cask cargo;do
  candidate="$(printf '%s\n' "$record" | awk -F '|' -v OFS='|' -v method="$method" '{$3=method;$4="sample";print}')"
  [[ "$(install_resume_package_state "$candidate" "linux.apt|0|$test_tmp/commands/bin/brew||")" == present ]]
done
candidate="$(printf '%s\n' "$record" | awk -F '|' -v OFS='|' '{$3="apt";$4="sample missing";print}')"
[[ -z "$(install_resume_package_state "$candidate" 'linux.apt|0|||')" ]]
candidate="$(printf '%s\n' "$record" | awk -F '|' -v OFS='|' '{$3="pipx";$4="sample";print}')"
[[ "$(install_field "$(install_resume_record "$candidate" 'linux.apt|0|||')" action)" == skip ]]
# Ordinary runs use the same current inventory and never infer presence from history.
: > "$state/installs"
normal="$(install_items_plan "$test_tmp/items" linux.apt 0 0 1 'linux.apt|0|||')"
install_items_execute "$normal" 'linux.apt|0|||' "$state/results" > "$test_tmp/normal.log"
[[ ! -s "$state/installs" ]]
grep -q '^first|skipped|.*|already-installed|' "$state/results"
rm "$state/installed-second"
normal="$(install_items_plan "$test_tmp/items" linux.apt 0 0 1 'linux.apt|0|||')"
install_items_execute "$normal" 'linux.apt|0|||' "$state/results" > "$test_tmp/removed.log"
[[ "$(cat "$state/installs")" == second ]]
printf '[linux.apt]\norder=40\nmethod=apt\npackages=fourth\nsource_kind=default\n' > "$test_tmp/items/fourth.conf"
: > "$state/installs"
normal="$(install_items_plan "$test_tmp/items" linux.apt 0 0 1 'linux.apt|0|||')"
install_items_execute "$normal" 'linux.apt|0|||' "$state/results" > "$test_tmp/added.log"
[[ "$(cat "$state/installs")" == fourth ]]
printf '42\n' > "$state/probe-exit"
if install_items_plan "$test_tmp/items" linux.apt 0 0 1 'linux.apt|0|||' > /dev/null;then exit 1;else [[ "$?" == 42 ]];fi
rm "$state/probe-exit"
# A successful command need not create discovery evidence; there is no post-check.
install_dispatch() { :; }
missing="$(install_record_update "$candidate" method apt packages absent action install reason requested)"
install_items_execute "$missing" 'linux.apt|0|||' "$state/results" > "$test_tmp/no-postcheck.log"
grep -q '^first|success|' "$state/results"
# Rust discovery requires the declared components, but never checks default/health.
cat > "$test_tmp/commands/bin/rustup" <<'RUSTUP'
#!/bin/bash
if [[ -f "$DOTFILES_TEST_PACKAGE_STATE/rust-error" ]];then exit 42;fi
case "$*" in
  'toolchain list') printf 'stable-test-host (default)\n' ;;
  'component list --installed --toolchain stable-test-host')
    printf 'rustfmt-test-host\n'
    [[ ! -f "$DOTFILES_TEST_PACKAGE_STATE/rust-missing" ]] || exit 0
    printf 'rust-analyzer-test-host\n' ;;
  *) exit 91 ;;
esac
RUSTUP
chmod +x "$test_tmp/commands/bin/rustup"
rust="$(install_record_update "$record" method rustup packages stable components rustfmt,rust-analyzer)"
[[ "$(install_probe_rustup "$rust" 'linux.pacman|0|||')" == present ]]
touch "$state/rust-missing"
[[ -z "$(install_probe_rustup "$rust" 'linux.pacman|0|||')" ]]
touch "$state/rust-error"
if install_probe_rustup "$rust" 'linux.pacman|0|||';then exit 1;else [[ "$?" == 42 ]];fi
# Missing commands cannot accidentally fall through to a host package manager.
rm "$test_tmp/commands/bin/dpkg-query"
if command -v dpkg-query >/dev/null 2>&1;then exit 1;fi
candidate="$(printf '%s\n' "$record" | awk -F '|' -v OFS='|' '{$3="apt";$4="sample";print}')"
[[ -z "$(install_resume_package_state "$candidate" 'linux.apt|0|||')" ]]
printf 'Installation resume, real fake-command boundaries, timeout/error gating and host isolation passed.\n'
