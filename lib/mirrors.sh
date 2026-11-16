# shellcheck shell=bash
# Host package-manager observation for standalone mirror entry points.
china_mirror_detect_package_manager() {
  if command -v pacman >/dev/null 2>&1;then printf 'pacman\n'
  elif command -v apt-get >/dev/null 2>&1;then printf 'apt\n'
  elif command -v dnf >/dev/null 2>&1;then printf 'dnf\n';fi
}
