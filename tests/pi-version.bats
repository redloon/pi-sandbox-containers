#!/usr/bin/env bats
# pi version policy — the sandbox pi is pinned (PI_VERSION, baked into the
# images) while the host pi updates independently; drift must be visible and
# fixable with one command (`pis use-pi`).
#
# Hermetic: docker is a test double, host pi is the shim's --version probe.

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

@test "use-pi: pins an explicit version and rebuilds every image" {
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" use-pi 3.2.1
  [ "$status" -eq 0 ]
  grep -q '^PI_VERSION=3.2.1$' "$PI_SANDBOX_CONFIG"
  grep -q "compose build general" "$FAKE_DOCKER_LOG"
  grep -q "compose build web" "$FAKE_DOCKER_LOG"
  grep -q "compose build android" "$FAKE_DOCKER_LOG"
  [ ! -e "$PI_TRIPWIRE" ]
}

@test "use-pi: bare invocation adopts the host pi version" {
  run env FAKE_HOST_PI_VERSION=9.9.9 PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" use-pi
  [ "$status" -eq 0 ]
  grep -q '^PI_VERSION=9.9.9$' "$PI_SANDBOX_CONFIG"
  [[ "$output" == *"sandbox pi pinned to 9.9.9"* ]]
}

@test "use-pi: re-pinning replaces the line and preserves other config" {
  printf 'PI_SANDBOX_HOME=/somewhere\nPI_VERSION=1.0.0\n' >"$PI_SANDBOX_CONFIG"
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" use-pi 2.0.0
  [ "$status" -eq 0 ]
  grep -q '^PI_SANDBOX_HOME=/somewhere$' "$PI_SANDBOX_CONFIG"
  grep -q '^PI_VERSION=2.0.0$' "$PI_SANDBOX_CONFIG"
  [ "$(grep -c '^PI_VERSION=' "$PI_SANDBOX_CONFIG")" -eq 1 ]
}

@test "use-pi: rejects a bogus version without touching anything" {
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" use-pi latest
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a pi version"* ]]
  [ ! -e "$PI_SANDBOX_CONFIG" ]
  [ ! -s "$FAKE_DOCKER_LOG" ]
}

@test "use-pi: bare invocation without host pi asks for an explicit version" {
  no_pi="$TEST_TMP/tools-no-pi"
  mkdir -p "$no_pi"
  for t in "$SHIM_TOOLS"/*; do
    [ "$(basename "$t")" = pi ] || ln -s "$t" "$no_pi/"
  done
  run env PATH="$SHIM_DOCKER:$no_pi" "$PIS" use-pi
  [ "$status" -eq 1 ]
  [[ "$output" == *"host pi not found on PATH"* ]]
  [[ "$output" == *"pis use-pi x.y.z"* ]]
}

@test "doctor: pi version drift warns and points at use-pi" {
  run env XIAOMI_TOKEN_PLAN_SGP_API_KEY=tok FAKE_HOST_PI_VERSION=9.9.9 \
    PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"pi version drift: host pi 9.9.9, sandbox pinned to 1.2.0"* ]]
  [[ "$output" == *"pis use-pi"* ]]
}

@test "doctor: in-sync versions are reported as in sync" {
  run env XIAOMI_TOKEN_PLAN_SGP_API_KEY=tok FAKE_HOST_PI_VERSION=1.2.0 \
    PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"pi version in sync (host and sandbox: 1.2.0)"* ]]
}

@test "pi runs announce drift up front, and the probe never runs host pi" {
  run env XIAOMI_TOKEN_PLAN_SGP_API_KEY=tok FAKE_HOST_PI_VERSION=9.9.9 \
    PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pi version drift: host pi 9.9.9, sandbox pinned to 1.2.0"* ]]
  [ ! -e "$PI_TRIPWIRE" ]
}

@test "pi version: the image bakes PI_VERSION and the entrypoint heals the volume" {
  # Named volumes seed from the image only on first use — without the heal,
  # updates stay hidden behind stale volume content.
  grep -q 'ENV PI_VERSION' "$REPO_ROOT/docker/Dockerfile.base"
  grep -q 'pi-coding-agent@\$PI_VERSION' "$REPO_ROOT/docker/entrypoint.sh"
}
