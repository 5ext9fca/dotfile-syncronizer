# shellcheck shell=bash
command_library_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=data-contract.sh
source "$command_library_dir/data-contract.sh"
# shellcheck source=atomic-report.sh
source "$command_library_dir/atomic-report.sh"
command_stop_group() {
  local pid="$1"
  [[ -n "$pid" ]] || return 0
  kill -TERM -- "-$pid" 2>/dev/null || :
  sleep 0.1
  kill -KILL -- "-$pid" 2>/dev/null || :
}
command_cleanup() {
  local child="$1" timer="$2" scratch="$3"
  if [[ ! -f "$scratch/success" && ! -f "$scratch/child-stopped" ]];then command_stop_group "$child";fi
  if [[ ! -f "$scratch/timer-stopped" ]];then command_stop_group "$timer";fi
  rm -rf -- "$scratch"
}
command_worker() {
  local scratch="$1"
  shift
  trap - INT TERM
  # Do not expose the child command until its controller has cancellation traps.
  while [[ ! -f "$scratch/ready" ]];do sleep 0.01;done
  "$@"
}
# policy: mutation/probe; dry: 0/1; timeout seconds (0 means no deadline).
# Empty capture directory preserves terminal streams; otherwise capture both.
command_run() (
  local policy="$1" dry="$2" timeout="$3" capture="$4" child timer='' scratch code=0 cancelled=0 started=$SECONDS status
  shift 4
  [[ "${1:-}" == -- ]] || return 2;shift
  [[ "$policy" == mutation || "$policy" == probe ]] || return 2
  [[ "$dry" =~ ^[01]$ && "$timeout" =~ ^[0-9]+$ && ${#timeout} -le 5 && $# -gt 0 ]] || return 2
  [[ "$timeout" == 0 || "$timeout" != 0* ]] || return 2
  (( timeout <= 86400 )) || return 2
  if [[ -n "$capture" ]];then
    [[ -d "$capture" && ! -L "$capture" && ! -L "$capture/stdout" && ! -L "$capture/stderr" ]] || return 2
    : > "$capture/stdout";: > "$capture/stderr"
  fi
  if [[ "$dry" == 1 ]];then
    printf 'DRY RUN:';printf ' %q' "$@";printf '\n'
    if [[ -n "$capture" ]];then contract_save command-result "$policy|planned|0|0|$capture/stdout|$capture/stderr" "$capture/command.result";fi
    return 0
  fi
  scratch="$(mktemp -d)" || return
  # Job control creates an isolated group on both Linux and macOS. Foreground
  # terminal commands are brought forward so sudo/interactive installers work.
  set -m
  if [[ -n "$capture" ]];then
    (command_worker "$scratch" "$@") < /dev/null > "$capture/stdout" 2> "$capture/stderr" &
  else
    (command_worker "$scratch" "$@") <&0 &
  fi
  child=$!
  if (( timeout ));then
    (sleep "$timeout";: > "$scratch/timed-out";command_stop_group "$child") &
    timer=$!
  fi
  # Freeze cleanup arguments because errexit may unwind local variable scopes.
  # shellcheck disable=SC2064
  trap "$(printf 'command_cleanup %q %q %q' "$child" "$timer" "$scratch")" EXIT
  trap 'cancelled=130;command_stop_group "$child"' INT
  trap 'cancelled=143;command_stop_group "$child"' TERM
  : > "$scratch/ready"
  if [[ -z "$capture" && -t 0 ]];then
    # Bash uses stderr for terminal foreground handoff. Stage logging may pipe
    # stderr through tee; redirect only fg, preserving the child output streams.
    if fg %1 >/dev/null 2>/dev/tty;then code=0;else code=$?;fi
  else
    set +m
    if wait "$child";then code=0;else code=$?;fi
  fi
  if [[ -f "$scratch/timed-out" ]];then code=124
  elif (( cancelled ));then code=$cancelled;fi
  # Complete descendant cleanup before returning to the deployment lease owner.
  # The watchdog may still be between TERM and KILL when wait returns.
  if (( code != 0 ));then command_stop_group "$child";wait "$child" 2>/dev/null || :;: > "$scratch/child-stopped";fi
  command_stop_group "$timer"
  if [[ -n "$timer" ]];then wait "$timer" 2>/dev/null || :;fi
  : > "$scratch/timer-stopped"
  if (( code == 0 ));then : > "$scratch/success";status=success
  elif (( code == 124 ));then status=timed-out
  elif (( code == 130 || code == 143 ));then status=interrupted
  else status=failed;fi
  if [[ -n "$capture" ]];then contract_save command-result "$policy|$status|$code|$((SECONDS-started))|$capture/stdout|$capture/stderr" "$capture/command.result";fi
  return "$code"
)
command_capture() (
  local timeout="$1" scratch code
  shift
  scratch="$(mktemp -d)" || return
  # shellcheck disable=SC2064
  trap "$(printf 'rm -rf -- %q' "$scratch")" EXIT
  if command_run probe 0 "$timeout" "$scratch" -- "$@";then code=0;else code=$?;fi
  cat "$scratch/stdout"
  return "$code"
)
