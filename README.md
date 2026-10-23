# pi-sandbox-local

Run **pi unattended inside Docker sandboxes** with a safe security boundary — and
almost no friction. The everyday command is just:

```bash
cd ~/work/personal-crm   # any work repo
pis                      # sandboxed pi, straight away
```

`pis` finds the repo root, auto-picks the right sandbox profile, builds the image
if it's missing or stale, starts (or reuses) a keep-alive container, and runs pi
inside it with all arguments passed through — `pis -p "task"` for unattended
one-shots, `pis --continue` to resume, exactly like local `pi`. One quiet notice
line (`⬢ android sandbox · /home/you/work/personal-crm`), then pi owns the terminal.

If anything in that chain fails — Docker down, build broken — `pis` **hard-errors
with a fix hint and never falls back to host pi**. Whenever `pis` runs, the
boundary is real.

## Setup (once)

```bash
cd ~/work/pi-sandbox-local
./install
```

This installs `pis` into `~/.local/bin`, seeds `.env` with your
`XIAOMI_TOKEN_PLAN_SGP_API_KEY` from `~/.pi/agent/auth.json` (value never
printed), runs `pis doctor`, and builds the images. Idempotent — re-run after
pulling changes.

## Sandbox profiles

| Profile | Auto-detected when the repo has | Contains |
|---|---|---|
| `android` | `settings.gradle.kts` / `build.gradle[.kts]` | everything below + JDK 21 (mise) + the host's Android SDK (mounted read-only) + headless emulator (AVD `pixel_6_api_34`, KVM-accelerated) |
| `web` | `package.json` | everything below + Playwright + pre-baked Chromium |
| `general` | anything else | mise, node 24, pi, git/ripgrep/fd/jq, build tools, tmux, python |

Override detection with `PI_SANDBOX_PROFILE=web pis …` or a `.pi-sandbox.toml` in
the repo root: `profile = "android"`. Precedence: env → file → auto-detect
(android > web > general).

Android's multi-GB toolchain lives **only** on the host: the android sandbox
mounts `~/Android/Sdk` (override with `PI_SANDBOX_ANDROID_SDK`) read-only at
`/opt/android-sdk`, and the image itself just adds JDK 21 and the emulator's
runtime libraries to `general`. Required SDK components: `cmdline-tools/latest`,
`platform-tools`, `emulator`, `platforms/android-36`, `build-tools/36.0.0`,
`system-images;android-34;google_apis;x86_64` — `pis doctor` checks them and
`pis` hard-errors with a provisioning hint when any are missing. Profiles run as
separate containers per repo, so parallel projects never collide and sessions
persist per repo+profile until `pis clean -y`.

## Commands

```bash
pis [pi args…]          # pi inside the sandbox (args pass straight through)
pis run -- <cmd> [args] # any command in the sandbox (exit code preserved)
pis shell               # debug shell in the sandbox
pis logs [-f]           # container/entrypoint output
pis status              # repo, profile, image, container state
pis doctor [--smoke]    # environment checks (+ pi auth smoke test)
pis rebuild [profile|all]
pis down                # stop container (volumes/sessions kept)
pis clean -y            # stop + delete volumes (incl. sessions)
pis sync-config         # refresh pi-home/ from ~/.pi/agent
pis --host [pi args…]   # explicitly run UNSANDBOXED host pi
```

`pis` reserves the words above as subcommands; `pis -- <args>` forces anything
through to pi (e.g. a prompt literally named "shell").

## How the pieces fit

- **Images** (`docker/`): `general` (Dockerfile.base) is the base; `web` and
  `android` layer on it. Everything is mise-based, non-root, and stamped with a
  content hash so `pis` rebuilds automatically when `docker/` changes.
- **Reusable settings** (`pi-home/`): a generated mirror of your `~/.pi/agent`
  (settings.json, skills, prompts, extensions, themes) that `pis` refreshes
  **automatically** before every run — add an extension or change a setting on
  the host and the next `pis` simply has it, no manual step. The mirror applies
  two sandbox-only deltas: `pi-sbx` dropped (it caused the per-command permission
  prompts; inside the container it's redundant) and `defaultProjectTrust:
  "always"` so unattended runs never stall. `pis sync-config` forces a refresh
  (`PI_SANDBOX_NO_SYNC=1` disables the automatic one). The one file that is
  *yours to edit* is `pi-home/AGENTS.md`. See `pi-home/README.md`.
- **Custom AGENTS.md**: `pi-home/AGENTS.md` is your standing instruction file for
  every sandbox (project AGENTS.md files layer on top). No kit-injected defaults.
- **Auth**: `XIAOMI_TOKEN_PLAN_SGP_API_KEY` from a gitignored `.env` (or the host
  environment) is injected as process env. Credentials never persist on the
  sandbox's disk — pi's empty `{}` `auth.json` startup stub is cleaned up
  automatically and any populated one is removed with a warning. See
  `docs/security.md` for the threat model — including what env-var
  exposure means and how to go further (e.g. Docker Sandboxes' secret proxy) if
  your threat model requires it.
- **Crash-proof debugging**: the container is a keep-alive box independent of pi.
  When pi exits or crashes, interactive `pis` drops you into a sandbox shell with
  the state intact; `pis shell` / `pis logs` work any time afterwards.
- **Workspaces**: each repo is bind-mounted read-write at `/workspace`. The only
  other home-directory mount is the Android SDK (android profile), read-only —
  nothing else from your home directory is visible.
- **Invariants, regression-tested**: the bats suite in `tests/` (run via
  `scripts/check.sh`) guards that config deletions propagate at every layer
  (host → `pi-home/` → container volume), junk extension files are quarantined
  before they can break pi startup, and credentials never reach disk.

## Development & testing

One command gates every change:

```bash
scripts/check.sh          # shellcheck + shfmt + the hermetic bats suite (tests/)
scripts/check.sh --slow   # …plus the Docker tier: pis doctor --smoke + lifecycle
```

`scripts/qa.sh` is a compatibility wrapper for the same gate. Tool versions are
pinned in `mise.toml`, but system binaries win when present (`--pinned` forces
the pins); `./install` runs a non-fatal `mise install`. See `AGENTS.md` for the
invariants the suite protects and how to add a case.

## Docs

- `docs/security.md` — boundary model, hardening, credential handling, honest limits.
- `docs/troubleshooting.md` — KVM, emulator, auth, Playwright versions, crash debug.
