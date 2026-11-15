# shellcheck shell=bash
install_items_read() {
  local directory="$1" platform="$2" file
  local install_schema_dir="${install_library_dir:?}/../install/schema"
  install_execution_policy '*' install >/dev/null || return
  for file in "$directory"/*.conf; do
    [[ -s "$file" ]] || { printf 'error: missing or empty item configuration: %s\n' "$file" >&2; return 1; }
  done
  LC_ALL=C awk -v platform="$platform" -f "$install_library_dir/install-compat.awk" -f "$install_library_dir/install-normalize.awk" -f "$install_library_dir/install-plan.awk" \
    "$install_schema_dir/fields.tsv" "$install_schema_dir/methods.tsv" "$install_schema_dir/sources.tsv" "$install_schema_dir/runtime-providers.tsv" "$install_schema_dir/capabilities.tsv" "$install_schema_dir/discovery-roots.tsv" "$install_library_dir/../contracts/schema/install-plan.fields" "$directory"/*.conf
}

