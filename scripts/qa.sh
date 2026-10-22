#!/usr/bin/env bash
# qa.sh — hermetic regression checks for pi-sandbox's managed-copy invariants.
#
# Bug class guarded: state drift between the managed copies
#   host ~/.pi/agent  →  pi-home/ overlay  →  container agent dir.
# Deletions must propagate at every layer, junk must never cross a layer, and
# credentials must never reach disk. Runs entirely in a throwaway temp dir —
# it never touches real host or sandbox state.
#
# Usage: scripts/qa.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# Point every layer at the throwaway dir.
export PI_SANDBOX_HOME="$T/config"         # pis config home (overlay lives here)
export PI_AGENT_DIR="$T/host-agent"        # pretend ~/.pi/agent (sync source)
export PI_HOME_SRC="$T/config/pi-home"     # seed source (the overlay)
export PI_CODING_AGENT_DIR="$T/sbx-agent"  # pretend container agent dir
PIS="$ROOT/bin/pis"
SEED="$ROOT/docker/seed-pi-home"
OVER="$PI_SANDBOX_HOME/pi-home"
SBX="$PI_CODING_AGENT_DIR"

mkdir -p "$PI_SANDBOX_HOME" "$PI_AGENT_DIR/extensions" "$PI_AGENT_DIR/npm" "$SBX/extensions"

fails=0
ok()  { printf '  ✓ %s\n' "$1"; }
bad() { printf '  ✗ %s\n' "$1"; fails=$((fails + 1)); }
assert() { local desc=$1; shift; if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi; }

# ---- fixtures: a host agent dir carrying deltas, junk, and symlinks ---------
cat > "$PI_AGENT_DIR/settings.json" <<'EOF'
{ "defaultProvider": "test", "defaultModel": "m", "packages": ["npm:pi-sbx", "npm:other"] }
EOF
cat > "$PI_AGENT_DIR/extensions/good.ts" <<'EOF'
export default () => ({ name: "good" });
EOF
: > "$PI_AGENT_DIR/extensions/empty.ts"
printf 'const x = 1\n' > "$PI_AGENT_DIR/extensions/nobodies.js"
ln -s /nowhere "$PI_AGENT_DIR/extensions/dangling"
echo '{"dependencies":{"pi-sbx":"*","other":"*"}}' > "$PI_AGENT_DIR/npm/package.json"

echo "• mirror: host agent dir → pi-home overlay (pis sync-config)"
out="$("$PIS" sync-config 2>&1)" || true
assert "settings.json: pi-sbx stripped, defaultProjectTrust=always" \
  jq -e '(.packages | index("npm:pi-sbx") | not) and .defaultProjectTrust == "always"' "$OVER/settings.json"
assert "npm/package.json: pi-sbx dependency stripped" \
  jq -e '.dependencies | index("pi-sbx") | not' "$OVER/npm/package.json"
assert "valid extension mirrored" test -f "$OVER/extensions/good.ts"
for j in empty.ts nobodies.js dangling; do
  if [[ ! -e "$OVER/extensions/$j" && ! -L "$OVER/extensions/$j" ]]; then
    ok "junk quarantined at sync: $j"
  else
    bad "junk quarantined at sync: $j"
  fi
done
assert "sync warns about empty.ts" grep -q 'empty.ts' <<<"$out"
assert "sync warns about nobodies.js" grep -q 'nobodies.js' <<<"$out"

echo "• mirror: deletions propagate"
rm "$PI_AGENT_DIR/extensions/good.ts"
"$PIS" sync-config >/dev/null 2>&1 || true
if [[ ! -e "$OVER/extensions/good.ts" ]]; then ok "host removal removes overlay copy"; else bad "host removal removes overlay copy"; fi

echo "• seed: overlay → container agent dir (docker/seed-pi-home)"
cat > "$OVER/extensions/zeta.ts" <<'EOF'
export default () => ({ name: "zeta" });
EOF
: > "$OVER/extensions/straggler.ts"                 # junk via hand-edited overlay
mkdir -p "$SBX/sessions" "$SBX/install"
echo s > "$SBX/sessions/s1"; echo i > "$SBX/install/keep"
echo '{}' > "$SBX/auth.json"                        # pi's benign startup stub
echo '{"k":"v"}' > "$SBX/models-store.json"
echo stale > "$SBX/extensions/stale.ts"             # drift from an older seed
ln -s /nowhere "$SBX/extensions/oldlink"

out="$("$SEED" 2>&1)"
assert "overlay delivered" test -f "$SBX/settings.json"
assert "valid extension delivered" test -f "$SBX/extensions/zeta.ts"
for j in stale.ts oldlink straggler.ts; do
  if [[ ! -e "$SBX/extensions/$j" && ! -L "$SBX/extensions/$j" ]]; then
    ok "stale/junk removed at seed: $j"
  else
    bad "stale/junk removed at seed: $j"
  fi
done
assert "seed warns about straggler.ts" grep -q 'straggler.ts' <<<"$out"
assert "sessions/ preserved" test -f "$SBX/sessions/s1"
assert "install/ preserved" test -f "$SBX/install/keep"
assert "models-store.json preserved" test -f "$SBX/models-store.json"
assert "auth.json never survives a seed" test ! -e "$SBX/auth.json"
assert ".sync-stamp not delivered" test ! -e "$SBX/.sync-stamp"

echo
if [[ $fails -eq 0 ]]; then
  echo "qa: all checks passed"
else
  echo "qa: $fails check(s) FAILED"
  exit 1
fi
