#!/usr/bin/env bash
set -euo pipefail
[[ "$(uname -s)" == Linux ]] || { printf 'Linux entry tests skipped on this OS.\n'; exit 0; }
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
test_tmp="$(mktemp -d)"
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/repo/install/items" "$test_tmp/repo/lib" "$test_tmp/repo/apply" "$test_tmp/bin" "$test_tmp/home"
cp "$repo_root/install/linux.sh" "$test_tmp/repo/install/"
cp -R "$repo_root/install/schema" "$repo_root/install/handlers" "$test_tmp/repo/install/"
cp "$repo_root"/lib/* "$test_tmp/repo/lib/"
cp -R "$repo_root/contracts" "$test_tmp/repo/"
cp -R "$repo_root/mirrors" "$test_tmp/repo/"
cp -R "$repo_root/apply/handlers" "$repo_root/apply/schema" "$test_tmp/repo/apply/"
mkdir -p "$test_tmp/repo/apply/items"
printf '[unix]\nsource=sample\ntarget_root=config_home\ntarget=sample\nmethod=hardlink\n' > "$test_tmp/repo/apply/items/sample.conf"
mkdir -p "$test_tmp/repo/workflow/profiles"
cp -R "$repo_root/workflow/schema" "$test_tmp/repo/workflow/"
for profile in linux wsl; do
  printf 'schema_version=1\ninstall=all\ncomponents=sample:sample\nshell=fish\nmirrors=initialize\nwsl=none\n' > "$test_tmp/repo/workflow/profiles/$profile.conf"
done
for manager in apt dnf pacman; do
  cat >> "$test_tmp/repo/install/items/sample.conf" <<CONFIG
[linux.$manager]
order=1
method=$manager
packages=sample
source_kind=default
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
# Downstream validation failure must prevent even package preparation.
cp "$test_tmp/repo/apply/apply.sh" "$test_tmp/apply-good"
cat > "$test_tmp/repo/apply/apply.sh" <<'STUB'
#!/usr/bin/env bash
exit 42
STUB
set +e
PATH="$test_tmp/bin:$PATH" HOME="$test_tmp/home" bash "$test_tmp/repo/install/linux.sh" --yes --no-china-mirrors > "$test_tmp/preflight-error" 2>&1
status=$?
set -e
[[ "$status" == 42 && ! -e "$INSTALL_TEST_COMMANDS" && ! -e "$INSTALL_TEST_APPLY" ]]
cp "$test_tmp/apply-good" "$test_tmp/repo/apply/apply.sh"
set +e
PATH="$test_tmp/bin:$PATH" HOME="$test_tmp/home" bash "$test_tmp/repo/install/linux.sh" --yes --no-china-mirrors --results "$test_tmp/results" > "$test_tmp/output" 2>&1
status=$?
set -e
[[ "$status" == 19 && ! -e "$INSTALL_TEST_APPLY" ]]
grep -q '|packages|failed|19|' "$test_tmp/results"
grep -q '|configuration|blocked|' "$test_tmp/results"
package_report="$(awk -F '|' '$3=="packages" {print $8}' "$test_tmp/results")"
grep -q '^sample|failed|' "$package_report"
# CLI resume preserves upstream mode and a new session links back to the old one.
old_session="$(dirname -- "$package_report")"
PATH="$test_tmp/bin:$PATH" HOME="$test_tmp/home" bash "$test_tmp/repo/install/linux.sh" --resume "$old_session" --plan > "$test_tmp/resume-plan" 2>&1
grep -q 'Stage mirrors: skipped (resume-selection)' "$test_tmp/resume-plan"
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
printf 'unknown=value\n' >> "$test_tmp/repo/install/items/sample.conf"
set +e
PATH="$test_tmp/bin:$PATH" HOME="$test_tmp/home" bash "$test_tmp/repo/install/linux.sh" --yes --no-china-mirrors > "$test_tmp/error" 2>&1
status=$?
set -e
[[ "$status" != 0 && ! -e "$INSTALL_TEST_COMMANDS" && ! -e "$INSTALL_TEST_APPLY" ]]
# Verify the lifecycle: packages -> deployment -> first mirror initialization.
sed '$d' "$test_tmp/repo/install/items/sample.conf" > "$test_tmp/valid.conf"
mv "$test_tmp/valid.conf" "$test_tmp/repo/install/items/sample.conf"
cat > "$test_tmp/bin/sudo" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$INSTALL_TEST_COMMANDS"
exit 0
STUB
cat > "$test_tmp/repo/apply/apply.sh" <<'STUB'
#!/usr/bin/env bash
if [[ " $* " == *' --plan '* ]]; then
  source "$(dirname -- "$0")/../lib/data-contract.sh"
  contract_write apply-plan ''
  exit
fi
printf 'configuration %s\n' "$*" >> "$INSTALL_TEST_COMMANDS"
[[ " $* " == *' --no-mirrors '* ]]
STUB
cat > "$test_tmp/repo/apply/mirrors.sh" <<'STUB'
#!/usr/bin/env bash
if [[ " $* " == *' --plan '* ]]; then
  source "$(dirname -- "$0")/../lib/data-contract.sh"
  contract_write apply-plan ''
  exit
fi
printf 'mirrors %s\n' "$*" >> "$INSTALL_TEST_COMMANDS"
[[ "$1" == --initialize ]]
STUB
chmod +x "$test_tmp/repo/apply/mirrors.sh"
PATH="$test_tmp/bin:$PATH" HOME="$test_tmp/home" bash "$test_tmp/repo/install/linux.sh" --yes > "$test_tmp/lifecycle" 2>&1
awk '
  /install -y sample|pacman -S --needed/ {installed=NR}
  /^configuration / {configured=NR}
  /^mirrors --initialize/ {initialized=NR}
  END {exit !(installed && configured>installed && initialized>configured)}
' "$INSTALL_TEST_COMMANDS"
[[ ! -e "$test_tmp/home/.cargo/config.toml" && ! -e "$test_tmp/home/.npmrc" ]]
# Explicit retry from configuration must not repeat package preparation/install.
: > "$INSTALL_TEST_COMMANDS"
PATH="$test_tmp/bin:$PATH" HOME="$test_tmp/home" bash "$test_tmp/repo/install/linux.sh" --yes --from-stage configuration --no-china-mirrors > "$test_tmp/retry" 2>&1
if grep -q 'apt-get\|pacman\|dnf' "$INSTALL_TEST_COMMANDS"; then exit 1; fi
grep -q '^configuration ' "$INSTALL_TEST_COMMANDS"
# Component-only execution does not change the login shell or initialize mirrors.
: > "$INSTALL_TEST_COMMANDS"
PATH="$test_tmp/bin:$PATH" HOME="$test_tmp/home" bash "$test_tmp/repo/install/linux.sh" --yes --only-stage configuration > "$test_tmp/component-only" 2>&1
[[ "$(wc -l < "$INSTALL_TEST_COMMANDS")" -eq 1 ]]
# Package-only execution must not invoke deployment, mirrors or login-shell work.
: > "$INSTALL_TEST_COMMANDS"
PATH="$test_tmp/bin:$PATH" HOME="$test_tmp/home" bash "$test_tmp/repo/install/linux.sh" --yes --only-stage packages --no-china-mirrors > "$test_tmp/package-only" 2>&1
if grep -q 'configuration\|mirrors\|chsh' "$INSTALL_TEST_COMMANDS"; then exit 1; fi
# Invalid output destinations fail before the first package-manager command.
: > "$INSTALL_TEST_COMMANDS"
set +e
PATH="$test_tmp/bin:$PATH" HOME="$test_tmp/home" bash "$test_tmp/repo/install/linux.sh" --yes --no-china-mirrors --results "$test_tmp/repo/unsafe-report" > "$test_tmp/bad-report" 2>&1
status=$?
set -e
[[ "$status" != 0 && ! -s "$INSTALL_TEST_COMMANDS" && ! -e "$test_tmp/repo/unsafe-report" ]]
# Dry runs create persistent session artifacts only when explicitly requested.
PATH="$test_tmp/bin:$PATH" HOME="$test_tmp/home" DOTFILES_BACKUP_DIR="$test_tmp/dry-backups" bash "$test_tmp/repo/install/linux.sh" --yes --dry-run --only-stage configuration > "$test_tmp/dry" 2>&1
[[ ! -e "$test_tmp/dry-backups" ]]
PATH="$test_tmp/bin:$PATH" HOME="$test_tmp/home" DOTFILES_BACKUP_DIR="$test_tmp/dry-backups" bash "$test_tmp/repo/install/linux.sh" --yes --dry-run --only-stage configuration --results "$test_tmp/dry.tsv" > "$test_tmp/dry-report" 2>&1
grep -q '|configuration|planned|' "$test_tmp/dry.tsv"
[[ -d "$test_tmp/dry-backups" ]]
# Exercise real deployment through the installer and recover via its linked journal.
cp "$repo_root/apply/apply.sh" "$test_tmp/repo/apply/apply.sh"
mkdir -p "$test_tmp/repo/sample" "$test_tmp/home/.config/sample"
printf 'repository configuration\n' > "$test_tmp/repo/sample/config"
printf 'original configuration\n' > "$test_tmp/home/.config/sample/config"
PATH="$test_tmp/bin:$PATH" HOME="$test_tmp/home" XDG_CONFIG_HOME="$test_tmp/home/.config" bash "$test_tmp/repo/install/linux.sh" --yes --only-stage configuration --results "$test_tmp/real-apply.tsv" > "$test_tmp/real-apply.log" 2>&1
[[ "$test_tmp/repo/sample/config" -ef "$test_tmp/home/.config/sample/config" ]]
journal="$(awk -F '|' '$3=="configuration" {print $9}' "$test_tmp/real-apply.tsv")"
[[ -f "$journal" ]]
HOME="$test_tmp/home" "$test_tmp/repo/apply/apply.sh" --restore "$journal" > "$test_tmp/restore.log"
grep -q '^original configuration$' "$test_tmp/home/.config/sample/config"
printf 'Linux workflow preflight, stage selection, reports, recovery and mirror lifecycle tests passed.\n'
