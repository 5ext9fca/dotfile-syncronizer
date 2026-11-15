#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
# shellcheck source=../lib/workflow.sh
source "$repo_root/lib/workflow.sh"
test_tmp="$(mktemp -d)"
test_tmp="$(cd "$test_tmp" && pwd -P)"
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/home" "$test_tmp/items" "$test_tmp/source" "$test_tmp/bin"
export DOTFILES_DEPLOYMENT_LOCK="$test_tmp/lease"
export HOME="$test_tmp/home" XDG_CONFIG_HOME="$test_tmp/home/.config" DOTFILES_BACKUP_DIR="$test_tmp/backups"
fail() { printf 'FAIL: %s\n' "$*" >&2;exit 1; }
reject() { if "$@" > "$test_tmp/reject.log" 2>&1;then fail "accepted $*";fi; }
for name in linux macos windows wsl;do
  profile="$(workflow_read_profile "$(workflow_profile_path "$repo_root" "$name")")"
  [[ "$(workflow_profile_value "$profile" install)" == none ]] || fail 'default installs'
  [[ "$(workflow_profile_value "$profile" components)" != *desktop-fonts* ]] || fail 'default fonts'
  [[ -z "$(workflow_profile_install_plan "$profile" '' '' normal)" ]] || fail 'none selected installation'
  full="$(workflow_read_profile "$(workflow_profile_path "$repo_root" "$name-full")")"
  [[ "$(workflow_profile_value "$full" install)" == all ]] || fail 'full lost installations'
done
for name in ../linux /tmp/linux Linux 'linux.conf' 'linux;echo';do reject workflow_profile_path "$repo_root" "$name";done
reject workflow_read_profile "$test_tmp/missing.conf"
# Installation discovery must not be reached at all with install=none.
context="$test_tmp/context";mkdir "$context"
printf 'install=none\n' > "$context/profile"
install_items_plan() { fail 'installation discovery called'; }
[[ -z "$(workflow_refresh_install_plan "$context")" ]] || fail 'unexpected installation plan'
workflow_stage_plan unix $'install=none\ncomponents=none\nshell=none\nmirrors=none\nwsl=none' '' '' 0 > "$context/stages.plan"
if grep -q '|1|' "$context/stages.plan";then fail 'empty profile enabled a stage';fi
# Shared root mapping resolves only selected roots; home permits single dotfiles.
printf 'zsh\n' > "$test_tmp/source/zsh"
printf 'git\n' > "$test_tmp/source/git"
printf '[unix]\nsource=zsh\ntarget_root=home\ntarget=.zshrc\nmethod=hardlink\n' > "$test_tmp/items/zsh.conf"
printf '[unix]\nsource=git\ntarget_root=home\ntarget=.gitconfig\nmethod=copy\n' > "$test_tmp/items/git.conf"
roots="$(printf 'home|%s\nconfig_home|relative-invalid\n' "$HOME")"
plan="$(apply_make_plan "$test_tmp/source" "$test_tmp/items" '' "$test_tmp/backup" '' '' 0 "$roots")"
[[ "$plan" == *"$HOME/.zshrc"* && "$plan" == *"$HOME/.gitconfig"* ]] || fail 'wrong home targets'
reject apply_validate_results "$HOME/.zshrc" "$plan"
printf 'old\n' > "$HOME/.gitconfig"
plan="$(apply_make_plan "$test_tmp/source" "$test_tmp/items" '' "$test_tmp/backup" '' '' 0 "$roots")"
apply_execute_plan "$plan" "$test_tmp/backup" 0 > "$test_tmp/deploy.log"
[[ "$test_tmp/source/zsh" -ef "$HOME/.zshrc" ]] || fail 'hardlink missing'
again="$(apply_make_plan "$test_tmp/source" "$test_tmp/items" '' "$test_tmp/again" '' '' 0 "$roots")"
[[ "$(printf '%s\n' "$again" | awk -F '|' '$2=="skip" {n++} END {print n+0}')" == 2 ]] || fail 'rerun changed targets'
apply_restore "$test_tmp/backup/journal.tsv" 0 > "$test_tmp/restore.log"
[[ "$(cat "$HOME/.gitconfig")" == old && ! -e "$HOME/.zshrc" ]] || fail 'restore failed'
for roots in 'home|' 'home|relative';do reject apply_make_plan "$test_tmp/source" "$test_tmp/items" '' "$test_tmp/unused" zsh '' 1 "$roots";done
# Equivalent destinations under separate roots conflict, including parent/child pairs.
sed 's/target=.gitconfig/target=.config\/git/' "$test_tmp/items/git.conf" > "$test_tmp/new";mv "$test_tmp/new" "$test_tmp/items/git.conf"
printf '[unix]\nsource=zsh\ntarget_root=config_home\ntarget=git/config\nmethod=copy\n' > "$test_tmp/items/zsh.conf"
roots="$(printf 'home|%s\nconfig_home|%s\n' "$HOME" "$XDG_CONFIG_HOME")"
reject apply_make_plan "$test_tmp/source" "$test_tmp/items" '' "$test_tmp/unused" '' '' 1 "$roots"
[[ -z "$(apply_make_plan "$test_tmp/source" "$test_tmp/items" '' "$test_tmp/unused" none '' 1 'home|')" ]] || fail 'none became all'
# Resolving aliases before conflict checks prevents equivalent root bypasses.
mkdir -p "$XDG_CONFIG_HOME"
ln -s "$XDG_CONFIG_HOME" "$test_tmp/config-alias"
roots="$(printf 'home|%s\nconfig_home|%s\n' "$HOME" "$test_tmp/config-alias")"
reject apply_make_plan "$test_tmp/source" "$test_tmp/items" '' "$test_tmp/unused" '' '' 1 "$roots"
rmdir "$XDG_CONFIG_HOME"
rm "$test_tmp/config-alias"
# Actual CLI tests use a copied declaration tree, never the live configuration.
mkdir "$test_tmp/repo"
for path in lib install apply workflow contracts configs mirrors;do cp -R "$repo_root/$path" "$test_tmp/repo/";done
cat > "$test_tmp/repo/workflow/profiles/custom.conf" <<'PROFILE'
schema_version=2
install=none
components=git
shell=none
mirrors=none
wsl=none
wsl_profile=none
PROFILE
cp "$test_tmp/repo/workflow/profiles/custom.conf" "$test_tmp/repo/workflow/profiles/empty.conf"
sed 's/components=git/components=none/' "$test_tmp/repo/workflow/profiles/empty.conf" > "$test_tmp/empty";mv "$test_tmp/empty" "$test_tmp/repo/workflow/profiles/empty.conf"
for command in brew sudo chsh wsl.exe;do
  printf '#!/bin/sh\necho forbidden >> "%s"\nexit 91\n' "$test_tmp/forbidden" > "$test_tmp/bin/$command";chmod +x "$test_tmp/bin/$command"
