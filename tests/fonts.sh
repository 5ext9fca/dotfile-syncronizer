#!/usr/bin/env bash
# Test overrides are dispatched indirectly by the command worker.
# shellcheck disable=SC2317,SC2329
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
# shellcheck source=../lib/install-items.sh
source "$repo_root/lib/install-items.sh"
# shellcheck source=../lib/apply-items.sh
source "$repo_root/lib/apply-items.sh"
test_tmp="$(mktemp -d)"
trap 'rm -rf "$test_tmp"' EXIT
export HOME="$test_tmp/home" XDG_CONFIG_HOME="$test_tmp/config"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$test_tmp/bin"
# Exercise the production component planner and native transactions.
export XDG_CURRENT_DESKTOP=KDE
unset WSL_INTEROP WSL_DISTRO_NAME
fixture_repo="$test_tmp/repo"
mkdir -p "$fixture_repo/configs/fontconfig"
cp "$repo_root/configs/fontconfig/60-dotfiles-fonts.conf" "$fixture_repo/configs/fontconfig/60-dotfiles-fonts.conf"
# kreadconfig supplies inherited values; no GTK/display query is needed here.
cat > "$test_tmp/bin/kreadconfig6" <<'MOCK'
#!/usr/bin/env bash
printf 'Inherited,10,-1,5,50,0,0,0,0,0\n'
MOCK
chmod +x "$test_tmp/bin/kreadconfig6"
export PATH="$test_tmp/bin:$PATH"
export DOTFILES_TEST_FONT_LIST="$test_tmp/font-list"
printf 'JetBrainsMono Nerd Font\nNoto Sans CJK SC\n' > "$DOTFILES_TEST_FONT_LIST"
cat > "$test_tmp/bin/fc-list" <<'FONT_LIST'
#!/usr/bin/env bash
cat "$DOTFILES_TEST_FONT_LIST"
FONT_LIST
chmod +x "$test_tmp/bin/fc-list"
mkdir -p "$XDG_CONFIG_HOME/gtk-3.0" "$XDG_CONFIG_HOME/gtk-4.0" "$test_tmp/candidates"
printf '# preserve\n[General]\nfont=Old,12,-1,5,50,0,0,0,0,0\nother=untouched\n' > "$XDG_CONFIG_HOME/kdeglobals"
for version in 3 4;do printf '[Settings]\ngtk-font-name=Old Sans 11\nother=untouched\n' > "$XDG_CONFIG_HOME/gtk-$version.0/settings.ini";done
chmod 640 "$XDG_CONFIG_HOME/kdeglobals"
cp "$XDG_CONFIG_HOME/kdeglobals" "$test_tmp/original"
apply_make_plan "$fixture_repo" "$repo_root/apply/items" "$XDG_CONFIG_HOME" "$test_tmp/session" desktop-fonts "$test_tmp/candidates" > "$test_tmp/plan"
apply_execute_plan "$(cat "$test_tmp/plan")" "$test_tmp/session" 0 > "$test_tmp/result"
grep -q '^font=Noto Sans CJK SC,12,' "$XDG_CONFIG_HOME/kdeglobals"
[[ "$(stat -c '%a' "$XDG_CONFIG_HOME/kdeglobals")" == 640 ]]
apply_make_plan "$fixture_repo" "$repo_root/apply/items" "$XDG_CONFIG_HOME" "$test_tmp/session2" desktop-fonts "$test_tmp/candidates" > "$test_tmp/plan"
[[ "$(awk -F '|' '$2=="skip" && ($4 ~ /kdeglobals$/ || $4 ~ /settings.ini$/) {n++} END {print n}' "$test_tmp/plan")" == 3 ]]
cp "$XDG_CONFIG_HOME/kdeglobals" "$test_tmp/deployed"
printf '# user edit\n' >> "$XDG_CONFIG_HOME/kdeglobals"
if apply_restore "$test_tmp/session/journal.tsv" 0 > "$test_tmp/restore" 2>&1;then exit 1;fi
cat "$test_tmp/deployed" > "$XDG_CONFIG_HOME/kdeglobals"
apply_restore "$test_tmp/session/journal.tsv" 0 > "$test_tmp/restore"
cmp "$test_tmp/original" "$XDG_CONFIG_HOME/kdeglobals"
# A failed publication restores the original desktop file and records rollback.
apply_make_plan "$fixture_repo" "$repo_root/apply/items" "$XDG_CONFIG_HOME" "$test_tmp/failed-session" desktop-fonts "$test_tmp/candidates" > "$test_tmp/plan"
apply_publish() {
  [[ "$1" != */new ]] || return 23
  apply_exists "$2" && return 1
  apply_command "$3" mv -n "$1" "$2"
}
record="$(awk -F '|' '$2=="copy" && $4 ~ /kdeglobals$/ {print;exit}' "$test_tmp/plan")"
mkdir -p "$test_tmp/failed-session"
printf '# dotfiles-apply-journal-v1\n' > "$test_tmp/failed-session/journal.tsv"
set +e
apply_transaction "$record" "$test_tmp/failed-session/journal.tsv" 1 > "$test_tmp/failure" 2>&1
status=$?
set -e
[[ "$status" == 23 ]]
cmp "$test_tmp/original" "$XDG_CONFIG_HOME/kdeglobals"
grep -q '|rolled-back|' "$test_tmp/failed-session/journal.tsv"
# shellcheck source=../apply/handlers/files.sh
source "$repo_root/apply/handlers/files.sh"
printf 'Unrelated Font\n' > "$DOTFILES_TEST_FONT_LIST"
if apply_make_plan "$fixture_repo" "$repo_root/apply/items" "$XDG_CONFIG_HOME" "$test_tmp/session3" desktop-fonts "$test_tmp/candidates" > "$test_tmp/plan";then exit 1;fi
# Both the availability gate and rendered families follow an alternate source.
sed -e 's/Noto Sans CJK SC/Custom UI/g' -e 's/JetBrainsMono Nerd Font/Custom Mono/g' \
  "$repo_root/configs/fontconfig/60-dotfiles-fonts.conf" > "$fixture_repo/configs/fontconfig/60-dotfiles-fonts.conf"
