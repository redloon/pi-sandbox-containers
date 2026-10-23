#!/usr/bin/env bash
# entrypoint.sh — container entrypoint for every pi sandbox.
#
# 1. Seed the pi agent directory from the /opt/pi-home overlay.
# 2. If the mounted workspace declares tools (mise.toml / .tool-versions),
#    trust and install them so project toolchains just work.
# 3. Run the requested command. Whatever happens — pi crashing included — the
#    container stays alive ("keep-alive") so you can `pis shell` in and debug.
set -uo pipefail

seed-pi-home || echo "entrypoint: warning: seed-pi-home failed" >&2

# `pis` polls for this marker before running anything in a fresh container
# (compose up -d returns while this script is still working); remove any stale
# one first so a restart cannot report ready too early.
rm -f /tmp/pi-sandbox-ready

# The mise data volume is seeded from the image only on first use, so a pi
# version bump would otherwise stay hidden behind the old volume content
# ("doctor says in sync, pi still old"). Re-pin pi to the image's PI_VERSION
# whenever they differ.
if [[ -n "${PI_VERSION:-}" ]] && ! pi --version 2>/dev/null | grep -qx "$PI_VERSION"; then
  echo "entrypoint: updating pi to $PI_VERSION (sandbox had: $(pi --version 2>/dev/null || echo none))" >&2
  npm install -g --ignore-scripts "@earendil-works/pi-coding-agent@$PI_VERSION" >/dev/null 2>&1 &&
    mise reshim >/dev/null 2>&1 ||
    echo "entrypoint: warning: could not install pi $PI_VERSION" >&2
fi

# Android profile: the SDK is a read-only host mount at /opt/android-sdk, so the
# AVD cannot be baked into the image at build time. Create it on first start
# (idempotent) so the app repo's ensure-emulator.sh finds it ready — the same
# AVD that script would fall back to creating. Name and system image are
# configurable (compose.yaml passes PI_SANDBOX_AVD_NAME /
# PI_SANDBOX_ANDROID_SYSTEM_IMAGE, resolved from env / .pi-sandbox.toml).
AVD_NAME="${PI_SANDBOX_AVD_NAME:-pixel_6_api_34}"
SYSTEM_IMAGE="${PI_SANDBOX_ANDROID_SYSTEM_IMAGE:-system-images;android-34;google_apis;x86_64}"
SYSTEM_IMAGE_DIR="${SYSTEM_IMAGE//;//}"
if [[ -d "/opt/android-sdk/$SYSTEM_IMAGE_DIR" ]] &&
  ! emulator -list-avds 2>/dev/null | grep -qx "$AVD_NAME"; then
  echo no | avdmanager create avd -n "$AVD_NAME" \
    -k "$SYSTEM_IMAGE" --force >/dev/null 2>&1 ||
    echo "entrypoint: warning: could not pre-create AVD $AVD_NAME (ensure-emulator.sh retries)" >&2
fi

# Startup work is done — execs may now rely on the prepared sandbox state.
touch /tmp/pi-sandbox-ready

if [[ -f /workspace/mise.toml || -f /workspace/.tool-versions ]]; then
  mise trust /workspace >/dev/null 2>&1 || true
  if ! (cd /workspace && mise install); then
    echo "entrypoint: warning: mise install failed for /workspace" >&2
  fi
fi

if [[ "${1:-}" == "keep-alive" ]]; then
  echo "sandbox ready (keep-alive) — pi is not running; use 'pis' from the host to start it."
  exec sleep infinity
fi

"$@"
rc=$?

echo
echo "$* exited $rc — container kept alive for debugging (try: pis shell / pis logs)" >&2
exec sleep infinity
