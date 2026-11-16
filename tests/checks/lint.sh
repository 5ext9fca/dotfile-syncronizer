#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/../.." && pwd -P)"
cd "$repo_root"
files=()
while IFS= read -r -d '' file; do files+=("$file"); done < <(find lib install apply mirrors workflow snapshot tests -name '*.sh' -type f -print0)
# Check every file independently. Recursive source analysis of test overrides
# grows without bound in ShellCheck 0.9; integration contracts cover those edges.
failed=0
for file in "${files[@]}"; do
  if ! "${DOTFILES_TEST_SHELLCHECK:-shellcheck}" -e SC1091 -P SCRIPTDIR "$file"; then failed=1; fi
done
exit "$failed"
