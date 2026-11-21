# shellcheck shell=bash
install_probe() {
  local method="$1" record="$2" context="$3" package output code
  if [[ -n "$(install_field "$record" discovery)" ]];then install_discover "$record" "$context";return;fi
  case "$method" in
    font-download)
      local target file files=()
      target="$HOME/.local/share/fonts/$(install_field "$record" id)"
      read -r -a files <<< "$(install_field "$record" font_files)"
      [[ -d "$target" && ! -L "$target" ]] || return 0
      for file in "${files[@]}"; do
        [[ -f "$target/$file" && ! -L "$target/$file" ]] || return 0
      done
      printf 'present\n' ;;
    pipx)
      package="$(install_field "$record" packages)"
      if command -v pipx >/dev/null 2>&1; then
        output="$(install_probe_capture "$method" pipx list --short)" || return
        if printf '%s\n' "$output" | awk -v name="$package" '$1==name {found=1} END {exit !found}'; then printf 'present\n'; fi
      fi ;;
    xcode)
      if install_probe_capture "$method" xcode-select -p >/dev/null 2>&1; then printf 'present\n'
      else code=$?;case "$code" in 1|127) ;; *) return "$code" ;; esac;fi ;;
    homebrew) if command -v "$(install_context "$context" 3)" >/dev/null 2>&1; then printf 'present\n'; fi ;;
    apt-or-snap) install_probe_apt_or_snap "$record" "$context" ;;
    rustup) install_probe_rustup "$record" "$context" ;;
  esac
}

install_resume_package_state() {
  local record="$1" context="$2" method package output code command packages=()
  method="$(install_field "$record" method)"
  if [[ "$method" == docker-ce ]];then method="${context%%|*}";method="${method#linux.}";fi
  read -r -a packages <<< "$(install_field "$record" packages)"
  for package in "${packages[@]}";do
    code=0;output=''
    case "$method" in
      apt|apt-repository)
        command=dpkg-query
        command -v "$command" >/dev/null 2>&1 || return 0
        # dpkg-query expands this format variable, not the shell.
        # shellcheck disable=SC2016
        output="$(install_probe_capture "$method" "$command" -W '-f=${Status}' "$package")" || code=$?
        if (( code == 0 )) && [[ "$output" != 'install ok installed' ]];then return 0;fi ;;
      dnf|dnf-copr)
        command -v rpm >/dev/null 2>&1 || return 0
        output="$(install_probe_capture "$method" rpm -q "$package")" || code=$? ;;
      pacman)
        command -v pacman >/dev/null 2>&1 || return 0
        output="$(install_probe_capture "$method" pacman -Q "$package")" || code=$? ;;
      brew|cask)
        command="$(install_context "$context" 3)"
        command -v "$command" >/dev/null 2>&1 || return 0
        if [[ "$method" == brew ]];then
          output="$(install_probe_capture "$method" "$command" list --formula --versions "$package")" || code=$?
        else output="$(install_probe_capture "$method" "$command" list --cask --versions "$package")" || code=$?;fi
        [[ "$code" != 0 || -n "$output" ]] || return 0 ;;
      cargo)
        command -v cargo >/dev/null 2>&1 || return 0
        output="$(install_probe_capture "$method" cargo install --list)" || return
        printf '%s\n' "$output" | awk -v name="$package" '$1==name && $2~/^v/ {found=1} END {exit !found}' || return 0 ;;
      *) return 0 ;;
    esac
    case "$code" in 0) ;; 1) return 0 ;; *) return "$code" ;; esac
  done
  [[ ${#packages[@]} -gt 0 ]] && printf 'present\n'
  return 0
}

install_query_state() {
  local record="$1" context="$2" method
  method="$(install_field "$record" method)"
  case "$method" in
    docker-ce|apt|apt-repository|dnf|dnf-copr|pacman|brew|cask|cargo) install_resume_package_state "$record" "$context" ;;
    *) install_probe "$method" "$record" "$context" ;;
  esac
}

install_evaluate_record() {
  dotfiles_request install-observe-native style unix native_shell "$BASH" item "$1" native_context "$2" mode "$3" policy_path "${install_policy_file_override:-$install_policy_library_dir/../install/schema/execution.tsv}"
}

# Query only installed toolchains/components; never invoke rustc (which may download).
install_probe_rustup() {
  local record="$1" context="$2" command=rustup platform prefix toolchain output line resolved='' component components
  platform="$(install_context "$context" 1)"
  case "$platform" in
    linux.apt) command=/usr/bin/rustup ;;
    macos) prefix="$(install_context "$context" 4)";command="$prefix/opt/rustup/bin/rustup" ;;
    linux.dnf) command="$HOME/.cargo/bin/rustup" ;;
  esac
  command -v "$command" >/dev/null 2>&1 || return 0
  toolchain="$(install_field "$record" packages)"
  output="$(install_probe_capture rustup "$command" toolchain list)" || return
  while IFS= read -r line;do
    line="${line%% *}"
    if [[ "$line" == "$toolchain" || "$line" == "$toolchain"-* ]];then resolved="$line";break;fi
  done <<< "$output"
  [[ -n "$resolved" ]] || return 0
  output="$(install_probe_capture rustup "$command" component list --installed --toolchain "$resolved")" || return
  components="$(install_field "$record" components)";components="${components//,/ }"
  for component in $components;do
    printf '%s\n' "$output" | awk -v name="$component" '$1==name || index($1,name "-")==1 {found=1} END {exit !found}' || return 0
  done
  printf 'present\n'
}
