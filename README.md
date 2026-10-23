# pi-sandbox-containers

Run **pi unattended inside Docker sandboxes** with a safe security boundary — and
almost no friction. The everyday command is just:

```bash
cd ~/work/my-app          # any work repo
pis                       # sandboxed pi, straight away
```

`pis` finds the repo root, auto-picks the right sandbox profile, builds the image
if it's missing or stale, starts (or reuses) a keep-alive container, and runs pi
inside it with all arguments passed through — `pis -p "task"` for unattended
one-shots, `pis --continue` to resume, exactly like local `pi`. One quiet notice
line (`⬢ android sandbox · /home/you/work/my-app`), then pi owns the terminal.

If anything in that chain fails — Docker down, build broken — `pis` **hard-errors
with a fix hint and never falls back to host pi**. Whenever `pis` runs, the
boundary is real.

## Setup (once)

```bash
cd ~/work/pi-sandbox-containers
./install
```

This installs `pis` into `~/.local/bin`, seeds `.env` with your provider's
credential vars from `~/.pi/agent/auth.json` (one `<provider>_API_KEY` per
entry, values never printed), runs `pis doctor`, and builds the images.
Idempotent — re-run after pulling changes. Requires Docker Compose ≥ 2.24 (the
`.env` passthrough uses the long-form `env_file`; `pis doctor` checks this).

## Sandbox profiles

| Profile | Auto-detected when the repo has | Contains |
|---|---|---|
| `android` | `settings.gradle.kts` / `build.gradle[.kts]` | everything below + JDK 21 (mise) + the host's Android SDK (mounted read-only) + headless emulator (AVD `pixel_6_api_34` by default, KVM-accelerated) |
| `web` | `package.json` | everything below + Playwright + pre-baked Chromium |
| `general` | anything else | mise, node 24, pi, git/ripgrep/fd/jq, build tools, tmux, vim, python — plus your read-only git identity |

Override detection with `PI_SANDBOX_PROFILE=web pis …` or a `.pi-sandbox.toml` in
the repo root: `profile = "android"`. Precedence: env → file → auto-detect
(android > web > general).

Android's multi-GB toolchain lives **only** on the host: the android sandbox
mounts `~/Android/Sdk` (override with `PI_SANDBOX_ANDROID_SDK`) read-only at
`/opt/android-sdk`, and the image itself just adds JDK 21 and the emulator's
runtime libraries to `general`. The SDK requirement is split in two: structural
parts (`cmdline-tools/latest`, `platform-tools`, `emulator`) are always
required; the project-specific parts default to `platforms/android-36`,
`build-tools/36.0.0`, `system-images/android-34/google_apis/x86_64` and are
configurable per repo via `.pi-sandbox.toml` or env (env wins; defaults shown):

```toml
sdk_components = "platforms/android-36 build-tools/36.0.0 system-images/android-34/google_apis/x86_64"
avd_name       = "pixel_6_api_34"
system_image   = "system-images;android-34;google_apis;x86_64"
```

