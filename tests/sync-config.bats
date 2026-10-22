#!/usr/bin/env bats
# sync-config — host agent dir → pi-home/ overlay (bin/pis sync-config).
#
# The mirror applies the documented sandbox deltas (npm:pi-sbx stripped,
# defaultProjectTrust: "always"), quarantines junk pi cannot load, propagates
# deletions, and must never let a credential onto disk.

load test_helper

setup() {
  make_tree
  # Host agent dir carrying deltas, junk, and symlinks.
  cat >"$PI_AGENT_DIR/settings.json" <<'EOF'
{ "defaultProvider": "test", "defaultModel": "m", "packages": ["npm:pi-sbx", "npm:other"] }
EOF
  cat >"$PI_AGENT_DIR/extensions/good.ts" <<'EOF'
export default () => ({ name: "good" });
EOF
  : >"$PI_AGENT_DIR/extensions/empty.ts"
  printf 'const x = 1\n' >"$PI_AGENT_DIR/extensions/nobodies.js"
  ln -s /nowhere "$PI_AGENT_DIR/extensions/dangling"
  echo '{"dependencies":{"pi-sbx":"*","other":"*"}}' >"$PI_AGENT_DIR/npm/package.json"
}

teardown() {
  drop_tree
}

@test "settings.json: npm:pi-sbx stripped and defaultProjectTrust: always" {
  run "$PIS" sync-config
  [ "$status" -eq 0 ]
  jq -e '(.packages | index("npm:pi-sbx") | not) and .defaultProjectTrust == "always"' \
    "$PI_SANDBOX_HOME/pi-home/settings.json"
}

@test "npm/package.json: pi-sbx dependency stripped" {
  run "$PIS" sync-config
  [ "$status" -eq 0 ]
  jq -e '.dependencies | index("pi-sbx") | not' "$PI_SANDBOX_HOME/pi-home/npm/package.json"
}

@test "valid extensions mirror to the overlay" {
  run "$PIS" sync-config
  [ "$status" -eq 0 ]
  test -f "$PI_SANDBOX_HOME/pi-home/extensions/good.ts"
}

@test "empty extension is quarantined at sync" {
  run "$PIS" sync-config
  [ "$status" -eq 0 ]
  [ ! -e "$PI_SANDBOX_HOME/pi-home/extensions/empty.ts" ]
  [ ! -L "$PI_SANDBOX_HOME/pi-home/extensions/empty.ts" ]
}

@test "export-less extension is quarantined at sync" {
  run "$PIS" sync-config
  [ "$status" -eq 0 ]
  [ ! -e "$PI_SANDBOX_HOME/pi-home/extensions/nobodies.js" ]
  [ ! -L "$PI_SANDBOX_HOME/pi-home/extensions/nobodies.js" ]
}

@test "dangling symlink is quarantined at sync" {
  run "$PIS" sync-config
  [ "$status" -eq 0 ]
  [ ! -e "$PI_SANDBOX_HOME/pi-home/extensions/dangling" ]
  [ ! -L "$PI_SANDBOX_HOME/pi-home/extensions/dangling" ]
}

@test "sync warns loudly about the empty extension" {
  run "$PIS" sync-config
  [ "$status" -eq 0 ]
  [[ "$output" == *"empty.ts"* ]]
}

@test "sync warns loudly about the export-less extension" {
  run "$PIS" sync-config
  [ "$status" -eq 0 ]
  [[ "$output" == *"nobodies.js"* ]]
}

@test "host removal propagates: overlay copy is deleted" {
  run "$PIS" sync-config
  [ "$status" -eq 0 ]
  rm "$PI_AGENT_DIR/extensions/good.ts"
  run "$PIS" sync-config
  [ "$status" -eq 0 ]
  [ ! -e "$PI_SANDBOX_HOME/pi-home/extensions/good.ts" ]
}

@test "credential guard: overlay auth.json aborts the sync" {
  mkdir -p "$PI_SANDBOX_HOME/pi-home"
  echo '{}' >"$PI_SANDBOX_HOME/pi-home/auth.json"
  run "$PIS" sync-config
  [ "$status" -eq 1 ]
  [[ "$output" == *"auth.json must never exist"* ]]
}
