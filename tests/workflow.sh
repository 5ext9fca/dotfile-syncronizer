#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
# shellcheck source=../lib/install-items.sh
source "$repo_root/lib/install-items.sh"
# shellcheck source=../lib/workflow.sh
source "$repo_root/lib/workflow.sh"
test_tmp="$(mktemp -d)"
trap 'rm -rf "$test_tmp"' EXIT
for profile_name in linux wsl macos windows; do
  profile="$(workflow_read_profile "$repo_root/workflow/profiles/$profile_name.conf")"
  platform="$profile_name"; wsl=0
  case "$profile_name" in linux) platform=linux.apt ;; wsl) platform=linux.dnf;wsl=1 ;; esac
  plan="$(install_items_plan "$repo_root/install/items" "$platform" 1 "$wsl" 0)"
  components="$(workflow_profile_components "$profile" "$plan")"
  [[ -n "$components" ]]
done
# Item selection includes dependencies and rejects misspelled references.
profile=$'install=leaf\ncomponents=leaf:leaf\nshell=none\nmirrors=none\nwsl=none'
# The imported field accessor reads this fixture schema.
# shellcheck disable=SC2034
install_field_names='id depends_on action install_depends_on'
plan=$'base||install|\nleaf|base|install|\nother||install|'
[[ "$(workflow_profile_install_plan "$profile" "$plan")" == $'base||install|\nleaf|base|install|' ]]
if workflow_profile_install_plan 'install=missing' "$plan" >/dev/null 2>&1; then exit 1; fi
# Reject values as data rather than executing or silently ignoring them.
# shellcheck disable=SC2016
for invalid in 'unknown=value' 'shell=bash' 'mirrors=apply' 'components=fish:fish  git:git' 'wsl=$(touch bad)' 'install='; do
  printf 'schema_version=1\ninstall=all\ncomponents=fish:fish\nshell=fish\nmirrors=initialize\nwsl=none\n%s\n' "$invalid" > "$test_tmp/invalid.conf"
  if workflow_read_profile "$test_tmp/invalid.conf" >/dev/null 2>&1; then printf 'Accepted invalid profile: %s\n' "$invalid" >&2; exit 1; fi