done
export PATH="$test_tmp/bin:$PATH" DOTFILES_MIRROR_CONFIG="$test_tmp/missing-mirrors"
entry=linux;entry_args=(--yes)
if [[ "$(uname -s)" == Darwin ]];then entry=macos;entry_args=();fi
bash "$test_tmp/repo/install/$entry.sh" ${entry_args[@]+"${entry_args[@]}"} --profile custom --dry-run --results "$test_tmp/result" > "$test_tmp/entry.log"
grep -q '|configuration|planned|' "$test_tmp/result"
grep -q '|packages|skipped|' "$test_tmp/result"
bash "$test_tmp/repo/install/$entry.sh" ${entry_args[@]+"${entry_args[@]}"} --profile empty --plan > "$test_tmp/empty.log"
[[ ! -e "$test_tmp/forbidden" ]] || fail 'configuration-only entry called native installation'
bash "$test_tmp/repo/apply/apply.sh" --profile custom --plan > "$test_tmp/apply.log"
grep -q '^git|' "$test_tmp/apply.log"
if grep -q '^fish|' "$test_tmp/apply.log";then fail 'profile ignored';fi
bash "$test_tmp/repo/apply/apply.sh" fish --plan > "$test_tmp/fish.log"
reject bash "$test_tmp/repo/apply/apply.sh" --profile custom fish --plan
reject bash "$test_tmp/repo/install/$entry.sh" ${entry_args[@]+"${entry_args[@]}"} --profile ../custom --plan
reject bash "$test_tmp/repo/install/$entry.sh" ${entry_args[@]+"${entry_args[@]}"} --profile absent --plan
[[ ! -d "$XDG_CONFIG_HOME" ]] || fail 'dry run deployed configuration'
# Apply ignores profile mirror settings; installer CLI overrides those settings.
sed 's/mirrors=none/mirrors=initialize/' "$test_tmp/repo/workflow/profiles/custom.conf" > "$test_tmp/mirror-profile"
mv "$test_tmp/mirror-profile" "$test_tmp/repo/workflow/profiles/custom.conf"
bash "$test_tmp/repo/apply/apply.sh" --profile custom --plan > "$test_tmp/apply-initialize.log"
bash "$test_tmp/repo/install/$entry.sh" ${entry_args[@]+"${entry_args[@]}"} --profile custom --no-china-mirrors --plan > "$test_tmp/no-mirrors.log"
grep -q 'Stage mirrors: skipped (disabled)' "$test_tmp/no-mirrors.log"
reject bash "$test_tmp/repo/install/$entry.sh" --profile empty --china-mirrors --only-stage mirrors --plan
# Restore the HOME declarations and ensure workflow sessions can live below HOME.
printf '[unix]\nsource=configs/git/config\ntarget_root=home\ntarget=.gitconfig\nmethod=copy\n' > "$test_tmp/repo/apply/items/git.conf"
XDG_CONFIG_HOME=invalid-relative DOTFILES_BACKUP_DIR="$HOME/.backups" bash "$test_tmp/repo/install/$entry.sh" --profile custom --no-china-mirrors --plan > "$test_tmp/home-plan"
reject env DOTFILES_BACKUP_DIR="$HOME/.gitconfig" bash "$test_tmp/repo/install/$entry.sh" --profile custom --no-china-mirrors --plan
printf 'Profile defaults, isolated CLI selection, target roots, backup and recovery tests passed.\n'