(env forms: `PI_SANDBOX_ANDROID_SDK_COMPONENTS`, `PI_SANDBOX_AVD_NAME`,
`PI_SANDBOX_ANDROID_SYSTEM_IMAGE`; if you change `system_image`, include its
directory form in `sdk_components` too.) `pis doctor` checks the SDK and `pis`
hard-errors with a provisioning hint when anything is missing. Profiles run as
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
pis use-pi [x.y.z]      # pin the sandbox pi version (default: host pi's) + rebuild
pis install-apk [path] [args…]  # adb-install to a PHYSICAL device (host-side)
pis down                # stop container (volumes/sessions kept)
pis clean -y            # stop + delete volumes (incl. sessions)
pis sync-config         # refresh pi-home/ from ~/.pi/agent
pis --host [pi args…]   # explicitly run UNSANDBOXED host pi
```

`pis` reserves the words above as subcommands; `pis -- <args>` forces anything
through to pi (e.g. a prompt literally named "shell").

## Updating pi

Two pi versions live on your machine, and they move independently:

| | where | how it updates |
|---|---|---|
| **host pi** | your machine | updates itself |
| **sandbox pi** | baked into the images | **pinned** (`PI_VERSION`) — never changes under an unattended run |

So when the host updates, the sandbox intentionally stays put — and `pis` tells
you exactly that:

```
! pi version drift: host pi 1.4.0, sandbox pinned to 1.2.0 — run 'pis use-pi' to sync
```

One command fixes it:

```bash
pis use-pi           # adopt the host pi's version and rebuild the images
pis use-pi 1.5.0     # or pin any explicit version
```

The rebuild runs immediately, and since the version is part of the image stamp,
any later change re-rebuilds automatically. Running sandboxes pick the new pi up
on their next start — the entrypoint re-pins the shared tool volume to match the
image automatically, so there is nothing to clean by hand. The pin lives in
`~/.config/pi-sandbox/config` (`PI_VERSION=…`); `pis doctor` shows the state any
time. Six months from now: read the warning, run `pis use-pi`, done.

## Git in the sandbox

`/workspace` is your real repo: the container shares the same working tree and
the same `.git` as the host, so **commits inside are host commits** — same SHAs
on both sides, nothing to sync. Your `~/.gitconfig` and `~/.config/git/` are
mounted **read-only**, so identity, aliases and `core.editor` match your host
(vim is installed), and commit / branch / merge / `rebase -i` just work.

Anything that touches the network stays on the host: **push, PRs, and fetch** —
there are no SSH keys or tokens inside the boundary (see docs/security.md).
Since the `.git` is shared, a `git fetch` on the host is instantly visible
inside, so the natural split is: fetch/push on the host, everything else in the
sandbox.

## Physical devices

There is deliberately **no adb bridge into sandboxes** — one would hand sandbox
code full control of every device your host can see. Instead, build inside the
sandbox (output lands in the shared `/workspace`) and install from the host:

```bash
pis install-apk                                  # newest */build/outputs/*.apk
pis install-apk path/to/app.apk --grant-permissions   # explicit APK + adb args
```

`pis install-apk` resolves `adb` from `PI_SANDBOX_ANDROID_SDK/platform-tools`
(falling back to `PATH`) and runs `adb install -r …` on the host. Missing adb or
APK is a hard error — it never silently succeeds.

**Debug-keystore caveat**: debug APKs built in the sandbox are signed with the
sandbox's own debug keystore, so updating an app previously installed from a
host-built APK can fail with a signature mismatch. Fix with `adb uninstall`
first, or keep one consistent debug keystore across host and sandbox.

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
- **Auth**: the `.env`-as-passthrough contract — **every variable in `.env`**
  (your provider's `*_API_KEY`, or any other name) is injected as process env
  into every sandbox, so every provider pi supports works with zero code
  changes. Host `*_API_KEY` vars (plus `PI_SANDBOX_EXTRA_ENV` names) are
  forwarded on each exec — values never in argv; keyless providers set
  `PI_SANDBOX_ALLOW_NO_AUTH=1`. `pis status`/`doctor` show credential *names*
  and sources, never values. Credentials never persist on the sandbox's disk —
  pi's empty `{}` `auth.json` startup stub is cleaned up automatically and any
  populated one is removed with a warning. See `docs/security.md` for the threat
  model — including what env-var exposure means and how to go further (e.g.
  Docker Sandboxes' secret proxy) if your threat model requires it.
- **Crash-proof debugging**: the container is a keep-alive box independent of pi.
  When pi exits or crashes, interactive `pis` drops you into a sandbox shell with
  the state intact; `pis shell` / `pis logs` work any time afterwards.
- **Workspaces**: each repo is bind-mounted read-write at `/workspace`. The only
  other home-directory mounts are read-only: the Android SDK (android profile)
  and your git identity (`~/.gitconfig`, `~/.config/git`) — nothing else from
  your home directory is visible.
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
