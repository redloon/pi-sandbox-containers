#!/usr/bin/env bats
# install-apk — physical-device installs run on the HOST (no adb bridge into
# sandboxes): newest */build/outputs/*.apk by default, explicit path wins,
# extra args forward to `adb install -r`, and a missing adb or APK hard-errors
# (never silently succeeds).
#
# Hermetic: adb is a logging test double; nothing reaches a real device.

load test_helper

setup() {
  make_tree
  make_shims
  cd "$TEST_TMP/repo"
  SDK="$TEST_TMP/android-sdk"
  export PI_SANDBOX_ANDROID_SDK="$SDK"
  export FAKE_ADB_LOG="$TEST_TMP/adb-invocations.log"
  mkdir -p "$SDK/platform-tools"
  cat >"$SDK/platform-tools/adb" <<'EOF'
#!/usr/bin/env bash
printf 'adb %s\n' "$*" >>"${FAKE_ADB_LOG:?}"
EOF
  chmod +x "$SDK/platform-tools/adb"
  : >"$FAKE_ADB_LOG"
}

teardown() {
  cd /
  drop_tree
}

@test "install-apk: picks the newest APK under build/outputs and installs with -r" {
  mkdir -p app/build/outputs/apk/debug lib/build/outputs/apk/release
  : >app/build/outputs/apk/debug/old.apk
  : >lib/build/outputs/apk/release/new.apk
  touch -t 202001010000 app/build/outputs/apk/debug/old.apk
  touch -t 202101010000 lib/build/outputs/apk/release/new.apk
  : >decoy.apk # newest, but outside build/outputs — never picked
  run env PATH="$SHIM_TOOLS" "$PIS" install-apk
  [ "$status" -eq 0 ]
  grep -q "adb install -r $TEST_TMP/repo/lib/build/outputs/apk/release/new.apk" "$FAKE_ADB_LOG"
  ! grep -q decoy "$FAKE_ADB_LOG"
}

@test "install-apk: an explicit path wins and extra args forward to adb" {
  mkdir -p app/build/outputs/apk/debug
  : >app/build/outputs/apk/debug/app.apk
  : >explicit.apk
  run env PATH="$SHIM_TOOLS" "$PIS" install-apk explicit.apk --grant-permissions
  [ "$status" -eq 0 ]
  grep -q "adb install -r explicit.apk --grant-permissions" "$FAKE_ADB_LOG"
  ! grep -q "app.apk" "$FAKE_ADB_LOG"
}

@test "install-apk: no adb anywhere is a hard error with a hint" {
  rm "$SDK/platform-tools/adb"
  mkdir -p app/build/outputs/apk/debug
  : >app/build/outputs/apk/debug/app.apk
  run env PATH="$SHIM_TOOLS" "$PIS" install-apk
  [ "$status" -eq 1 ]
  [[ "$output" == *"adb not found"* ]]
  [[ "$output" == *"hint:"* ]]
  [ ! -s "$FAKE_ADB_LOG" ]
}

@test "install-apk: no APK under build/outputs is a hard error with a hint" {
  run env PATH="$SHIM_TOOLS" "$PIS" install-apk
  [ "$status" -eq 1 ]
  [[ "$output" == *"no APK found"* ]]
  [[ "$output" == *"hint:"* ]]
  [ ! -s "$FAKE_ADB_LOG" ]
}

@test "install-apk: a missing explicit APK path is a hard error" {
  run env PATH="$SHIM_TOOLS" "$PIS" install-apk missing.apk
  [ "$status" -eq 1 ]
  [[ "$output" == *"APK not found"* ]]
  [ ! -s "$FAKE_ADB_LOG" ]
}

@test "install-apk: adb falls back to PATH when the SDK has none" {
  rm "$SDK/platform-tools/adb"
  ADB_BIN="$TEST_TMP/adb-bin"
  mkdir -p "$ADB_BIN"
  cat >"$ADB_BIN/adb" <<'EOF'
#!/usr/bin/env bash
printf 'adb %s\n' "$*" >>"${FAKE_ADB_LOG:?}"
EOF
  chmod +x "$ADB_BIN/adb"
  mkdir -p app/build/outputs/apk/debug
  : >app/build/outputs/apk/debug/app.apk
  run env PATH="$ADB_BIN:$SHIM_TOOLS" "$PIS" install-apk
  [ "$status" -eq 0 ]
  grep -q "adb install -r" "$FAKE_ADB_LOG"
}

@test "install-apk: runs host-side and never touches docker" {
  mkdir -p app/build/outputs/apk/debug
  : >app/build/outputs/apk/debug/app.apk
  run env PATH="$SHIM_TOOLS" "$PIS" install-apk # no docker shim on PATH at all
  [ "$status" -eq 0 ]
  [ ! -s "$FAKE_DOCKER_LOG" ]
}
