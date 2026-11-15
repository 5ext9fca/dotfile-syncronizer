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
# Exercise the real candidate planner + existing transactional file operations.
# kreadconfig supplies inherited values; no GTK/display query is needed here.
cat > "$test_tmp/bin/kreadconfig6" <<'MOCK'
#!/usr/bin/env bash
printf 'Inherited,10,-1,5,50,0,0,0,0,0\n'
MOCK
chmod +x "$test_tmp/bin/kreadconfig6"
export PATH="$test_tmp/bin:$PATH"
fc-list() { printf 'JetBrainsMono Nerd Font\nNoto Sans CJK SC\n'; }
mkdir -p "$XDG_CONFIG_HOME/gtk-3.0" "$XDG_CONFIG_HOME/gtk-4.0" "$test_tmp/candidates"
printf '# preserve\n[General]\nfont=Old,12,-1,5,50,0,0,0,0,0\nother=untouched\n' > "$XDG_CONFIG_HOME/kdeglobals"
for version in 3 4;do printf '[Settings]\ngtk-font-name=Old Sans 11\nother=untouched\n' > "$XDG_CONFIG_HOME/gtk-$version.0/settings.ini";done
chmod 640 "$XDG_CONFIG_HOME/kdeglobals"
cp "$XDG_CONFIG_HOME/kdeglobals" "$test_tmp/original"
: > "$test_tmp/plan";: > "$test_tmp/directories"
desktop_fonts_plan desktop-fonts "$XDG_CONFIG_HOME" "$test_tmp/session" "$test_tmp/candidates" "$test_tmp/plan" "$test_tmp/directories" 0 "$repo_root/configs/fontconfig/60-dotfiles-fonts.conf"
apply_execute_plan "$(cat "$test_tmp/plan")" "$test_tmp/session" 0 > "$test_tmp/result"
grep -q '^font=Noto Sans CJK SC,12,' "$XDG_CONFIG_HOME/kdeglobals"
[[ "$(stat -c '%a' "$XDG_CONFIG_HOME/kdeglobals")" == 640 ]]
: > "$test_tmp/plan";: > "$test_tmp/directories"
desktop_fonts_plan desktop-fonts "$XDG_CONFIG_HOME" "$test_tmp/session2" "$test_tmp/candidates" "$test_tmp/plan" "$test_tmp/directories" 0 "$repo_root/configs/fontconfig/60-dotfiles-fonts.conf"
[[ "$(awk -F '|' '$2=="skip" {n++} END {print n}' "$test_tmp/plan")" == 3 ]]
cp "$XDG_CONFIG_HOME/kdeglobals" "$test_tmp/deployed"
printf '# user edit\n' >> "$XDG_CONFIG_HOME/kdeglobals"
if apply_restore "$test_tmp/session/journal.tsv" 0 > "$test_tmp/restore" 2>&1;then exit 1;fi
cat "$test_tmp/deployed" > "$XDG_CONFIG_HOME/kdeglobals"
apply_restore "$test_tmp/session/journal.tsv" 0 > "$test_tmp/restore"
cmp "$test_tmp/original" "$XDG_CONFIG_HOME/kdeglobals"
# A failed publication restores the original desktop file and records rollback.
: > "$test_tmp/plan";: > "$test_tmp/directories"
desktop_fonts_plan desktop-fonts "$XDG_CONFIG_HOME" "$test_tmp/failed-session" "$test_tmp/candidates" "$test_tmp/plan" "$test_tmp/directories" 0 "$repo_root/configs/fontconfig/60-dotfiles-fonts.conf"
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
if desktop_fonts_plan desktop-fonts "$XDG_CONFIG_HOME" "$test_tmp/session3" "$test_tmp/candidates" "$test_tmp/plan" "$test_tmp/directories" 0 "$repo_root/configs/fontconfig/60-dotfiles-fonts.conf";then exit 1;fi
# Both the availability gate and rendered families follow an alternate source.
sed -e 's/Noto Sans CJK SC/Custom UI/g' -e 's/JetBrainsMono Nerd Font/Custom Mono/g' \
  "$repo_root/configs/fontconfig/60-dotfiles-fonts.conf" > "$test_tmp/custom.conf"
fc-list() { printf 'JetBrainsMono Nerd Font\nNoto Sans CJK SC\n'; }
if desktop_fonts_plan desktop-fonts "$XDG_CONFIG_HOME" "$test_tmp/custom-session" "$test_tmp/candidates" "$test_tmp/plan" "$test_tmp/directories" 0 "$test_tmp/custom.conf";then exit 1;fi
fc-list() { printf 'Custom UI\nCustom Mono\n'; }
: > "$test_tmp/plan";: > "$test_tmp/directories"
desktop_fonts_plan desktop-fonts "$XDG_CONFIG_HOME" "$test_tmp/custom-session" "$test_tmp/candidates" "$test_tmp/plan" "$test_tmp/directories" 0 "$test_tmp/custom.conf"
grep -q '^font=Custom UI,12,' "$test_tmp/candidates/desktop-kdeglobals"
grep -q '^fixed=Custom Mono,' "$test_tmp/candidates/desktop-kdeglobals"
grep -q '^gtk-font-name=Custom UI 11' "$test_tmp/candidates/desktop-gtk-3.0-settings.ini"
# Selecting the component outside native KDE produces an explicit skip.
export XDG_CURRENT_DESKTOP=GNOME
plan="$(apply_make_plan "$repo_root" "$repo_root/apply/items" "$XDG_CONFIG_HOME" "$test_tmp/skipped" desktop-fonts "$test_tmp/candidates")"
[[ "$plan" == *'|requires-native-linux-kde|1' ]]
export XDG_CURRENT_DESKTOP=KDE WSL_DISTRO_NAME=Test
plan="$(apply_make_plan "$repo_root" "$repo_root/apply/items" "$XDG_CONFIG_HOME" "$test_tmp/skipped" desktop-fonts "$test_tmp/candidates")"
[[ "$plan" == *'|requires-native-linux-kde|1' ]]
printf 'Declarative desktop font preflight, deployment and recovery tests passed.\n'
