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

## Auth: pi can't reach the model provider

- `pis doctor` shows which credential vars are configured (names and sources,
  never values). Auth is a passthrough: **every variable in `.env`** becomes env
  inside every sandbox, and exported `*_API_KEY` host vars (plus any names in
  `PI_SANDBOX_EXTRA_ENV`) are forwarded on each exec.
- If `.env` is missing: `./install` seeds `<PROVIDER>_API_KEY` vars from
  `~/.pi/agent/auth.json`, or copy `.env.example` → `.env` and set the vars your
  provider needs. Sandboxes are env-only — OAuth `/login` credentials in
  `auth.json` never cross the boundary; put the provider's env var in `.env` by
  hand if pi's provider docs name one.
- Keyless provider (e.g. a local endpoint)? `PI_SANDBOX_ALLOW_NO_AUTH=1` skips
  the guard.
- After changing `.env`, restart the container so the env is re-injected:
  `pis down && pis`.

## pi prompts / behaves differently than expected

- pi inside sandboxes runs with all tools enabled and `defaultProjectTrust:
  "always"` — it should never stop for permission or trust prompts. If pi asks
  something, that's the model talking, not a permission gate.
- Plan-mode-style extensions enforce their own bash command-policy allowlist on
  top of tool visibility — seeing `!`/bash does not mean every command is
  allowed. Tool visibility ≠ command allowlist; if commands get refused, check
  the extension's policy, not the sandbox.
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

## `Failed to load extension "…": Extension does not export a valid factory function`

pi fails fast when an extension file is empty, has no exports, or is a dangling
symlink — one bad file fails startup for the whole sandbox. Three layers guard
this class:

1. The config sync quarantines such files at the host source, loudly, before
   they ever reach `pi-home/`.
2. `seed-pi-home` re-checks at delivery (catches hand-edited overlays).
3. Seeds propagate deletions (`rsync --delete`), so stale copies left in old
   container volumes — the way this error appeared "out of nowhere" — are
   removed automatically on the next start.

If you see it anyway: run `pis` again (the seed self-heals), start once with
`pi -ne` to skip extensions, or `pis clean -y` to reset volumes.
The bats suite in `tests/` regression-tests these invariants (`scripts/check.sh`).

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
