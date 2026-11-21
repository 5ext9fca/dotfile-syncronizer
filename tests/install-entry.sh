#!/usr/bin/env bash
set -euo pipefail
[[ "$(uname -s)" == Linux ]] || { printf 'Linux entry tests skipped on this OS.\n'; exit 0; }
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
test_tmp="$(mktemp -d)"
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/repo/software/items" "$test_tmp/repo/install" "$test_tmp/repo/lib" "$test_tmp/repo/apply" "$test_tmp/bin" "$test_tmp/home"
export DOTFILES_CATALOG="$test_tmp/repo" DOTFILES_DEPLOYMENT_LOCK="$test_tmp/lease"
cp "$repo_root/install/linux.sh" "$test_tmp/repo/install/"
cp -R "$repo_root/install/schema" "$repo_root/install/handlers" "$test_tmp/repo/install/"
cp "$repo_root"/lib/* "$test_tmp/repo/lib/"
cp -R "$repo_root/contracts" "$repo_root/dotfiles_core" "$test_tmp/repo/"
export DOTFILES_PYTHON="${DOTFILES_PYTHON:-$repo_root/.venv/bin/python}"
cp -R "$repo_root/mirrors" "$test_tmp/repo/"
cp -R "$repo_root/apply/handlers" "$repo_root/apply/schema" "$test_tmp/repo/apply/"
mkdir -p "$test_tmp/repo/apply/items"
printf '[unix]\nsource=sample\ntarget_root=config_home\ntarget=sample\nmethod=hardlink\n' > "$test_tmp/repo/apply/items/sample.conf"
mkdir -p "$test_tmp/repo/workflow/profiles"
cp -R "$repo_root/workflow/schema" "$test_tmp/repo/workflow/"
for profile in linux wsl; do
  printf 'schema_version=3\nsoftware=all\n' > "$test_tmp/repo/workflow/profiles/$profile.conf"
done
printf 'schema_version = 1\n' > "$test_tmp/repo/software/items/sample.toml"
for manager in apt dnf pacman; do
  cat >> "$test_tmp/repo/software/items/sample.toml" <<CONFIG
[install."linux.$manager"]
order="1"
method="$manager"
packages="sample"
source_kind="default"
CONFIG
done
cat > "$test_tmp/bin/fish" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$test_tmp/bin/fish"
# The only privileged-command entry is replaced; nothing reaches real sudo.
cat > "$test_tmp/bin/sudo" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$INSTALL_TEST_COMMANDS"
case "$*" in
  'apt-get update'|'pacman -Syu --noconfirm') exit 0 ;;
  *) exit 19 ;;
esac
STUB
cat > "$test_tmp/repo/apply/apply.sh" <<'STUB'
#!/usr/bin/env bash
if [[ " $* " == *' --plan '* ]]; then
  source "$(dirname -- "$0")/../lib/data-contract.sh"
  contract_write apply-plan ''
  exit
fi
printf 'unexpected apply\n' > "$INSTALL_TEST_APPLY"
exit 99
STUB
chmod +x "$test_tmp/bin/sudo" "$test_tmp/repo/apply/apply.sh"
export INSTALL_TEST_COMMANDS="$test_tmp/commands" INSTALL_TEST_APPLY="$test_tmp/applied"
# Inspection-only mode neither prompts nor invokes preparation or deployment.
PATH="$test_tmp/bin:$PATH" HOME="$test_tmp/home" bash "$test_tmp/repo/install/linux.sh" --plan --no-china-mirrors > "$test_tmp/plan"
[[ ! -e "$INSTALL_TEST_COMMANDS" && ! -e "$INSTALL_TEST_APPLY" ]]
grep -q '^sample|' "$test_tmp/plan"
set +e
PATH="$test_tmp/bin:$PATH" HOME="$test_tmp/home" bash "$test_tmp/repo/install/linux.sh" --yes --no-china-mirrors --results "$test_tmp/results" > "$test_tmp/output" 2>&1
status=$?
set -e
[[ "$status" == 19 && ! -e "$INSTALL_TEST_APPLY" ]]
grep -q '|packages|failed|19|' "$test_tmp/results"
package_report="$(awk -F '|' '$3=="packages" {print $8}' "$test_tmp/results")"
grep -q '^sample|failed|' "$package_report"
# CLI resume preserves upstream mode and a new session links back to the old one.
old_session="$(dirname -- "$package_report")"
PATH="$test_tmp/bin:$PATH" HOME="$test_tmp/home" bash "$test_tmp/repo/install/linux.sh" --resume "$old_session" --plan > "$test_tmp/resume-plan" 2>&1
grep -q 'Stage packages:' "$test_tmp/resume-plan"
set +e
PATH="$test_tmp/bin:$PATH" HOME="$test_tmp/home" bash "$test_tmp/repo/install/linux.sh" --resume "$old_session" --yes --results "$test_tmp/resume-results" > "$test_tmp/resume-log" 2>&1
status=$?
set -e
[[ "$status" == 19 ]]
new_session="$(dirname -- "$(awk -F '|' '$3=="packages" {print $8}' "$test_tmp/resume-results")")"
[[ "$new_session" != "$old_session" ]]
grep -Fq "|$old_session|0" "$new_session/request.tsv"
# Invalid configuration must be rejected before even preparation is attempted.
rm "$INSTALL_TEST_COMMANDS"
printf 'unknown="value"\n' >> "$test_tmp/repo/software/items/sample.toml"
set +e
PATH="$test_tmp/bin:$PATH" HOME="$test_tmp/home" bash "$test_tmp/repo/install/linux.sh" --yes --no-china-mirrors > "$test_tmp/error" 2>&1
status=$?
set -e
[[ "$status" != 0 && ! -e "$INSTALL_TEST_COMMANDS" && ! -e "$INSTALL_TEST_APPLY" ]]
# Restore the valid declaration for output and preview checks.
sed '$d' "$test_tmp/repo/software/items/sample.toml" > "$test_tmp/valid"
mv "$test_tmp/valid" "$test_tmp/repo/software/items/sample.toml"
# Invalid output destinations fail before the first package-manager command.
: > "$INSTALL_TEST_COMMANDS"
set +e
PATH="$test_tmp/bin:$PATH" HOME="$test_tmp/home" bash "$test_tmp/repo/install/linux.sh" --yes --no-china-mirrors --results "$test_tmp/repo/unsafe-report" > "$test_tmp/bad-report" 2>&1
status=$?
set -e
[[ "$status" != 0 && ! -s "$INSTALL_TEST_COMMANDS" && ! -e "$test_tmp/repo/unsafe-report" ]]
# Dry runs create persistent session artifacts only when explicitly requested.
PATH="$test_tmp/bin:$PATH" HOME="$test_tmp/home" DOTFILES_BACKUP_DIR="$test_tmp/dry-backups" bash "$test_tmp/repo/install/linux.sh" --yes --dry-run --only-stage packages > "$test_tmp/dry" 2>&1
[[ ! -e "$test_tmp/dry-backups" ]]
PATH="$test_tmp/bin:$PATH" HOME="$test_tmp/home" DOTFILES_BACKUP_DIR="$test_tmp/dry-backups" bash "$test_tmp/repo/install/linux.sh" --yes --dry-run --only-stage packages --results "$test_tmp/dry.tsv" > "$test_tmp/dry-report" 2>&1
grep -q '|packages|planned|' "$test_tmp/dry.tsv"
[[ -d "$test_tmp/dry-backups" ]]
printf 'Linux installation-only preflight, failure, resume and report tests passed.\n'
