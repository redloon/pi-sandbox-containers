#!/usr/bin/env bash
# check.sh — the test gate for pi-sandbox-local. Run it before declaring any
# change done (see AGENTS.md at the repo root).
#
#   scripts/check.sh             lint + fast hermetic bats suite (no Docker)
#   scripts/check.sh --slow      …plus the Docker tier: pis doctor --smoke and
#                                a compose lifecycle smoke (needs Docker/auth)
#   scripts/check.sh --pinned    force the mise.toml tool versions instead of
#                                the system ones (env form: CHECK_PREFER=mise)
#
# Tool resolution is system-first on purpose: any shellcheck/shfmt/bats on
# PATH wins (zero install friction), the mise.toml pins are only the fallback
# (or the choice with --pinned). Every resolved tool + version is printed so
# version skew is always visible. Exit status 0 means the gate is green.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat <<'EOF'
Usage: scripts/check.sh [--slow] [--pinned]

  (no flags)   shellcheck + shfmt + the fast hermetic bats suite (tests/)
  --slow       also run the Docker tier: pis doctor --smoke + lifecycle smoke
  --pinned     force the mise.toml tool versions instead of system binaries
               (env form: CHECK_PREFER=mise)

Exit status 0 means the gate is green.
EOF
}

die() {
  printf 'check.sh: error: %s\n' "$1" >&2
  if [[ $# -gt 1 ]]; then printf '      hint: %s\n' "$2" >&2; fi
  exit 1
}
note() { printf '\n— %s\n' "$*"; }

SLOW=0
PREFER="${CHECK_PREFER:-system}"
for a in "$@"; do
  case "$a" in
    --slow) SLOW=1 ;;
    --pinned) PREFER=mise ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      printf 'check.sh: unknown option %s\n' "$a" >&2
      usage >&2
      exit 2
      ;;
  esac
done
if [[ "$PREFER" != system && "$PREFER" != mise ]]; then
  die "CHECK_PREFER must be 'system' or 'mise'"
fi

# ------------------------------------------------------------ tool wiring --
declare -A TOOL_PATH=()
tool() {
  local name=$1
  shift
  "${TOOL_PATH[$name]}" "$@"
}

tool_version() {
  local name=$1
  case "$name" in
    shellcheck) "$2" --version | sed -n 's/^version: //p' ;;
    *) "$2" --version 2>&1 | head -1 ;;
  esac
}

need() {
  local t=$1 path where
  if [[ "$PREFER" == system ]] && command -v "$t" >/dev/null 2>&1; then
    path="$(command -v "$t")"
    where="system: $path"
  elif command -v mise >/dev/null 2>&1; then
    path="$(mise exec -- bash -c "command -v $t" 2>/dev/null || true)"
    if [[ -z "$path" ]]; then
      die "$t not found on PATH and mise could not provide it" \
        "install $t, or run: mise install (pins live in mise.toml)"
    fi
    where="mise pinned (mise.toml)"
  else
    die "$t is not on PATH and mise is not installed" \
      "install $t, or install mise and run: mise install"
  fi
  TOOL_PATH[$t]="$path"
  printf '  %-11s %-12s (%s)\n' "$t" "$(tool_version "$t" "$path")" "$where"
}

# ------------------------------------------------------------- file sets --
SHELL_FILES=(bin/pis install docker/entrypoint.sh docker/seed-pi-home scripts/check.sh scripts/qa.sh)
BATS_FILES=()
for f in tests/*.bash; do [[ -e "$f" ]] && SHELL_FILES+=("$f"); done
for f in tests/*.bats; do [[ -e "$f" ]] && BATS_FILES+=("$f"); done
[[ ${#BATS_FILES[@]} -gt 0 ]] || die "no tests/*.bats files found"

note "tools (system first, mise.toml pins as fallback)"
need shellcheck
need shfmt
need bats
for t in jq rsync; do
  command -v "$t" >/dev/null 2>&1 ||
    die "$t is required by the test suite" "install $t"
done

note "shellcheck (${#SHELL_FILES[@]} shell + ${#BATS_FILES[@]} bats helpers)"
tool shellcheck "${SHELL_FILES[@]}"

note "shfmt -d (indent 2, case indent)"
tool shfmt -i 2 -ci -d "${SHELL_FILES[@]}"
tool shfmt -ln bats -i 2 -ci -d "${BATS_FILES[@]}"

note "bats (${#BATS_FILES[@]} files, hermetic — no Docker)"
tool bats --print-output-on-failure "${BATS_FILES[@]}"

if [[ $SLOW == 1 ]]; then
  note "slow tier: docker"
  command -v docker >/dev/null 2>&1 ||
    die "docker is required for --slow" "run without --slow on machines without Docker"
  docker info >/dev/null 2>&1 ||
    die "the Docker daemon is not reachable (needed for --slow)" "start it and retry"
  note "slow tier: pis doctor --smoke (runs pi inside the sandbox)"
  "$ROOT/bin/pis" doctor --smoke
  note "slow tier: compose lifecycle smoke"
  "$ROOT/bin/pis" run -- true
  "$ROOT/bin/pis" down
  note "slow tier: green"
fi

printf '\ncheck: all green\n'
