#!/usr/bin/env bash
set -euo pipefail
# Test overrides are dispatched indirectly by the command worker.
# shellcheck disable=SC2317,SC2329
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
# shellcheck source=../lib/install-items.sh
source "$repo_root/lib/install-items.sh"
test_tmp="$(mktemp -d)"
trap 'rm -rf "$test_tmp"' EXIT
export HOME="$test_tmp/home" XDG_CONFIG_HOME="$test_tmp/config"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$test_tmp/bin"
# No network and no real font install. Failure cases must publish no fonts.
curl() {
  [[ "${font_fail:-}" != download ]] || return 22
  local output
  while (( $# ));do if [[ "$1" == -o ]];then output="$2";break;fi;shift;done
  printf 'font-data' > "$output"
}
fc-scan() {
  [[ "${font_fail:-}" != parse ]] || return 1
  [[ "${font_fail:-}" != wrong ]] || { printf 'Wrong Family';return; }
  printf 'Sample Sans'
}
fc-cache() { printf 'refresh\n' >> "$test_tmp/cache"; }
for font_fail in download parse wrong;do
  if install_font_download_files sample https://example.invalid 'One.otf Two.otf' 'Sample Sans';then exit 1;fi
  [[ ! -e "$HOME/.local/share/fonts/sample" ]]
done
font_fail=''
install_font_download_files sample https://example.invalid 'One.otf Two.otf' 'Sample Sans'
[[ -f "$HOME/.local/share/fonts/sample/Two.otf" && -s "$test_tmp/cache" ]]
if install_font_download_files sample https://example.invalid '../bad.otf' 'Sample Sans';then exit 1;fi
# Presence requires every declared file; native-only items are excluded on WSL.
raw="$(install_items_plan "$repo_root/tests/fixtures/install/font-download" linux.apt 0 0 0)"
record="$(printf '%s\n' "$raw" | awk -F '|' '$1=="sample"')"
for file in $(install_field "$record" font_files);do touch "$HOME/.local/share/fonts/sample/$file";done
context="$(install_context_make linux.apt 0 '' '' "$test_tmp/backups")"
observed="$(install_evaluate_record "$record" "$context" normal)"
[[ "$(install_field "$observed" action)" == skip ]]
rm "$HOME/.local/share/fonts/sample/Bold.ttf"
observed="$(install_evaluate_record "$record" "$context" normal)"
[[ "$(install_field "$observed" action)" == install ]]
plan="$(install_items_plan "$repo_root/tests/fixtures/install/font-download" linux.apt 0 1 0)"
[[ "$(install_field "$plan" reason)" == environment-not-selected:wsl ]]
touch "$HOME/.local/share/fonts/JetBrainsMonoNerdFont-Regular.ttf"
raw="$(install_items_plan "$repo_root/install/items" linux.dnf 0 0 0)"
record="$(printf '%s\n' "$raw" | awk -F '|' '$1=="jetbrains-mono"')"
observed="$(install_evaluate_record "$record" "$(install_context_make linux.dnf 0 '' '' "$test_tmp/backups")" normal)"
[[ "$(install_field "$observed" detected_method)" == manual ]]
# The family comes from the record and works for arbitrary item IDs.
plan="$(install_items_plan "$repo_root/tests/fixtures/install/font-download" linux.apt 0 0 0)"
install_run() { shift; printf '<%s>' "$@"; }
output="$(install_font_download "$plan" "$context")"
[[ "$output" == *'<Sample Sans>'* ]]
# Defaults contain Noto and never download PingFang, on every native branch.
for platform in linux.apt linux.dnf linux.pacman;do
  plan="$(install_items_plan "$repo_root/install/items" "$platform" 0 0 0)"
  [[ "$plan" == *'noto-cjk|'* && "$plan" != *'pingfang-sc|'* ]]
done
printf 'Declarative font download and default selection tests passed.\n'
