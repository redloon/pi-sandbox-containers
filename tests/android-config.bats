#!/usr/bin/env bats
# android toolchain pins — structural SDK parts (cmdline-tools, platform-tools,
# emulator) are always required; the project-specific components, AVD name and
# system image are configurable via env or .pi-sandbox.toml (env > file >
# default), flowing into the SDK missing-parts check and the entrypoint's AVD
# preparation via compose.
#
# Hermetic: docker is a test double (tests/test_helper.bash), the SDK is a
# throwaway tree of directories.

load test_helper

setup() {
  make_tree
  make_shims
  cd "$TEST_TMP/repo"
  touch settings.gradle.kts # auto-detect: android
  SDK="$TEST_TMP/android-sdk"
  export PI_SANDBOX_ANDROID_SDK="$SDK"
  export FAKE_DOCKER_ENV_DUMP="$TEST_TMP/docker-env-dump"
}

teardown() {
  cd /
  drop_tree
}

make_sdk() { # $@ = extra component dirs beyond the structural three
  mkdir -p "$SDK/cmdline-tools/latest" "$SDK/platform-tools" "$SDK/emulator"
  local d
  for d in "$@"; do mkdir -p "$SDK/$d"; done
}

@test "pins: defaults are unchanged when nothing is configured" {
  make_sdk platforms/android-36 build-tools/36.0.0 system-images/android-34/google_apis/x86_64
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"sdk:       ok ($SDK)"* ]]
  grep -q '^PI_SANDBOX_AVD_NAME=pixel_6_api_34$' "$FAKE_DOCKER_ENV_DUMP"
  grep -q '^PI_SANDBOX_ANDROID_SYSTEM_IMAGE=system-images;android-34;google_apis;x86_64$' "$FAKE_DOCKER_ENV_DUMP"
}

@test "pins: PI_SANDBOX_ANDROID_SDK_COMPONENTS changes the missing-parts check" {
  make_sdk platforms/android-33
  run env PI_SANDBOX_ANDROID_SDK_COMPONENTS="platforms/android-33" \
    PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"sdk:       ok ($SDK)"* ]]
  run env PI_SANDBOX_ANDROID_SDK_COMPONENTS="platforms/android-36" \
    PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"missing: platforms/android-36"* ]]
}

@test "pins: sdk_components in .pi-sandbox.toml change the missing-parts check" {
  make_sdk platforms/android-35
  echo 'sdk_components = "platforms/android-35"' >.pi-sandbox.toml
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"sdk:       ok ($SDK)"* ]]
  [[ "$output" == *"android (from auto-detect)"* ]] # no profile key needed
}

@test "pins: structural SDK parts stay required regardless of sdk_components" {
  make_sdk platforms/android-33
  rmdir "$SDK/emulator"
  run env PI_SANDBOX_ANDROID_SDK_COMPONENTS="platforms/android-33" \
    PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"missing: emulator"* ]]
}

@test "pins: toml avd_name and system_image parse and reach compose" {
  make_sdk platforms/android-36 build-tools/36.0.0 system-images/android-34/google_apis/x86_64
  cat >.pi-sandbox.toml <<'EOF'
profile = "android"
avd_name = "ci_avd"
system_image = "system-images;android-35;google_apis;x86_64"
EOF
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" status
  [ "$status" -eq 0 ]
  grep -q '^PI_SANDBOX_AVD_NAME=ci_avd$' "$FAKE_DOCKER_ENV_DUMP"
  grep -q '^PI_SANDBOX_ANDROID_SYSTEM_IMAGE=system-images;android-35;google_apis;x86_64$' "$FAKE_DOCKER_ENV_DUMP"
}

@test "pins: env beats .pi-sandbox.toml" {
  echo 'avd_name = "file_avd"' >.pi-sandbox.toml
  run env PI_SANDBOX_AVD_NAME=env_avd PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" status
  [ "$status" -eq 0 ]
  grep -q '^PI_SANDBOX_AVD_NAME=env_avd$' "$FAKE_DOCKER_ENV_DUMP"
}

@test "pins: compose passes them to the android service and the entrypoint uses them" {
  grep -q 'PI_SANDBOX_AVD_NAME: "${PI_SANDBOX_AVD_NAME' "$REPO_ROOT/compose.yaml"
  grep -q 'PI_SANDBOX_ANDROID_SYSTEM_IMAGE' "$REPO_ROOT/compose.yaml"
  grep -q 'PI_SANDBOX_AVD_NAME:-pixel_6_api_34' "$REPO_ROOT/docker/entrypoint.sh"
  grep -q 'PI_SANDBOX_ANDROID_SYSTEM_IMAGE:-system-images;android-34;google_apis;x86_64' "$REPO_ROOT/docker/entrypoint.sh"
}
