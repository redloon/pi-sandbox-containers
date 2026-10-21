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
