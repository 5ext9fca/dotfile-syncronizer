#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
test_tmp="$(mktemp -d)"
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/tests/checks"
cp "$repo_root/tests/check.sh" "$test_tmp/tests/check.sh"
printf '#!/usr/bin/env bash\nexit 19\n' > "$test_tmp/tests/fail.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$test_tmp/tests/pass.sh"
printf 'first\tcore\tlinux macos windows\tbash\ttests/fail.sh\t-\nsecond\tcore\tlinux macos windows\tbash\ttests/pass.sh\t-\nforeign\tcore\tother\tbash\tnot-present\t-\n' > "$test_tmp/tests/checks/manifest.tsv"
if "$BASH" "$test_tmp/tests/check.sh" --strict > "$test_tmp/result" 2>&1; then printf 'Runner swallowed check failure\n' >&2; exit 1; fi
grep -q 'FAIL first: exit 19' "$test_tmp/result"
grep -q 'PASS second' "$test_tmp/result"
grep -q 'passed=1 failed=1 skipped=1' "$test_tmp/result"
DOTFILES_TEST_BASH="$test_tmp/missing-bash" "$BASH" "$test_tmp/tests/check.sh" > "$test_tmp/skips"
grep -q 'passed=0 failed=0 skipped=3' "$test_tmp/skips"
if DOTFILES_TEST_BASH="$test_tmp/missing-bash" "$BASH" "$test_tmp/tests/check.sh" --strict > "$test_tmp/strict"; then exit 1; fi
grep -q 'passed=0 failed=2 skipped=1' "$test_tmp/strict"
printf 'Unified check runner failure, continuation and missing-runtime tests passed.\n'
