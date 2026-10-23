#!/usr/bin/env bats
# android SDK mount policy — the android profile bind-mounts the host Android
# SDK read-only at /opt/android-sdk, so a complete host SDK is a hard
# precondition: anything missing is a hard error with a provisioning hint,
# never a silent degrade. Non-android profiles never require it.
#
# Hermetic: docker is a test double (tests/test_helper.bash), the SDK is a
# throwaway tree of directories, and host pi is a tripwire.

load test_helper

setup() {
  make_tree
  make_shims
  cd "$TEST_TMP/repo"
  touch settings.gradle.kts # auto-detect: android
  SDK="$TEST_TMP/android-sdk"
  export PI_SANDBOX_ANDROID_SDK="$SDK"
}

teardown() {
  cd /
  drop_tree
}

make_sdk() {
  mkdir -p "$SDK/cmdline-tools/latest" "$SDK/platform-tools" "$SDK/emulator" \
    "$SDK/platforms/android-36" "$SDK/build-tools/36.0.0" \
    "$SDK/system-images/android-34/google_apis/x86_64"
}

@test "android SDK: a complete SDK lets the android sandbox start" {
  [[ -c /dev/kvm && -r /dev/kvm && -w /dev/kvm ]] || skip "needs rw /dev/kvm (ensure_kvm gate)"
  make_sdk
  run env ANTHROPIC_API_KEY=tok PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" run -- true
  [ "$status" -eq 0 ]
  grep -q "compose up -d android" "$FAKE_DOCKER_LOG"
  [ ! -e "$PI_TRIPWIRE" ]
}

@test "android SDK: a missing SDK directory is a hard error with a provisioning hint" {
  run env ANTHROPIC_API_KEY=tok PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" run -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs a host Android SDK at $SDK"* ]]
  [[ "$output" == *"PI_SANDBOX_ANDROID_SDK=/path/to/Android/Sdk"* ]]
  [[ "$output" == *"sdkmanager"* ]]
  ! grep -q "compose up" "$FAKE_DOCKER_LOG"
  [ ! -e "$PI_TRIPWIRE" ]
}

@test "android SDK: an incomplete SDK names every missing component" {
  make_sdk
  rmdir "$SDK/emulator" "$SDK/system-images/android-34/google_apis/x86_64"
  run env ANTHROPIC_API_KEY=tok PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" run -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing: emulator, system-images/android-34/google_apis/x86_64"* ]]
  ! grep -q "compose up" "$FAKE_DOCKER_LOG"
  [ ! -e "$PI_TRIPWIRE" ]
}

@test "android SDK: non-android profiles never require the SDK" {
  rm settings.gradle.kts
  run env ANTHROPIC_API_KEY=tok PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" run -- true
  [ "$status" -eq 0 ]
  grep -q "compose up -d general" "$FAKE_DOCKER_LOG"
}

@test "android SDK: status reports ok, incomplete and missing SDK states" {
  make_sdk
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"sdk:       ok ($SDK)"* ]]
  rmdir "$SDK/platform-tools"
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"missing: platform-tools"* ]]
  rm -rf "$SDK"
  run env PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"sdk:       MISSING (expected at $SDK)"* ]]
}

@test "android SDK: doctor passes a complete SDK and fails a partial one" {
  make_sdk
  run env ANTHROPIC_API_KEY=tok PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"android SDK complete ($SDK"* ]]
  rmdir "$SDK/build-tools/36.0.0"
  run env ANTHROPIC_API_KEY=tok PATH="$SHIM_DOCKER:$SHIM_TOOLS" "$PIS" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing: build-tools/36.0.0"* ]]
}

@test "android SDK: the SDK mount is read-only and lives only on the android service" {
  run grep -F 'PI_SANDBOX_ANDROID_SDK' "$REPO_ROOT/compose.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *":/opt/android-sdk:ro"* ]]
  [ "$(grep -c ':/opt/android-sdk:ro' "$REPO_ROOT/compose.yaml")" -eq 1 ]
}

@test "android SDK: the android image never downloads SDK packages at build time" {
  # The flaky dl.google.com downloads (Error on ZipFile unknown archive) must
  # stay gone: the Dockerfile only prepares the mount point and runtime libs.
  run grep -E '^[^#]*(sdkmanager|avdmanager|dl\.google\.com)' "$REPO_ROOT/docker/Dockerfile.android"
  [ "$status" -ne 0 ]
}
