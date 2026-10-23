#!/usr/bin/env bats
# provider auth — the .env passthrough contract and the generic guard: any
# provider's credential vars work (no hardcoded names), host-env creds are
# forwarded per exec without ever entering argv, and keyless providers have an
# explicit escape hatch. Display shows names and sources only — never values.
#
# Hermetic: docker is a test double (tests/test_helper.bash) and host pi is a
# tripwire. Nothing here needs a real container.

load test_helper

setup() {
  make_tree
  make_shims
  cd "$TEST_TMP/repo"
}

teardown() {
  cd /
  drop_tree
}

# ------------------------------------------------------------- guard ------

@test "auth guard: a generic var in .env satisfies the guard" {
  echo 'ANTHROPIC_API_KEY=from-dotenv' >"$PI_SANDBOX_HOME/.env"
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS"
  [ "$status" -eq 0 ]
  grep -q "compose up -d general" "$FAKE_DOCKER_LOG"
}

@test "auth guard: an empty generic var in .env does not count" {
  echo 'ANTHROPIC_API_KEY=' >"$PI_SANDBOX_HOME/.env"
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no provider credentials configured"* ]]
}

@test "auth guard: a host-env *_API_KEY var satisfies the guard" {
  run env OPENROUTER_API_KEY=tok PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS"
  [ "$status" -eq 0 ]
  grep -q "compose up -d general" "$FAKE_DOCKER_LOG"
}

@test "auth guard: a PI_SANDBOX_EXTRA_ENV host name satisfies the guard" {
  run env PI_SANDBOX_EXTRA_ENV=MY_CRED MY_CRED=x PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS"
  [ "$status" -eq 0 ]
  grep -q "compose up -d general" "$FAKE_DOCKER_LOG"
}

@test "auth guard: PI_SANDBOX_ALLOW_NO_AUTH=1 bypasses for keyless providers" {
  run env PI_SANDBOX_ALLOW_NO_AUTH=1 PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS"
  [ "$status" -eq 0 ]
  grep -q "compose up -d general" "$FAKE_DOCKER_LOG"
}

@test "auth guard: the error is provider-neutral and carries a fix hint" {
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no provider credentials configured"* ]]
  [[ "$output" == *"hint:"* ]]
  [[ "$output" == *".env"* ]]
  ! grep -qi "xiaomi\|mimo" <<<"$output"
  ! grep -q "compose up" "$FAKE_DOCKER_LOG"
  [ ! -e "$PI_TRIPWIRE" ]
}

# -------------------------------------------------------- passthrough -----

@test "passthrough: host *_API_KEY vars reach compose exec -e, values never in argv" {
  run env ANTHROPIC_API_KEY=supersecret1 PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" run -- true
  [ "$status" -eq 0 ]
  grep -q -- "-e ANTHROPIC_API_KEY" "$FAKE_DOCKER_LOG"
  ! grep -q "supersecret1" "$FAKE_DOCKER_LOG"
}

@test "passthrough: PI_SANDBOX_EXTRA_ENV names are forwarded, other host vars are not" {
  run env PI_SANDBOX_EXTRA_ENV=GITHUB_TOKEN GITHUB_TOKEN=gh-secret OTHER_TOKEN=nope \
    ANTHROPIC_API_KEY=k PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" run -- true
  [ "$status" -eq 0 ]
  grep -q -- "-e GITHUB_TOKEN" "$FAKE_DOCKER_LOG"
  grep -q -- "-e ANTHROPIC_API_KEY" "$FAKE_DOCKER_LOG"
  ! grep -q "OTHER_TOKEN" "$FAKE_DOCKER_LOG"
  ! grep -q "gh-secret" "$FAKE_DOCKER_LOG"
}

@test "passthrough: .env vars flow via env_file at container create, not per-exec -e" {
  echo 'ANTHROPIC_API_KEY=from-dotenv' >"$PI_SANDBOX_HOME/.env"
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" run -- true
  [ "$status" -eq 0 ]
  grep -q "compose up -d general" "$FAKE_DOCKER_LOG"
  ! grep -q -- "-e ANTHROPIC_API_KEY" "$FAKE_DOCKER_LOG"
  ! grep -q "from-dotenv" "$FAKE_DOCKER_LOG"
}

@test "passthrough: compose.yaml injects every .env var generically (no hardcoded names)" {
  run grep -A2 'env_file' "$REPO_ROOT/compose.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"required: false"* ]]
  run grep 'XIAOMI\|ANTHROPIC\|OPENROUTER' "$REPO_ROOT/compose.yaml"
  [ "$status" -ne 0 ]
}

# ------------------------------------------------------------ display -----

@test "display: status and doctor show credential names and sources, never values" {
  echo 'ANTHROPIC_API_KEY=supersecretvalue' >"$PI_SANDBOX_HOME/.env"
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"ANTHROPIC_API_KEY"* ]]
  [[ "$output" == *".env"* ]]
  ! grep -q "supersecretvalue" <<<"$output"
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"ANTHROPIC_API_KEY"* ]]
  ! grep -q "supersecretvalue" <<<"$output"
}

@test "display: status names both sources separately" {
  echo 'ANTHROPIC_API_KEY=a' >"$PI_SANDBOX_HOME/.env"
  run env OPENROUTER_API_KEY=b PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" status
  [ "$status" -eq 0 ]
  [[ "$output" == *".env: ANTHROPIC_API_KEY"* ]]
  [[ "$output" == *"host env: OPENROUTER_API_KEY"* ]]
}

@test "display: status reports the keyless bypass and the missing state" {
  run env PI_SANDBOX_ALLOW_NO_AUTH=1 PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"PI_SANDBOX_ALLOW_NO_AUTH=1"* ]]
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"auth:      MISSING"* ]]
}
