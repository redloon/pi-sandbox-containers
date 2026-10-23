#!/usr/bin/env bats
# pis policy — profile selection, project naming, image staleness stamps,
# subcommand dispatch, and the never-fall-back-to-host-pi rule.
# (Provider auth lives in tests/auth.bats.)
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

# ------------------------------------------------------------- profiles ----

@test "profile precedence: PI_SANDBOX_PROFILE beats .pi-sandbox.toml" {
  echo 'profile = "android"' >.pi-sandbox.toml
  run env PI_SANDBOX_PROFILE=web PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"profile:   web (from PI_SANDBOX_PROFILE)"* ]]
}

@test "profile precedence: .pi-sandbox.toml beats auto-detect" {
  touch settings.gradle.kts # auto-detect would say android
  echo 'profile = "web"' >.pi-sandbox.toml
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"profile:   web (from .pi-sandbox.toml)"* ]]
}

@test "auto-detect: gradle repo resolves to android" {
  touch settings.gradle.kts
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"profile:   android (from auto-detect)"* ]]
}

@test "auto-detect: package.json repo resolves to web" {
  echo '{}' >package.json
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"profile:   web (from auto-detect)"* ]]
}

@test "auto-detect: plain repo resolves to general" {
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"profile:   general (from auto-detect)"* ]]
}

@test "unknown profile dies with the expected-values hint" {
  run env PI_SANDBOX_PROFILE=bogus PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" status
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown profile 'bogus'"* ]]
  [[ "$output" == *"expected: general | web | android"* ]]
}

# -------------------------------------------------- repo root + naming ----

@test "repo root is found from nested dirs and named pi-sbx-<slug>-<hash6>" {
  cd "$TEST_TMP/My Project/a/b"
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"repo:      $TEST_TMP/My Project"* ]]
  [[ "$output" =~ project:\ \ \ pi-sbx-my-project-[0-9a-f]{6} ]]
}

@test "project name is stable across invocations and differs across paths" {
  cd "$TEST_TMP/My Project"
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" status
  first="$(grep '^project:' <<<"$output")"
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" status
  second="$(grep '^project:' <<<"$output")"
  [ "$first" = "$second" ]
  cd "$TEST_TMP/dup/My Project"
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" status
  third="$(grep '^project:' <<<"$output")"
  [ "$first" != "$third" ]
  [[ "$third" == "project:   pi-sbx-my-project-"* ]]
}

# ----------------------------------------------------- image stamping ----

@test "image stamp: stable across runs and immune to unrelated files" {
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" status
  [ "$status" -eq 0 ]
  h1="$(cat "$FAKE_DOCKER_DUMP")"
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" status
  [ "$status" -eq 0 ]
  h2="$(cat "$FAKE_DOCKER_DUMP")"
  [ "$h1" = "$h2" ]
  echo unrelated >"$PI_SANDBOX_HOME/README.md"
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" status
  h3="$(cat "$FAKE_DOCKER_DUMP")"
  [ "$h1" = "$h3" ]
}

@test "image stamp: any change under docker/ marks images stale" {
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" status
  h1="$(cat "$FAKE_DOCKER_DUMP")"
  echo changed >>"$PI_SANDBOX_HOME/docker/Dockerfile.base"
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" status
  h2="$(cat "$FAKE_DOCKER_DUMP")"
  [ "$h2" != "$h1" ]
}

@test "image stamp: a PI_VERSION bump marks images stale" {
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" status
  h1="$(cat "$FAKE_DOCKER_DUMP")"
  run env PI_VERSION=9.9.9 PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" status
  h2="$(cat "$FAKE_DOCKER_DUMP")"
  [ "$h2" != "$h1" ]
}

@test "status flips a built image from ok to stale when docker/ changes" {
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" status
  h="$(cat "$FAKE_DOCKER_DUMP")"
  run env FAKE_IMAGE_LABEL="$h" PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" status
  [[ "$output" == *"image:     pi-sandbox:general → ok"* ]]
  echo changed >>"$PI_SANDBOX_HOME/docker/Dockerfile.base"
  run env FAKE_IMAGE_LABEL="$h" PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" status
  [[ "$output" == *"image:     pi-sandbox:general → stale"* ]]
}

# ---------------------------------------------------------- dispatch ------

@test "dispatch: --version prints the version and touches nothing" {
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" --version
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^pis\ [0-9]+\.[0-9]+\.[0-9]+$ ]]
  [ ! -s "$FAKE_DOCKER_LOG" ]
}

@test "dispatch: status and help are reserved words, not pi prompts" {
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" status
  [[ "$output" == *"repo:"* ]]
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" help
  [[ "$output" == *"Usage:"* ]]
  [ ! -s "$FAKE_DOCKER_LOG" ] || ! grep -q 'pis-sh' "$FAKE_DOCKER_LOG"
}

@test "dispatch: run executes in the sandbox and preserves exit codes" {
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" run -- true
  [ "$status" -eq 0 ]
  grep -q "compose exec -T general true" "$FAKE_DOCKER_LOG"
  run env FAKE_EXEC_RC=42 PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" run -- true
  [ "$status" -eq 42 ]
}

@test "dispatch: shell is the sandbox shell; 'pis -- shell' passes through to pi" {
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" shell
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs an interactive terminal"* ]]
  run env ANTHROPIC_API_KEY=tok PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" -- shell
  [ "$status" -eq 0 ]
  grep -q "pis-sh shell" "$FAKE_DOCKER_LOG"
}

@test "dispatch: unknown words pass through to pi as prompts" {
  run env ANTHROPIC_API_KEY=tok PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" fix the bug
  [ "$status" -eq 0 ]
  grep -q "pis-sh fix the bug" "$FAKE_DOCKER_LOG"
}

@test "dispatch: clean requires -y and never touches docker without it" {
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" clean
  [ "$status" -eq 1 ]
  [[ "$output" == *"clean deletes this sandbox's volumes"* ]]
  [[ "$output" == *"pis clean -y"* ]]
  [ ! -s "$FAKE_DOCKER_LOG" ]
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" clean -y
  [ "$status" -eq 0 ]
  grep -q "compose down -v --remove-orphans" "$FAKE_DOCKER_LOG"
}

# ------------------------------------------ never fall back to host pi ----

@test "never fallback: docker missing → hard error, host pi provably untouched" {
  run env PATH="$SHIM_TOOLS" "$PIS" run -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"docker is not installed"* ]]
  [[ "$output" == *"never runs pi unsandboxed"* ]]
  [ ! -e "$PI_TRIPWIRE" ]
  run env PATH="$SHIM_TOOLS" "$PIS"
  [ "$status" -eq 1 ]
  [ ! -e "$PI_TRIPWIRE" ]
}

@test "never fallback: daemon unreachable → hard error, host pi provably untouched" {
  run env FAKE_DOCKER_INFO_RC=1 PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" run -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"Docker daemon is not reachable"* ]]
  [[ "$output" == *"never runs pi unsandboxed"* ]]
  [ ! -e "$PI_TRIPWIRE" ]
}

# --------------------------------------------------------- doctor gate ----

@test "doctor: docker compose older than 2.24 is flagged (env_file needs it)" {
  run env ANTHROPIC_API_KEY=tok FAKE_COMPOSE_VERSION=2.20.0 \
    PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"older than 2.24"* ]]
}

@test "doctor: a modern docker compose passes the version check" {
  run env ANTHROPIC_API_KEY=tok FAKE_COMPOSE_VERSION=2.31.0 \
    PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" doctor
  [ "$status" -eq 0 ]
  ! grep -q "older than 2.24" <<<"$output"
}