done
context="$test_tmp/context";mkdir "$context"
profile=$'shell=fish\nmirrors=initialize\nwsl=none'
# Poison the old dynamic interface: selection must come from the context only.
# shellcheck disable=SC2034
only_stage=packages from_stage=shell workflow_profile='shell=none'
workflow_stage_plan unix "$profile" configuration '' 1 > "$context/stages.plan"
workflow_stage_enabled "$context" configuration
if workflow_stage_enabled "$context" packages;then exit 1;fi
workflow_stage_plan unix "$profile" '' mirrors 1 > "$context/stages.plan"
workflow_stage_enabled "$context" mirrors
workflow_stage_enabled "$context" shell
if workflow_stage_enabled "$context" configuration;then exit 1;fi
if workflow_stage_plan unix "$profile" configuration mirrors 1 >/dev/null 2>&1;then exit 1;fi
# Output directories must not occupy a file that mirror initialization will create.
workflow_context_set "$context" session_path "$test_tmp/config.toml/session"
workflow_context_set "$context" results_path ''
if workflow_validate_plan_outputs "$context" "mirrors|copy|$test_tmp/rendered|$test_tmp/config.toml||||||new" >/dev/null 2>&1;then exit 1;fi
# Native adapters must honor explicit context rather than the entry globals.
workflow_context_set "$context" platform linux.apt
workflow_context_set "$context" dry_run 1
# shellcheck disable=SC2034
dry_run=0 package_manager=pacman
mkdir "$test_tmp/bin"
printf '#!/usr/bin/env bash\nexit 88\n' > "$test_tmp/bin/sudo"
chmod +x "$test_tmp/bin/sudo"
# shellcheck disable=SC2034
install_field_names="$(contract_fields install-plan | tr '|' ' ')"
install_items_plan "$repo_root/tests/fixtures/install/dependencies" linux.apt 0 0 0 > "$context/install.plan"
PATH="$test_tmp/bin:$PATH" workflow_prepare_packages "$context" > "$test_tmp/preparation"
grep -q '^DRY RUN: sudo apt-get update$' "$test_tmp/preparation"
# Preparation follows pending recipes, not merely the selected stage/platform.
record="$(head -n 1 "$context/install.plan")"
install_record_update "$record" action skip > "$context/install.plan"
PATH="$test_tmp/bin:$PATH" workflow_prepare_packages "$context" > "$test_tmp/preparation"
[[ ! -s "$test_tmp/preparation" ]]
install_record_update "$record" method cargo > "$context/install.plan"
PATH="$test_tmp/bin:$PATH" workflow_prepare_packages "$context" > "$test_tmp/preparation"
[[ ! -s "$test_tmp/preparation" ]]
install_record_update "$record" method apt-or-snap state snap:tool > "$context/install.plan"
PATH="$test_tmp/bin:$PATH" workflow_prepare_packages "$context" > "$test_tmp/preparation"
[[ ! -s "$test_tmp/preparation" ]]
workflow_context_set "$context" platform linux.pacman
install_record_update "$record" method pacman > "$context/install.plan"
PATH="$test_tmp/bin:$PATH" workflow_prepare_packages "$context" > "$test_tmp/preparation"
grep -q 'pacman -Syu --noconfirm' "$test_tmp/preparation"
if grep -q 'pacman -R' "$test_tmp/preparation";then exit 1;fi
install_record_update "$record" method pacman action skip > "$context/install.plan"
PATH="$test_tmp/bin:$PATH" workflow_prepare_packages "$context" > "$test_tmp/preparation"
[[ ! -s "$test_tmp/preparation" ]]
# Only a pending toolchain requests removal of the conflicting package.
(
  # shellcheck disable=SC2329
  install_probe_capture() { printf 'rust-analyzer\n'; }
  install_record_update "$record" method rustup > "$context/install.plan"
  PATH="$test_tmp/bin:$PATH" workflow_prepare_packages "$context" > "$test_tmp/preparation"
  grep -q 'pacman -R --noconfirm rust-analyzer' "$test_tmp/preparation"
  if grep -q 'pacman -Syu' "$test_tmp/preparation";then exit 1;fi
)
# A GUI prerequisite is a deferred stage, with no downstream execution.
cat > "$test_tmp/deferred.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
source "$1/lib/workflow.sh"
workflow_preflight() { :; }
workflow_execute_stage() { printf 'requested GUI prerequisite\n'; return 75; }
context="$2/deferred-context";mkdir "$context"
workflow_context_set "$context" session_path "$2/session"
workflow_context_set "$context" results_path "$2/deferred.tsv"
workflow_context_set "$context" china_mirrors 1
workflow_context_set "$context" profile_name macos
workflow_context_set "$context" platform macos
workflow_context_set "$context" session_id deferred
workflow_context_set "$context" dry_run 0
workflow_context_set "$context" plan_only 0
workflow_stage_plan unix $'shell=fish\nmirrors=initialize\nwsl=none' '' '' 1 > "$context/stages.plan"
workflow_run "$context"
SCRIPT
set +e
"$BASH" "$test_tmp/deferred.sh" "$repo_root" "$test_tmp" > "$test_tmp/deferred.log" 2>&1
status=$?
set -e
[[ "$status" == 75 ]]
grep -q '|packages|deferred|75|' "$test_tmp/deferred.tsv"
[[ "$(awk -F '|' '$4=="blocked" {n++} END {print n+0}' "$test_tmp/deferred.tsv")" == 3 ]]
printf 'Unix workflow profiles, dependency selection, stage selection and deferred-stage tests passed.\n'