printf 'JetBrainsMono Nerd Font\nNoto Sans CJK SC\n' > "$DOTFILES_TEST_FONT_LIST"
if apply_make_plan "$fixture_repo" "$repo_root/apply/items" "$XDG_CONFIG_HOME" "$test_tmp/custom-session" desktop-fonts "$test_tmp/candidates" > "$test_tmp/plan";then exit 1;fi
printf 'Custom UI\nCustom Mono\n' > "$DOTFILES_TEST_FONT_LIST"
: > "$test_tmp/plan";: > "$test_tmp/directories"
apply_make_plan "$fixture_repo" "$repo_root/apply/items" "$XDG_CONFIG_HOME" "$test_tmp/custom-session" desktop-fonts "$test_tmp/candidates" > "$test_tmp/plan"
grep -q '^font=Custom UI,12,' "$test_tmp/candidates/desktop-kdeglobals"
grep -q '^fixed=Custom Mono,' "$test_tmp/candidates/desktop-kdeglobals"
grep -q '^gtk-font-name=Custom UI 11' "$test_tmp/candidates/desktop-gtk-3.0-settings.ini"
# Selecting the component outside native KDE produces an explicit skip.
export XDG_CURRENT_DESKTOP=GNOME
plan="$(apply_make_plan "$fixture_repo" "$repo_root/apply/items" "$XDG_CONFIG_HOME" "$test_tmp/skipped" desktop-fonts "$test_tmp/candidates")"
[[ "$plan" == *'|requires-native-linux-kde|1' ]]
export XDG_CURRENT_DESKTOP=KDE WSL_DISTRO_NAME=Test
plan="$(apply_make_plan "$fixture_repo" "$repo_root/apply/items" "$XDG_CONFIG_HOME" "$test_tmp/skipped" desktop-fonts "$test_tmp/candidates")"
[[ "$plan" == *'|requires-native-linux-kde|1' ]]
printf 'Declarative desktop font preflight, deployment and recovery tests passed.\n'
