#!/usr/bin/env bash
# Literal package-manager placeholders are part of the fixtures.
# shellcheck disable=SC2016,SC2317
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
# shellcheck source=../lib/apply-items.sh
source "$repo_root/lib/apply-items.sh"
# shellcheck source=../lib/mirrors.sh
source "$repo_root/lib/mirrors.sh"
work="$(mktemp -d)"
work="$(cd -- "$work" && pwd -P)"
trap 'rm -rf "$work"' EXIT
test_config="$work/home/.config"
export CARGO_HOME="$work/home/.cargo" NPM_CONFIG_USERCONFIG="$work/home/.npmrc"
mkdir -p "$CARGO_HOME" "$test_config" "$work/system/etc/apt/sources.list.d" "$work/bin"
# Never query or write the host Go environment during these isolated tests.
go() { [[ "$*" == 'env GOENV' ]] && printf '%s\n' "$test_config/go/env"; }
# Called indirectly by the sourced mirror planner.
# shellcheck disable=SC2329
china_mirror_detect_package_manager() { printf 'apt\n'; }
cp "$repo_root/mirrors/current.conf" "$work/current.conf"
printf 'deb http://archive.ubuntu.com/ubuntu noble main\ndeb https://third-party.example/repo stable main\n' > "$work/system/etc/apt/sources.list"
printf 'deb https://mirrors.ustc.edu.cn/ubuntu-ports noble main\n' > "$work/system/etc/apt/sources.list.d/ports.list"
printf '[build]\njobs = 7\n' > "$CARGO_HOME/config.toml"
printf 'save-exact=true\n' > "$NPM_CONFIG_USERCONFIG"
cp "$CARGO_HOME/config.toml" "$work/unknown-cargo"
plan_for() {
  local mode="$1" label="$2"
  mkdir -p "$work/$label-scratch"
  mirror_make_plan "$work/current.conf" "$mode" "$test_config" "$work/backups/$label" "$work/$label-scratch" '' "$work/system"
}
# Installation preparation only exports process variables; no files are changed.
mirror_prepare_install "$work/current.conf"
[[ "$RUSTUP_DIST_SERVER" == https://mirrors.ustc.edu.cn/rust-static && ! -f "$test_config/fish/conf.d/15-mirrors.fish" ]]
cmp "$CARGO_HOME/config.toml" "$work/unknown-cargo"
plan="$(plan_for initialize initial)"
apply_execute_plan "$plan" "$work/backups/initial" 0 > "$work/log"
cmp "$CARGO_HOME/config.toml" "$work/unknown-cargo"
grep -Fqx 'save-exact=true' "$NPM_CONFIG_USERCONFIG"
grep -Fqx 'registry=https://registry.npmmirror.com' "$NPM_CONFIG_USERCONFIG"
grep -Fq 'https://mirrors.ustc.edu.cn/ubuntu noble' "$work/system/etc/apt/sources.list"
grep -Fqx 'deb https://third-party.example/repo stable main' "$work/system/etc/apt/sources.list"
# A legacy Cargo config is recognized, but unrelated settings must survive.
cat > "$CARGO_HOME/config.toml" <<'CARGO'
[source.crates-io]
replace-with = "rsproxy-sparse"
[source.rsproxy-sparse]
registry = "sparse+https://rsproxy.cn/index/"
[registries.rsproxy]
index = "sparse+https://rsproxy.cn/index/"
[build]
jobs = 7
CARGO
# Change current settings. initialize must not overwrite already configured tools.
awk '{sub(/^npm=.*/,"npm=https://npm.example.test");sub(/^cargo_index=.*/,"cargo_index=sparse+https://cargo.example.test/index/");sub(/^rust_dist=.*/,"rust_dist=https://rust.example.test");sub(/^ubuntu=.*/,"ubuntu=https://ubuntu.example.test/ubuntu");print}' "$work/current.conf" > "$work/next.conf"
mv "$work/next.conf" "$work/current.conf"
plan="$(plan_for initialize repeated-init)"
apply_execute_plan "$plan" "$work/backups/repeated-init" 0 > "$work/log"
grep -Fq 'sparse+https://rsproxy.cn/index/' "$CARGO_HOME/config.toml"
grep -Fqx 'registry=https://registry.npmmirror.com' "$NPM_CONFIG_USERCONFIG"
# apply must reconcile managed fields to the current values, with recovery logs.
plan="$(plan_for apply update)"
apply_execute_plan "$plan" "$work/backups/update" 0 > "$work/log"
grep -Fqx 'jobs = 7' "$CARGO_HOME/config.toml"
grep -Fq 'sparse+https://cargo.example.test/index/' "$CARGO_HOME/config.toml"
grep -Fqx 'save-exact=true' "$NPM_CONFIG_USERCONFIG"
grep -Fqx 'registry=https://npm.example.test' "$NPM_CONFIG_USERCONFIG"
grep -Fq 'https://rust.example.test' "$test_config/fish/conf.d/15-mirrors.fish"
grep -Fq 'https://ubuntu.example.test/ubuntu noble' "$work/system/etc/apt/sources.list"
# A similarly prefixed repository must not inherit the Ubuntu setting.
grep -Fq 'https://mirrors.ustc.edu.cn/ubuntu-ports noble' "$work/system/etc/apt/sources.list.d/ports.list"
plan="$(plan_for apply idempotent)"
[[ "$plan" != *'|copy|'* && "$plan" != *'|mkdir|'* ]]
apply_restore "$work/backups/update/journal.tsv" 0 > "$work/log"
grep -Fqx 'registry=https://registry.npmmirror.com' "$NPM_CONFIG_USERCONFIG"
grep -Fq 'sparse+https://rsproxy.cn/index/' "$CARGO_HOME/config.toml"
# Unknown explicit registries remain untouched in apply mode too.
printf 'registry=https://private.example.test\nsave-exact=true\n' > "$NPM_CONFIG_USERCONFIG"
cp "$NPM_CONFIG_USERCONFIG" "$work/unknown-npm"
plan="$(plan_for apply private)"
apply_execute_plan "$plan" "$work/backups/private" 0 > "$work/log"
cmp "$NPM_CONFIG_USERCONFIG" "$work/unknown-npm"
printf 'Mirror initialization/current-apply, preservation, idempotency and recovery tests passed.\n'
# DNF and Pacman use the same rendering/transaction layer without real sudo.
mkdir -p "$work/system/etc/yum.repos.d" "$work/system/etc/pacman.d"
cat > "$work/system/etc/yum.repos.d/fedora.repo" <<'DNF'
[fedora]
metalink=https://mirrors.fedoraproject.org/metalink?repo=fedora-$releasever&arch=$basearch
#baseurl=http://download.fedoraproject.org/pub/fedora/linux/releases/$releasever/Everything/$basearch/os/
enabled=1
DNF
# Called indirectly by the sourced mirror planner.
# shellcheck disable=SC2329
china_mirror_detect_package_manager() { printf 'dnf\n'; }
plan="$(plan_for initialize dnf-initial)";apply_execute_plan "$plan" "$work/backups/dnf-initial" 0 > "$work/log"
grep -Fq 'baseurl=https://mirrors.ustc.edu.cn/fedora/releases/$releasever' "$work/system/etc/yum.repos.d/fedora.repo"
grep -Fq '#metalink=' "$work/system/etc/yum.repos.d/fedora.repo"
awk '{sub(/^fedora=.*/,"fedora=https://fedora.example.test/linux");print}' "$work/current.conf" > "$work/next.conf";mv "$work/next.conf" "$work/current.conf"
plan="$(plan_for apply dnf-update)";apply_execute_plan "$plan" "$work/backups/dnf-update" 0 > "$work/log"
grep -Fq 'baseurl=https://fedora.example.test/linux/releases/' "$work/system/etc/yum.repos.d/fedora.repo"
printf 'Server = https://custom.example.test/arch/$repo/os/$arch\n' > "$work/system/etc/pacman.d/mirrorlist"
# Called indirectly by the sourced mirror planner.
# shellcheck disable=SC2329
china_mirror_detect_package_manager() { printf 'pacman\n'; }
plan="$(plan_for initialize pacman-initial)";apply_execute_plan "$plan" "$work/backups/pacman-initial" 0 > "$work/log"
grep -Fqx 'Server = https://mirrors.ustc.edu.cn/archlinux/$repo/os/$arch' "$work/system/etc/pacman.d/mirrorlist"
grep -Fqx 'Server = https://custom.example.test/arch/$repo/os/$arch' "$work/system/etc/pacman.d/mirrorlist"
awk '{sub(/^arch=.*/,"arch=https://arch.example.test/linux");print}' "$work/current.conf" > "$work/next.conf";mv "$work/next.conf" "$work/current.conf"
plan="$(plan_for apply pacman-update)";apply_execute_plan "$plan" "$work/backups/pacman-update" 0 > "$work/log"
[[ "$(head -n 1 "$work/system/etc/pacman.d/mirrorlist")" == 'Server = https://arch.example.test/linux/$repo/os/$arch' ]]
[[ "$(grep -c '^Server' "$work/system/etc/pacman.d/mirrorlist")" == 2 ]]
printf 'APT/DNF/Pacman mirror rendering tests passed.\n'
