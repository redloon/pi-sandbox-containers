# Troubleshooting

## `pis` says "the Docker daemon is not reachable"

Start Docker (`sudo systemctl start docker`). `pis` hard-errors instead of
falling back to host pi on purpose — see docs/security.md. Check the whole chain
with `pis doctor`.

## Android: "/dev/kvm does not exist" or emulator is hopelessly slow

- The android sandbox needs KVM: virtualization (VT-x/AMD-V) enabled in firmware
  and the `kvm` module loaded (`lsmod | grep kvm`).
- If `/dev/kvm` exists but `pis` says it's not accessible:
  `sudo usermod -aG kvm $USER` (re-login), or `sudo setfacl -m u:$USER:rw /dev/kvm`.
- Verify inside the sandbox: `pis run -- emulator -accel-check` → should say KVM.
- Emulator boot takes 1–2 minutes; `scripts/ensure-emulator.sh` waits up to 120 s
  and disables animations automatically.

## Auth: pi can't reach the Xiaomi provider

- `pis doctor` shows whether `XIAOMI_TOKEN_PLAN_SGP_API_KEY` is configured.
- If `.env` is missing: `./install` seeds it from `~/.pi/agent/auth.json`, or copy
  `.env.example` → `.env` and fill the key. (Resolution order in pi: process env,
  then `auth.json` — sandboxes only ever get the env var.)
- After changing `.env`, restart the container so the env is re-injected:
  `pis down && pis`.

## pi prompts / behaves differently than expected

- pi inside sandboxes runs with all tools enabled and `defaultProjectTrust:
  "always"` — it should never stop for permission or trust prompts. If pi asks
  something, that's the model talking, not a permission gate.
- `pi-sbx` is intentionally removed from sandbox settings (`pis sync-config`
  strips it; `--keep-pi-sbx` restores it). If you want it back, re-add it to
  `pi-home/settings.json` packages.

## Settings/AGENTS.md edits didn't apply

- Host-side changes (settings, new extensions, skills) are picked up
  **automatically** at the start of the next `pis` — you'll see a one-line
  `pi config synced from host: …` notice when something actually changed. If a
  run must not touch `pi-home/`, set `PI_SANDBOX_NO_SYNC=1`; to force a refresh,
  `pis sync-config`.
- `pi-home/AGENTS.md` is the curated exception — edit it directly in the repo.
- If a container was started by hand (`docker compose up`), re-seed with
  `pis run -- seed-pi-home`.

## Playwright version mismatch ("browser executable not found")

The web image bakes Chromium for `playwright@latest` at build time. If your
project pins a different Playwright, run once inside the sandbox:

```bash
pis run -- npx playwright install chromium
```

Browsers live in `/opt/pw-browsers` (persistent volume). Also set
`chromiumSandbox: false` in playwright config — required in containers with
`cap_drop: ALL`.

## An extension from my host machine is missing

`pis sync-config` skips symlinks that point outside `pi-home/` (they would dangle
inside containers) and prints a warning for each. To ship such an extension into
sandboxes, copy its real directory into `pi-home/extensions/`.

## pi crashed — how do I debug?

- Interactive `pis` drops you into a shell in the same environment right after the
  crash (`pi exited N — sandbox shell`).
- Any time later: `pis shell` (environment), `pis logs` (entrypoint output).
- The container never dies with pi; session history survives in the per-repo
  volume. Start a fresh pi with `pis --continue` to resume the session.

## Nuclear options

- `pis rebuild all` — rebuild all images (also happens automatically when `docker/`
  changes, detected via a content stamp).
- `pis clean -y` — delete this repo's sandbox volumes (including pi sessions).
  The next `pis` re-seeds everything from `pi-home/`.
- `pis sync-config` — re-snapshot host pi settings into `pi-home/`.
