#!/usr/bin/env bash
# Fixed native operations only. Request data is never evaluated as shell code.
set -euo pipefail
adapter_library_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=python.sh
source "$adapter_library_dir/python.sh"
request_path="$1" result_path="$2"
arguments_path="${result_path}.arguments" payload_path="${result_path}.payload"
dotfiles_python_init
dotfiles_python native-input --platform unix --request "$request_path" --payload "$arguments_path"
{
  IFS= read -r -d '' operation
  IFS= read -r -d '' first
  IFS= read -r -d '' second
  IFS= read -r -d '' mode
  if [[ "$operation" != publish-report ]];then IFS= read -r -d '' extra;fi
  if [[ "$operation" == workflow-stage ]];then IFS= read -r -d '' log_path;fi
} < "$arguments_path"
: > "$payload_path"
adapter_finish() {
  local code=$?
  trap - EXIT
  dotfiles_python native-result --platform unix --request "$request_path" --result "$result_path" --payload "$payload_path" --code "$code" || exit 65
  exit "$code"
}
trap adapter_finish EXIT
case "$operation" in
  apply-restore)
    # shellcheck source=apply-items.sh
    source "$adapter_library_dir/apply-items.sh"
    apply_restore_unlocked "$first" "$second" ;;
  apply-effect)
    # shellcheck source=apply-items.sh
    source "$adapter_library_dir/apply-items.sh"
    case "$first" in
      start)
        [[ ! -e "$second" && ! -L "$second" ]] || { printf 'error: session already exists\n' >&2;exit 1; }
        mkdir -p "$second"
        printf '# dotfiles-apply-journal-v1\n' > "$second/journal.tsv" ;;
      transaction) apply_transaction "$mode" "$second" "$extra" ;;
      preview)
        IFS='|' read -r _component action source target backup _rest <<< "$mode"
        [[ -z "$backup" ]] || printf 'DRY RUN: back up %q to %q\n' "$target" "$backup"
        printf 'DRY RUN: %s %q -> %q\n' "$action" "$source" "$target" ;;
      *) exit 65 ;;
    esac ;;
  workflow-shell-command)
    # shellcheck source=workflow.sh
    source "$adapter_library_dir/workflow.sh"
    workflow_set_shell "$first" ;;
  workflow-prepare-command)
    # shellcheck source=command.sh
    source "$adapter_library_dir/command.sh"
    case "$first" in
      apt-update) command_run mutation "$second" 0 '' -- sudo apt-get update ;;
      pacman-upgrade) command_run mutation "$second" 0 '' -- sudo pacman -Syu --noconfirm ;;
      pacman-remove-rust-analyzer) command_run mutation "$second" 0 '' -- sudo pacman -R --noconfirm rust-analyzer ;;
      *) exit 65 ;;
    esac ;;
  workflow-query)
    if [[ "$first" == pacman-packages ]];then
      # shellcheck source=command.sh
      source "$adapter_library_dir/command.sh"
      # shellcheck source=install-policy.sh
      source "$adapter_library_dir/install-policy.sh"
    fi
    # shellcheck source=workflow-observation.sh
    source "$adapter_library_dir/workflow-observation.sh"
    workflow_native_query "$first" "$second" "$mode" > "$payload_path" ;;
  workflow-stage)
    # Preserve the existing native stage/log boundary and caller stdin.
    # shellcheck source=workflow.sh
    source "$adapter_library_dir/workflow.sh"
    set +e
    (set -e;workflow_execute_stage "$first" "$second" "$mode" "$extra") 2>&1 | tee "$log_path"
    code=$?
    set -e
    printf '%s' "$code" > "$payload_path" ;;
  apply-render)
    # Candidate files belong to caller-owned scratch, never deployment targets.
    # shellcheck source=command.sh
    source "$adapter_library_dir/command.sh"
    command_run probe 0 30 '' -- "$DOTFILES_PYTHON" -X utf8 -B "$adapter_library_dir/../apply/renderers/desktop-fonts.py" "$first" "$second" "$mode" "$extra"
    permissions=644
    [[ ! -f "$second" ]] || permissions="$(stat -c '%a' "$second")"
    chmod "$permissions" "$mode" ;;
  apply-query)
    # shellcheck source=apply-fs.sh
    source "$adapter_library_dir/apply-fs.sh"
    case "$first" in
      entry)
        kind=absent;readable=false;writable=false;searchable=false
        if [[ -L "$second" ]];then kind='link'
        elif [[ -f "$second" ]];then kind='file'
        elif [[ -d "$second" ]];then kind=directory
        elif [[ -e "$second" ]];then kind=other;fi
        [[ ! -r "$second" ]] || readable=true
        [[ ! -w "$second" ]] || writable=true
        [[ ! -x "$second" ]] || searchable=true
        printf '{"kind":"%s","readable":%s,"writable":%s,"searchable":%s}' "$kind" "$readable" "$writable" "$searchable" > "$payload_path" ;;
      state) apply_state "$second" > "$payload_path" ;;
      tree) apply_list "$second" > "$payload_path" ;;
      anchor) apply_nearest_directory "$second" > "$payload_path" ;;
      identity) apply_stat "$second" > "$payload_path" ;;
      resolve-root) apply_resolve_root "$second" > "$payload_path" ;;
      physical-directory) (cd -- "$second" && pwd -P) > "$payload_path" ;;
      directory) if [[ -d "$second" ]];then printf 1;else printf 0;fi > "$payload_path" ;;
      file) if [[ -f "$second" ]];then printf 1;else printf 0;fi > "$payload_path" ;;
      exists) if [[ -e "$second" ]];then printf 1;else printf 0;fi > "$payload_path" ;;
      permissions)
        if [[ "$(uname -s)" == Darwin ]];then stat -f '%Lp' "$second";else stat -c '%a' "$second";fi > "$payload_path" ;;
      go-env) if command -v go >/dev/null 2>&1;then go env GOENV > "$payload_path";fi ;;
      manjaro-branch)
        if command -v pacman-mirrors >/dev/null 2>&1;then
          branch="$(pacman-mirrors --get-branch)"
          printf '/%s' "$branch" > "$payload_path"
        fi ;;
      mirror-sources)
        for target in "$second"/etc/apt/sources.list "$second"/etc/apt/sources.list.d/*.list "$second"/etc/apt/sources.list.d/*.sources "$second"/etc/yum.repos.d/fedora.repo "$second"/etc/yum.repos.d/fedora-updates.repo "$second"/etc/pacman.d/mirrorlist;do
          [[ -f "$target" && -r "$target" && ! -L "$target" ]] || continue
          apply_safe_path "$target"
          printf '%s\n' "${target/#\/\//\/}"
        done > "$payload_path" ;;
      equal-copy) if cmp -s "$second" "$mode";then printf 1;else printf 0;fi > "$payload_path" ;;
      equal-hardlink) if [[ "$second" -ef "$mode" ]];then printf 1;else printf 0;fi > "$payload_path" ;;
      desktop-supported)
        # shellcheck source=desktop-fonts.sh
        source "$adapter_library_dir/desktop-fonts.sh"
        if desktop_fonts_supported;then printf 1;else printf 0;fi > "$payload_path" ;;
      desktop-required)
        # shellcheck source=command.sh
        source "$adapter_library_dir/command.sh"
        command_capture 30 "$DOTFILES_PYTHON" -X utf8 -B "$adapter_library_dir/../apply/renderers/desktop-fonts.py" --families "$second" > "$payload_path" ;;
      desktop-families)
        # shellcheck source=command.sh
        source "$adapter_library_dir/command.sh"
        if command -v fc-list >/dev/null;then command_capture 30 fc-list --format '%{family}\n' > "$payload_path";fi ;;
      *) exit 65 ;;
    esac ;;
  publish-report)
    # shellcheck source=atomic-report.sh
    source "$adapter_library_dir/atomic-report.sh"
    printf '%s' "$second" | atomic_report_write "$first" "$mode" ;;
  discovery-path|install-command|install-state|install-command-probe|install-target-check)
    # shellcheck source=install-items.sh
    source "$adapter_library_dir/install-items.sh"
    # Consumed by the sourced install-policy adapter.
    # shellcheck disable=SC2034
    install_policy_file_override=''
    # shellcheck disable=SC2034
    [[ "$operation" == discovery-path ]] || install_policy_file_override="$extra"
    case "$operation" in
      discovery-path)
        if install_discovery_match_path "$first" "$second" "$mode" "$extra" > "$payload_path";then :
        else code=$?;[[ "$code" == 1 ]] || exit "$code";printf '""' > "$payload_path";fi ;;
      install-state) install_query_state "$first" "$second" > "$payload_path" ;;
      install-command-probe)
        probe="$(install_field "$first" probe_command)"
        if command -v "$probe" >/dev/null 2>&1;then
          install_probe_capture "$(install_field "$first" method)" "$probe" --version >/dev/null
          printf '1' > "$payload_path"
        else printf '0' > "$payload_path";fi ;;
      install-target-check)
        [[ "$(install_field "$first" method)" == docker-ce ]] || exit 2
        install_docker_target "$second" >/dev/null ;;
      install-command)
        # A direct call preserves errexit throughout the handler.
        install_dispatch "$(install_field "$first" method)" "$first" "$second" ;;
    esac ;;
  *) exit 65 ;;
esac
