#!/usr/bin/env bats
# git home mapping — the host's git identity/config is bind-mounted read-only
# into every sandbox so commits inside carry the host identity; credentials
# (~/.ssh, ~/.git-credentials) are deliberately never mapped, so push/PR stays
# on the host (docs/security.md).
#
# Hermetic: docker is a test double, the "host git home" is a throwaway dir.

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

@test "git home: missing config files are prepared before the container starts" {
  run env ANTHROPIC_API_KEY=tok PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" run -- true
  [ "$status" -eq 0 ]
  [ -f "$PI_SANDBOX_GIT_HOME/.gitconfig" ]
  [ -d "$PI_SANDBOX_GIT_HOME/.config/git" ]
  grep -q "compose up -d general" "$FAKE_DOCKER_LOG"
}

@test "git home: existing host config is left untouched" {
  printf '[user]\n\tname = Test User\n' >"$PI_SANDBOX_GIT_HOME/.gitconfig"
  run env ANTHROPIC_API_KEY=tok PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" run -- true
  [ "$status" -eq 0 ]
  grep -q 'name = Test User' "$PI_SANDBOX_GIT_HOME/.gitconfig"
}

@test "git home: identity and config mount read-only in every profile" {
  [ "$(grep -c '/home/pi/.gitconfig:ro' "$REPO_ROOT/compose.yaml")" -eq 3 ]
  [ "$(grep -c '/home/pi/.config/git:ro' "$REPO_ROOT/compose.yaml")" -eq 3 ]
}

@test "git home: credentials and ssh keys are never mapped in" {
  run grep -E 'git-credentials|\.ssh' "$REPO_ROOT/compose.yaml"
  [ "$status" -ne 0 ]
}
