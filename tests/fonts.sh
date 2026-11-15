#!/usr/bin/env bash
set -euo pipefail
# Test overrides are dispatched indirectly by the command worker.
# shellcheck disable=SC2317,SC2329
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
# shellcheck source=../lib/install-items.sh
source "$repo_root/lib/install-items.sh"
# shellcheck source=../lib/apply-items.sh
source "$repo_root/lib/apply-items.sh"
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
  printf 'PingFang SC'
}
fc-cache() { printf 'refresh\n' >> "$test_tmp/cache"; }
for font_fail in download parse wrong;do
  if install_font_download_files pingfang-sc https://example.invalid 'One.otf Two.otf';then exit 1;fi
  [[ ! -e "$HOME/.local/share/fonts/pingfang-sc" ]]
done
font_fail=''
install_font_download_files pingfang-sc https://example.invalid 'One.otf Two.otf'
[[ -f "$HOME/.local/share/fonts/pingfang-sc/Two.otf" && -s "$test_tmp/cache" ]]
if install_font_download_files pingfang-sc https://example.invalid '../bad.otf';then exit 1;fi
# Presence requires every declared file; native-only items are excluded on WSL.
raw="$(install_items_read "$repo_root/install/items" linux.dnf)"
record="$(printf '%s\n' "$raw" | awk -F '|' '$1=="pingfang-sc"')"
for file in $(install_field "$record" font_files);do touch "$HOME/.local/share/fonts/pingfang-sc/$file";done
context="$(install_context_make linux.dnf 0 '' '' "$test_tmp/backups")"
observed="$(install_evaluate_record "$record" "$context" normal)"
[[ "$(install_field "$observed" action)" == skip ]]
rm "$HOME/.local/share/fonts/pingfang-sc/PingFangSC-Thin.otf"
observed="$(install_evaluate_record "$record" "$context" normal)"
[[ "$(install_field "$observed" action)" == install ]]
mkdir -p "$HOME/.local/share/fonts"
touch "$HOME/.local/share/fonts/JetBrainsMonoNerdFont-Regular.ttf"
record="$(printf '%s\n' "$raw" | awk -F '|' '$1=="jetbrains-mono"')"
observed="$(install_evaluate_record "$record" "$context" normal)"
[[ "$(install_field "$observed" detected_method)" == manual ]]
for platform in linux.apt linux.dnf linux.pacman;do
  plan="$(install_items_plan "$repo_root/install/items" "$platform" 0 1 0)"
  record="$(printf '%s\n' "$plan" | awk -F '|' '$1=="pingfang-sc"')"
  [[ "$(install_field "$record" reason)" == environment-not-selected:wsl ]]
done
# Exercise the real candidate planner + existing transactional file operations.
# kreadconfig supplies inherited values; no GTK/display query is needed here.
cat > "$test_tmp/bin/kreadconfig6" <<'MOCK'
#!/usr/bin/env bash
printf 'Inherited,10,-1,5,50,0,0,0,0,0\n'
MOCK
chmod +x "$test_tmp/bin/kreadconfig6"
export PATH="$test_tmp/bin:$PATH"
fc-list() { printf 'PingFang SC\nJetBrainsMono Nerd Font\nNoto Sans CJK SC\n'; }
mkdir -p "$XDG_CONFIG_HOME/gtk-3.0" "$XDG_CONFIG_HOME/gtk-4.0" "$test_tmp/candidates"
printf '# preserve\n[General]\nfont=Old,12,-1,5,50,0,0,0,0,0\nother=untouched\n' > "$XDG_CONFIG_HOME/kdeglobals"
for version in 3 4;do printf '[Settings]\ngtk-font-name=Old Sans 11\nother=untouched\n' > "$XDG_CONFIG_HOME/gtk-$version.0/settings.ini";done
chmod 640 "$XDG_CONFIG_HOME/kdeglobals"
cp "$XDG_CONFIG_HOME/kdeglobals" "$test_tmp/original"
: > "$test_tmp/plan";: > "$test_tmp/directories"
desktop_fonts_plan desktop-fonts "$XDG_CONFIG_HOME" "$test_tmp/session" "$test_tmp/candidates" "$test_tmp/plan" "$test_tmp/directories"
apply_execute_plan "$(cat "$test_tmp/plan")" "$test_tmp/session" 0 > "$test_tmp/result"
grep -q '^font=PingFang SC,12,' "$XDG_CONFIG_HOME/kdeglobals"
[[ "$(stat -c '%a' "$XDG_CONFIG_HOME/kdeglobals")" == 640 ]]
: > "$test_tmp/plan";: > "$test_tmp/directories"
desktop_fonts_plan desktop-fonts "$XDG_CONFIG_HOME" "$test_tmp/session2" "$test_tmp/candidates" "$test_tmp/plan" "$test_tmp/directories"
[[ "$(awk -F '|' '$2=="skip" {n++} END {print n}' "$test_tmp/plan")" == 3 ]]
cp "$XDG_CONFIG_HOME/kdeglobals" "$test_tmp/deployed"
printf '# user edit\n' >> "$XDG_CONFIG_HOME/kdeglobals"
if apply_restore "$test_tmp/session/journal.tsv" 0 > "$test_tmp/restore" 2>&1;then exit 1;fi
cat "$test_tmp/deployed" > "$XDG_CONFIG_HOME/kdeglobals"
apply_restore "$test_tmp/session/journal.tsv" 0 > "$test_tmp/restore"
cmp "$test_tmp/original" "$XDG_CONFIG_HOME/kdeglobals"
# A failed publication restores the original desktop file and records rollback.
: > "$test_tmp/plan";: > "$test_tmp/directories"
desktop_fonts_plan desktop-fonts "$XDG_CONFIG_HOME" "$test_tmp/failed-session" "$test_tmp/candidates" "$test_tmp/plan" "$test_tmp/directories"
apply_publish() {
  [[ "$1" != */new ]] || return 23
  apply_exists "$2" && return 1
  apply_command "$3" mv -n "$1" "$2"
}
set +e
apply_execute_plan "$(cat "$test_tmp/plan")" "$test_tmp/failed-session" 0 > "$test_tmp/failure" 2>&1
status=$?
set -e
[[ "$status" == 23 ]]
cmp "$test_tmp/original" "$XDG_CONFIG_HOME/kdeglobals"
grep -q '|rolled-back|' "$test_tmp/failed-session/journal.tsv"
# shellcheck source=../apply/handlers/files.sh
source "$repo_root/apply/handlers/files.sh"
fc-list() { printf 'Unrelated Font\n'; }
if desktop_fonts_plan desktop-fonts "$XDG_CONFIG_HOME" "$test_tmp/session3" "$test_tmp/candidates" "$test_tmp/plan" "$test_tmp/directories";then exit 1;fi
# Selecting the component outside native KDE produces an explicit skip.
export XDG_CURRENT_DESKTOP=GNOME
plan="$(apply_make_plan "$repo_root" "$repo_root/apply/items" "$XDG_CONFIG_HOME" "$test_tmp/skipped" desktop-fonts "$test_tmp/candidates")"
[[ "$plan" == *'|requires-native-linux-kde|1' ]]
export XDG_CURRENT_DESKTOP=KDE WSL_DISTRO_NAME=Test
plan="$(apply_make_plan "$repo_root" "$repo_root/apply/items" "$XDG_CONFIG_HOME" "$test_tmp/skipped" desktop-fonts "$test_tmp/candidates")"
[[ "$plan" == *'|requires-native-linux-kde|1' ]]
printf 'Font download, discovery, candidate deployment and recovery tests passed.\n'
