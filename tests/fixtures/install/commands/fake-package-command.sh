#!/usr/bin/env bash
set -euo pipefail
state="${DOTFILES_TEST_PACKAGE_STATE:?}"
tool="${0##*/}"
fixture_report() {
  if [[ -f "$state/report-source" ]];then cat "$state/report-source";else printf '%s' "$state/results";fi
}
fixture_snapshot() {
  [[ ! -f "$state/$1-snapshot" ]] || cp "$(fixture_report)" "$(cat "$state/$1-snapshot")"
}
{ printf '%s' "$tool";printf ' <%s>' "$@";printf '\n'; } >> "$state/commands"
if [[ "$tool" == winget.exe ]];then
  operation="$1";shift
  package=''
  while (( $# ));do
    if [[ "$1" == --id ]];then package="$2";shift;fi
    shift
  done
  [[ -n "$package" ]] || exit 91
  if [[ "$operation" == list ]];then
    fixture_snapshot probe
    if [[ -f "$state/probe-exit" ]];then exit "$(cat "$state/probe-exit")";fi
    if [[ -f "$state/installed-$package" ]];then printf '%s 1.0\n' "$package";fi
    exit 0
  fi
  [[ "$operation" == install ]] || exit 91
  printf '%s\n' "$package" >> "$state/installs"
  fixture_snapshot install
  report_id="$package";[[ ! -f "$state/report-id" ]] || report_id="$(cat "$state/report-id")"
  grep -q "^$report_id|running|" "$(fixture_report)" || exit 92
  if [[ -f "$state/corrupt-stage" ]];then printf '# dotfiles|stage-result|99\nkey|value\n' > "$(cat "$state/corrupt-stage")";fi
  [[ ! -f "$state/install-exit" ]] || exit "$(cat "$state/install-exit")"
  [[ ! -f "$state/fail-$package" ]] || exit 23
  [[ -f "$state/skip-evidence" ]] || touch "$state/installed-$package"
  exit 0
fi
if [[ "$tool" == sudo ]];then exec "$@";fi
if [[ "$tool" == apt-get ]];then
  [[ "$1 $2" == 'install -y' ]] || exit 91
  shift 2
  for package in "$@";do
    printf '%s\n' "$package" >> "$state/installs"
    fixture_snapshot install
    report_id="$package";[[ ! -f "$state/report-id" ]] || report_id="$(cat "$state/report-id")"
    grep -q "^$report_id|running|" "$(fixture_report)"
    [[ ! -f "$state/install-exit" ]] || exit "$(cat "$state/install-exit")"
    if [[ -f "$state/fail-$package" ]];then exit 23;fi
    [[ -f "$state/skip-evidence" ]] || touch "$state/installed-$package"
  done
  exit 0
fi
fixture_snapshot probe
if [[ -f "$state/probe-delay" ]];then sleep 5;fi
if [[ -f "$state/probe-exit" ]];then exit "$(cat "$state/probe-exit")";fi
case "$tool" in
  vswhere.exe) exit 0 ;;
  apt-cache)
    [[ "$1" == policy ]] || exit 91
    if [[ -f "$state/installed-$2" ]];then printf 'Candidate: 1.0\n';else printf 'Candidate: (none)\n';fi ;;
  dpkg-query)
    # dpkg-query receives this format literally.
    # shellcheck disable=SC2016
    [[ "$1" == -W && "$2" == '-f=${Status}' ]] || exit 91
    [[ -f "$state/installed-$3" ]] || exit 1
    printf 'install ok installed' ;;
  rpm|pacman)
    [[ "$1" == -q || "$1" == -Q ]] || exit 91
    [[ -f "$state/installed-$2" ]] || exit 1
    printf '%s 1.0\n' "$2" ;;
  brew)
    [[ "$1" == list && ( "$2" == --formula || "$2" == --cask ) && "$3" == --versions ]] || exit 91
    [[ -f "$state/installed-$4" ]] || exit 1
    printf '%s 1.0\n' "$4" ;;
  cargo|pipx)
    if [[ "$tool" == cargo ]];then [[ "$*" == 'install --list' ]] || exit 91
    else [[ "$*" == 'list --short' ]] || exit 91;fi
    for marker in "$state"/installed-*;do
      [[ -f "$marker" ]] || continue
      package="${marker##*/installed-}"
      if [[ "$tool" == cargo ]];then printf '%s v1.0.0:\n    %s\n' "$package" "$package"
      else printf '%s 1.0\n' "$package";fi
    done ;;
  *) exit 91 ;;
esac
