#!/usr/bin/env bash
# Offline workflow: retain the real stage/item/command loops, replace host actions.
set -euo pipefail
source "$1/lib/workflow.sh"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
context="$work/context"
mkdir -p "$context" "$work/install/items" "$work/apply"
for id in first second; do
  printf '[linux.apt]\norder=10\nmethod=apt\nsource_kind=default\npackages=%s\n' "$id" > "$work/install/items/$id.conf"
done
workflow_preflight() { :; }

# Emulate sudo's controlling-terminal password read, then an installer's stdin.
# Nothing privileged runs, and the supplied text is a synthetic test value.
mkdir "$work/bin"
cat > "$work/bin/sudo" <<'SUDO'
#!/usr/bin/env bash
set -euo pipefail
printf 'READY %s\n' "$*"
read -r secret </dev/tty
[[ "$secret" == 'test input' ]]
read -r answer
[[ "$answer" == 'stdin input' ]]
printf 'INPUT_OK %s\n' "$*"
printf 'STDERR_OK\n' >&2
SUDO
chmod +x "$work/bin/sudo"
export PATH="$work/bin:$PATH"

workflow_context_set "$context" platform linux.apt
workflow_context_set "$context" profile_name linux
workflow_context_set "$context" china_mirrors 0
workflow_context_set "$context" assume_yes 1
workflow_context_set "$context" dry_run 0
workflow_context_set "$context" plan_only 0
workflow_context_set "$context" results_path ''
workflow_context_set "$context" session_path "$work/session"
workflow_context_set "$context" session_id terminal-test
workflow_context_set "$context" repo_root "$work"
for key in brew_cmd brew_prefix distro_id distro_codename inside_wsl; do workflow_context_set "$context" "$key" 0; done
printf 'install=all\n' > "$context/profile"
workflow_context_set "$context" config_home "$work/config"
printf 'linux.apt|0|brew||%s\n' "$work/backup" > "$context/install.context"
printf 'packages|1|selected||packages\nconfiguration|1|selected||configuration\n' > "$context/stages.plan"
printf 'fish\n' > "$context/components"
printf '#!/usr/bin/env bash\nprintf "NEXT_STAGE_OK\\n"\n' > "$work/apply/apply.sh"
chmod +x "$work/apply/apply.sh"
workflow_run_unlocked "$context"
[[ "$(grep -c '^INPUT_OK' "$work/session/packages.log")" == 3 ]]
[[ "$(grep -c '^STDERR_OK' "$work/session/packages.log")" == 3 ]]
printf 'OUTCOME=0\n'
