#!/usr/bin/env bash
# qa.sh — compatibility wrapper. The gate lives in scripts/check.sh now
# (the invariant cases are bats tests under tests/).
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check.sh" "$@"
