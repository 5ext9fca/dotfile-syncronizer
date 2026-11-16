# shellcheck shell=bash
desktop_fonts_supported() {
  [[ "$(uname -s)" == Linux && -z "${WSL_INTEROP:-}${WSL_DISTRO_NAME:-}" ]] || return 1
  ! grep -qi microsoft /proc/sys/kernel/osrelease || return 1
  case ":${XDG_CURRENT_DESKTOP:-}:" in *:KDE:*) return 0 ;; *) return 1 ;; esac
}
