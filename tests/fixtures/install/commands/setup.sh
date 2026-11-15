# shellcheck shell=bash
# Build a closed PATH: only pinned utilities and fake package managers exist.
setup_fake_package_commands() {
  local destination="$1" repo="$2" tool executable
  mkdir -p "$destination/bin" "$destination/state" "$destination/lib" "$destination/install/schema"
  for tool in bash env awk cat chmod cp cut date dirname grep head ln mkdir mktemp mv paste rm rmdir sed sleep sort tail touch tr;do
    executable="$(command -v "$tool")"
    [[ "$executable" == /* ]] || { printf 'missing test utility: %s\n' "$tool" >&2;return 1; }
    ln -s "$executable" "$destination/bin/$tool"
  done
  for tool in dpkg-query rpm pacman cargo brew pipx sudo apt-get apt-cache;do
    cp "$repo/tests/fixtures/install/commands/fake-package-command.sh" "$destination/bin/$tool"
    chmod +x "$destination/bin/$tool"
  done
  cp "$repo/install/schema/methods.tsv" "$destination/install/schema/methods.tsv"
  awk -F '\t' -v OFS='\t' '$1=="*" && $2=="probe" {$3=1} {print}' "$repo/install/schema/execution.tsv" > "$destination/install/schema/execution.tsv"
  export DOTFILES_TEST_PACKAGE_STATE="$destination/state"
  export PATH="$destination/bin"
  # Used by the imported installation policy reader.
  # shellcheck disable=SC2034
  install_policy_library_dir="$destination/lib"
}
