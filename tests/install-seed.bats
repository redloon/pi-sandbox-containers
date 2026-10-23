#!/usr/bin/env bats
# install auth seeding — ~/.pi/agent/auth.json entries with a .key become
# <SLUG_UPPER_WITH_UNDERSCORES>_API_KEY vars in .env (the passthrough contract);
# entries without one (OAuth /login providers) get a loud note instead.
# Values are never printed.
#
# Hermetic: the installer runs against a throwaway fleet copy and fake $HOME;
# docker/pis are test doubles (tests/test_helper.bash).

load test_helper

setup() {
  make_tree
  make_shims
  HOME_DIR="$TEST_TMP/home"
  FLEET="$TEST_TMP/fleet"
  mkdir -p "$HOME_DIR/.pi/agent" "$FLEET/bin" "$FLEET/docker" "$FLEET/pi-home"
  cp "$REPO_ROOT/install" "$REPO_ROOT/.env.example" "$REPO_ROOT/compose.yaml" "$FLEET/"
  cp "$REPO_ROOT/bin/pis" "$FLEET/bin/"
  touch "$FLEET/docker/Dockerfile.base"
  AUTH="$HOME_DIR/.pi/agent/auth.json"
}

teardown() {
  cd /
  drop_tree
}

run_install() {
  run env -u PI_SANDBOX_HOME -u PI_SANDBOX_CONFIG -u PI_SANDBOX_GIT_HOME \
    HOME="$HOME_DIR" PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$FLEET/install" --no-build
}

@test "install seeding: two providers with keys seed two convention-named vars" {
  cat >"$AUTH" <<'EOF'
{"anthropic": {"key": "sk-ant-secret"},
 "openrouter": {"key": "or-secret"}}
EOF
  run_install
  [ "$status" -eq 0 ]
  grep -q '^ANTHROPIC_API_KEY=sk-ant-secret$' "$FLEET/.env"
  grep -q '^OPENROUTER_API_KEY=or-secret$' "$FLEET/.env"
  [[ "$output" == *"ANTHROPIC_API_KEY, OPENROUTER_API_KEY"* ]]
  ! grep -q 'sk-ant-secret' <<<"$output"
  [ "$(stat -c %a "$FLEET/.env")" = 600 ]
}

@test "install seeding: an OAuth-only entry is noted and seeds nothing" {
  echo '{"vercel-ai-gateway": {"token": "t"}}' >"$AUTH"
  run_install
  [ "$status" -eq 0 ]
  [ ! -f "$FLEET/.env" ]
  [[ "$output" == *"vercel-ai-gateway"* ]]
  [[ "$output" == *"VERCEL_AI_GATEWAY_API_KEY"* ]]
  [[ "$output" == *"env-only"* ]]
}

@test "install seeding: mixed auth.json seeds keys and notes the keyless entry" {
  cat >"$AUTH" <<'EOF'
{"xiaomi-token-plan-sgp": {"key": "xm-secret"},
 "oauth-provider": {}}
EOF
  run_install
  [ "$status" -eq 0 ]
  grep -q '^XIAOMI_TOKEN_PLAN_SGP_API_KEY=xm-secret$' "$FLEET/.env"
  [[ "$output" == *"OAUTH_PROVIDER_API_KEY"* ]]
  ! grep -q 'xm-secret' <<<"$output"
}

@test "install seeding: no auth.json at all prints the manual setup hint" {
  run_install
  [ "$status" -eq 0 ]
  [ ! -f "$FLEET/.env" ]
  [[ "$output" == *"copy .env.example to .env"* ]]
}
