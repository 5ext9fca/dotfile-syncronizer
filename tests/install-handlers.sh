#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
# shellcheck source=../lib/install-items.sh
source "$repo_root/lib/install-items.sh"
test_tmp="$(mktemp -d)"
trap 'rm -rf "$test_tmp"' EXIT
# Record commands without running package managers or touching the host.
install_run() { shift; printf 'COMMAND';printf ' <%s>' "$@";printf '\n'; }
# Poison the old dynamically-scoped interface: handlers must use their arguments.
# shellcheck disable=SC2034
packages=wrong selected_source=wrong item=wrong package_manager=wrong dry_run=0
for platform in linux.apt linux.dnf linux.pacman macos; do
  plan="$(install_items_plan "$repo_root/install/items" "$platform" 1 0 0)"
  distro=;codename=
  case "$platform" in linux.apt) distro=debian;codename=trixie ;; linux.dnf) distro=fedora ;; esac
  while IFS= read -r record; do
    method="$(install_field "$record" method)"
    # Offline plans intentionally do not inspect the host package cache.
    if [[ "$method" == apt-or-snap ]]; then record="$(install_record_update "$record" state snap:helix)"; fi
    install_dispatch "$method" "$record" "$platform|1|/test/brew|/test|$test_tmp/backups||$distro|$codename" >> "$test_tmp/$platform"
  done <<< "$plan"
done
grep -Fq 'https://download.docker.com/linux/fedora/docker-ce.repo' "$test_tmp/linux.dnf"
grep -Fq '<dnf> <--enablerepo=docker-ce-stable> <install> <-y> <docker-ce> <docker-ce-cli> <containerd.io> <docker-buildx-plugin> <docker-compose-plugin>' "$test_tmp/linux.dnf"
grep -Fq 'https://download.docker.com/linux/debian trixie stable' "$test_tmp/linux.apt"
grep -Fq '<apt-get> <install> <-y> <docker-ce> <docker-ce-cli>' "$test_tmp/linux.apt"
grep -Fq '<apt-get> <install> <-y> <gh>' "$test_tmp/linux.apt"
grep -Fq '<dnf> <-y> <copr> <enable> <wezfurlong/wezterm-nightly>' "$test_tmp/linux.dnf"
grep -Fq '<pacman> <-S> <--needed> <--noconfirm> <github-cli>' "$test_tmp/linux.pacman"
grep -Fq '</test/brew> <install> <--cask> <wezterm>' "$test_tmp/macos"
grep -Fq '<PIP_INDEX_URL=https://mirrors.ustc.edu.cn/pypi/simple>' "$test_tmp/linux.apt"
grep -Fq 'source.rsproxy-sparse.registry="sparse+https://rsproxy.cn/index/"' "$test_tmp/linux.dnf"
grep -Fq '</test/opt/rustup/bin/rustup> <toolchain> <install> <stable>' "$test_tmp/macos"
grep -Fq '<snap> <install> <helix> <--classic>' "$test_tmp/linux.apt"
grep -Fq 'CODEX_NON_INTERACTIVE=1 sh -s --' "$test_tmp/linux.apt"
grep -Fq 'https://opencode.ai/install' "$test_tmp/linux.apt"
grep -Fq 'https://mirrors.ustc.edu.cn/misc/brew-install.sh' "$test_tmp/macos"
# Check per-item custom repository arguments and explicit upstream cargo source.
plan="$(install_items_plan "$repo_root/tests/fixtures/install/pacman" linux.pacman 0 0 0)"
install_dispatch pacman "$plan" 'linux.pacman|1|||' > "$test_tmp/custom"
grep -Fq '<extra/tool>' "$test_tmp/custom"
plan="$(install_items_plan "$repo_root/install/items" linux.apt 0 0 0)"
while IFS= read -r record; do
  if [[ "$(install_field "$record" id)" == starship ]]; then
    install_dispatch cargo "$record" 'linux.apt|1|||' > "$test_tmp/cargo"
  fi
done <<< "$plan"
grep -Fq '<--index> <sparse+https://index.crates.io/>' "$test_tmp/cargo"
# Real planning probe, with a fake pipx executable, skips an existing environment.
source "$repo_root/tests/fixtures/install/commands/setup.sh"
setup_fake_package_commands "$test_tmp/commands" "$repo_root"
touch "$DOTFILES_TEST_PACKAGE_STATE/installed-sample"
plan="$(install_items_plan "$repo_root/tests/fixtures/install/mirror" linux.apt 1 0 1 'linux.apt|1|||')"
[[ "$(install_field "$plan" action)" == skip ]]
rm "$test_tmp/commands/bin/pipx"
plan="$(install_record_update "$plan" action install)"
install_dispatch pipx "$plan" 'linux.apt|1|||' > "$test_tmp/upgrade"
grep -Fq '<pipx> <install> <sample>' "$test_tmp/upgrade"
# Probe timeouts are preflight failures, never a fallback installation decision.
touch "$DOTFILES_TEST_PACKAGE_STATE/probe-delay"
set +e
install_probe_apt_or_snap "$plan" > "$test_tmp/probe-timeout"
code=$?
set -e
[[ "$code" == 124 && ! -s "$test_tmp/probe-timeout" ]]
printf 'Install handler tests passed.\n'
