#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
source "$repo_root/lib/install-items.sh"
test_tmp="$(mktemp -d)"
trap 'rm -rf -- "$test_tmp"' EXIT
plan="$(install_items_plan "$repo_root/install/items" linux.dnf 0 0 0)"
record="$(printf '%s\n' "$plan" | awk -F '|' '$1=="docker"')"
for distro in fedora centos rhel;do
  install_dispatch docker-ce "$record" "linux.dnf|1|||$test_tmp/backups||$distro|" > "$test_tmp/plan"
  grep -Fq "https://download.docker.com/linux/$distro/docker-ce.repo" "$test_tmp/plan"
done
for distro in debian ubuntu;do
  install_dispatch docker-ce "$record" "linux.apt|1|||$test_tmp/backups||$distro|example" > "$test_tmp/plan"
  grep -Fq "https://download.docker.com/linux/$distro example stable" "$test_tmp/plan"
done
# Reject unsupported targets and missing release facts before issuing commands.
for context in 'linux.dnf|1|||||unknown|' 'linux.apt|1|||||debian|';do
  set +e
  (set -e;install_dispatch docker-ce "$record" "$context") > "$test_tmp/plan" 2> "$test_tmp/error"
  code=$?
  set -e
  [[ "$code" == 1 ]]
  [[ ! -s "$test_tmp/plan" ]]
done
# Publish against temporary files: preserve conflicts and leave correct files alone.
install_run() { shift; [[ "$1" == sudo ]];shift; "$@"; }
printf 'old\n' > "$test_tmp/target"
printf 'new\n' > "$test_tmp/source"
context="linux.dnf|0|||$test_tmp/backups|docker-ce|fedora|"
install_docker_publish "$context" "$test_tmp/source" "$test_tmp/target"
cmp "$test_tmp/source" "$test_tmp/target"
grep -qx old "$test_tmp/backups/system/docker$test_tmp/target"
install_run() { printf 'unexpected write\n' >&2;return 99; }
install_docker_publish "$context" "$test_tmp/source" "$test_tmp/target"
# A failed download must stop before repository publication or package installation.
install_docker_download() { return 23; }
set +e
(set -e; install_dispatch docker-ce "$record" "$context") > "$test_tmp/failure" 2>&1
code=$?
set -e
[[ "$code" == 23 && ! -s "$test_tmp/failure" ]]
# Moby alone is not CE; both native backends require every declared CE package.
source "$repo_root/tests/fixtures/install/commands/setup.sh"
setup_fake_package_commands "$test_tmp/commands" "$repo_root"
touch "$DOTFILES_TEST_PACKAGE_STATE/installed-moby-engine" "$DOTFILES_TEST_PACKAGE_STATE/installed-docker-cli"
for platform in linux.apt linux.dnf;do
  [[ -z "$(install_resume_package_state "$record" "$platform|0|||||fedora|")" ]]
done
for package in docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin;do
  touch "$DOTFILES_TEST_PACKAGE_STATE/installed-$package"
done
for platform in linux.apt linux.dnf;do
  [[ "$(install_resume_package_state "$record" "$platform|0|||||fedora|")" == present ]]
done
rm "$DOTFILES_TEST_PACKAGE_STATE/installed-docker-compose-plugin"
[[ -z "$(install_resume_package_state "$record" 'linux.dnf|0|||||fedora|')" ]]
printf 'Docker CE repository, backup and presence tests passed.\n'
