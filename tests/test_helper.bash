# shellcheck shell=bash
# Shared fixtures for the pi-sandbox-containers hermetic test suite (tests/*.bats).
#
# Every case runs against a throwaway tree; the seams are the same env vars
# the real tools honor (see bin/pis and docker/seed-pi-home):
#   PI_SANDBOX_HOME      pis config home (the pi-home/ overlay lives here)
#   PI_AGENT_DIR         pretend ~/.pi/agent (sync source)
#   PI_HOME_SRC          seed source (defaults to the overlay)
#   PI_CODING_AGENT_DIR  pretend container agent dir (seed destination)
#   PI_SANDBOX_CONFIG    points at a nonexistent file (never the real config)
#   PI_SANDBOX_GIT_HOME  pretend host git home (bind-mount source)
#
# Nothing here touches real host or sandbox state.

# Consumed by the .bats files that `load` this helper.
REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
# shellcheck disable=SC2034  # consumed by the .bats files that load this helper
PIS="$REPO_ROOT/bin/pis"
# shellcheck disable=SC2034  # consumed by the .bats files that load this helper
SEED="$REPO_ROOT/docker/seed-pi-home"

make_tree() {
  TEST_TMP="$(mktemp -d)"
  export PI_SANDBOX_HOME="$TEST_TMP/config"
  export PI_AGENT_DIR="$TEST_TMP/host-agent"
  export PI_HOME_SRC="$TEST_TMP/config/pi-home"
  export PI_CODING_AGENT_DIR="$TEST_TMP/sbx-agent"
  export PI_SANDBOX_CONFIG="$TEST_TMP/no-such-config"
  export PI_SANDBOX_GIT_HOME="$TEST_TMP/git-home"
  export PI_SANDBOX_NO_SYNC=1
  unset PI_SANDBOX_PROFILE PI_VERSION PI_SANDBOX_EXTRA_ENV PI_SANDBOX_ALLOW_NO_AUTH \
    PI_SANDBOX_ANDROID_SDK_COMPONENTS PI_SANDBOX_AVD_NAME PI_SANDBOX_ANDROID_SYSTEM_IMAGE \
    XIAOMI_TOKEN_PLAN_SGP_API_KEY ANTHROPIC_API_KEY OPENROUTER_API_KEY \
    PI_SANDBOX_ANDROID_SDK
  mkdir -p "$PI_SANDBOX_HOME" "$PI_AGENT_DIR/extensions" "$PI_AGENT_DIR/npm" \
    "$PI_CODING_AGENT_DIR/extensions" "$PI_SANDBOX_GIT_HOME"
  # A fleet home needs compose.yaml + docker/ for the policy paths under test.
  touch "$PI_SANDBOX_HOME/compose.yaml"
  mkdir -p "$PI_SANDBOX_HOME/docker"
  echo base >"$PI_SANDBOX_HOME/docker/Dockerfile.base"
  # Throwaway repos for repo-root discovery / project naming.
  mkdir -p "$TEST_TMP/repo/.git" "$TEST_TMP/repo/nested/deep"
  mkdir -p "$TEST_TMP/My Project/.git" "$TEST_TMP/My Project/a/b"
  mkdir -p "$TEST_TMP/dup/My Project/.git"
}

drop_tree() {
  rm -rf "$TEST_TMP"
}

# Host-side tripwire + restricted PATH: every launcher dependency except
# docker, so tests can prove what happens when docker is missing — and that
# host pi is never executed in that case.
make_shims() {
  SHIM_TOOLS="$TEST_TMP/tools"
  SHIM_DOCKER="$TEST_TMP/tools-docker"
  export PI_TRIPWIRE="$TEST_TMP/host-pi-was-executed"
  export FAKE_DOCKER_LOG="$TEST_TMP/docker-invocations.log"
  export FAKE_DOCKER_DUMP="$TEST_TMP/docker-hash-dump"
  mkdir -p "$SHIM_TOOLS" "$SHIM_DOCKER"
  local t
  for t in bash basename cat cmp cp cut dirname find grep head id jq ln mkdir mktemp \
    mv readlink rm rsync sed sha256sum stat sort tail touch tr xargs; do
    ln -s "$(command -v "$t")" "$SHIM_TOOLS/$t"
  done
  cat >"$SHIM_TOOLS/pi" <<'EOF'
#!/usr/bin/env bash
# Version probes are metadata, not a fallback execution of host pi: they never
# trip the tripwire (which proves pi is never run *instead of* the sandbox).
if [[ "${1:-}" == "--version" ]]; then
  echo "${FAKE_HOST_PI_VERSION:-1.2.0}"
  exit 0
fi
echo "host pi executed: $*" > "${PI_TRIPWIRE:?PI_TRIPWIRE not set}"
exit 0
EOF
  cat >"$SHIM_DOCKER/docker" <<'EOF'
#!/usr/bin/env bash
# Test double for docker: logs every invocation and plays back canned
# behavior driven by FAKE_* env vars.
set -u
if [[ -n "${FAKE_DOCKER_LOG:-}" ]]; then printf 'docker %s\n' "$*" >> "$FAKE_DOCKER_LOG"; fi
case "${1:-}" in
  --version) echo "Docker version 0.0.0-testdouble" ;;
  info) exit "${FAKE_DOCKER_INFO_RC:-0}" ;;
  image)
    if [[ "${FAKE_IMAGE_LABEL+x}" == x ]]; then
      printf '%s\n' "$FAKE_IMAGE_LABEL"
      exit 0
    fi
    exit 1
    ;;
  compose)
    case "${2:-}" in
      version) echo "${FAKE_COMPOSE_VERSION:-2.31.0-testdouble}" ;;
      *)
        if [[ "${FAKE_DOCKER_DUMP+x}" == x ]]; then
          printf '%s\n' "${DOCKER_HASH:-}" > "$FAKE_DOCKER_DUMP"
        fi
        if [[ "${FAKE_DOCKER_ENV_DUMP+x}" == x ]]; then
          {
            printf 'PI_SANDBOX_AVD_NAME=%s\n' "${PI_SANDBOX_AVD_NAME:-}"
            printf 'PI_SANDBOX_ANDROID_SYSTEM_IMAGE=%s\n' "${PI_SANDBOX_ANDROID_SYSTEM_IMAGE:-}"
          } > "$FAKE_DOCKER_ENV_DUMP"
        fi
        # The ready-marker probe is infrastructure, not a user command: it
        # always answers "ready" so FAKE_EXEC_RC keeps modelling user execs.
        if [[ "${2:-}" == exec && "$*" != *pi-sandbox-ready* && "${FAKE_EXEC_RC:-0}" != 0 ]]; then
          exit "$FAKE_EXEC_RC"
        fi
        ;;
    esac
    ;;
esac
exit 0
EOF
  chmod +x "$SHIM_TOOLS/pi" "$SHIM_DOCKER/docker"
  : >"$FAKE_DOCKER_LOG"
}
