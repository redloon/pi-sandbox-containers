#!/usr/bin/env bats
# seed-pi-home — pi-home/ overlay → container agent dir (docker/seed-pi-home).
#
# The seed delivers the overlay, drops stale/junk files (deletions propagate),
# preserves per-sandbox runtime state, and is the last gate before pi: no
# credential may ever be on disk in a sandbox.

load test_helper

setup() {
  make_tree
  # Overlay (seed source): one valid extension plus hand-edited junk.
  mkdir -p "$PI_HOME_SRC/extensions"
  echo '{ "defaultProvider": "test" }' >"$PI_HOME_SRC/settings.json"
  cat >"$PI_HOME_SRC/extensions/zeta.ts" <<'EOF'
export default () => ({ name: "zeta" });
EOF
  : >"$PI_HOME_SRC/extensions/straggler.ts"
  echo stamp >"$PI_HOME_SRC/.sync-stamp"
  # Sandbox agent dir: state that must survive — and drift that must not.
  mkdir -p "$PI_CODING_AGENT_DIR/sessions" "$PI_CODING_AGENT_DIR/install"
  echo s >"$PI_CODING_AGENT_DIR/sessions/s1"
  echo i >"$PI_CODING_AGENT_DIR/install/keep"
  echo '{}' >"$PI_CODING_AGENT_DIR/auth.json" # pi's benign startup stub
  echo '{"k":"v"}' >"$PI_CODING_AGENT_DIR/models-store.json"
  echo stale >"$PI_CODING_AGENT_DIR/extensions/stale.ts" # drift from an older seed
  ln -s /nowhere "$PI_CODING_AGENT_DIR/extensions/oldlink"
}

teardown() {
  drop_tree
}

@test "overlay is delivered to the sandbox agent dir" {
  run "$SEED"
  [ "$status" -eq 0 ]
  test -f "$PI_CODING_AGENT_DIR/settings.json"
}

@test "valid overlay extensions are delivered" {
  run "$SEED"
  [ "$status" -eq 0 ]
  test -f "$PI_CODING_AGENT_DIR/extensions/zeta.ts"
}

@test "hand-edited junk in the overlay is not delivered" {
  run "$SEED"
  [ "$status" -eq 0 ]
  [ ! -e "$PI_CODING_AGENT_DIR/extensions/straggler.ts" ]
  [ ! -L "$PI_CODING_AGENT_DIR/extensions/straggler.ts" ]
}

@test "stale extension copies are removed at seed" {
  run "$SEED"
  [ "$status" -eq 0 ]
  [ ! -e "$PI_CODING_AGENT_DIR/extensions/stale.ts" ]
}

@test "stale symlink copies are removed at seed" {
  run "$SEED"
  [ "$status" -eq 0 ]
  [ ! -e "$PI_CODING_AGENT_DIR/extensions/oldlink" ]
  [ ! -L "$PI_CODING_AGENT_DIR/extensions/oldlink" ]
}

@test "seed warns loudly about un-loadable overlay extensions" {
  run "$SEED"
  [ "$status" -eq 0 ]
  [[ "$output" == *"straggler.ts"* ]]
}

@test "sessions/ survive seeding" {
  run "$SEED"
  [ "$status" -eq 0 ]
  test -f "$PI_CODING_AGENT_DIR/sessions/s1"
}

@test "install/ survives seeding" {
  run "$SEED"
  [ "$status" -eq 0 ]
  test -f "$PI_CODING_AGENT_DIR/install/keep"
}

@test "models-store.json survives seeding" {
  run "$SEED"
  [ "$status" -eq 0 ]
  test -f "$PI_CODING_AGENT_DIR/models-store.json"
}

@test "auth.json never survives a seed (pi's empty stub is removed)" {
  run "$SEED"
  [ "$status" -eq 0 ]
  [ ! -e "$PI_CODING_AGENT_DIR/auth.json" ]
}

@test "populated auth.json is removed loudly" {
  echo '{"key":"a-real-credential"}' >"$PI_CODING_AGENT_DIR/auth.json"
  run "$SEED"
  [ "$status" -eq 0 ]
  [ ! -e "$PI_CODING_AGENT_DIR/auth.json" ]
  [[ "$output" == *"auth.json contained credentials and was removed"* ]]
}

@test ".sync-stamp is not delivered" {
  run "$SEED"
  [ "$status" -eq 0 ]
  [ ! -e "$PI_CODING_AGENT_DIR/.sync-stamp" ]
}
