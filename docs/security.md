# Security model

## The boundary

Everything pi does happens **inside the container**: model calls, built-in tools,
`!` shell commands, extensions, npm/mise installs, gradle builds, the Android
emulator. There is no tool-by-tool routing and no per-command approval — the
container is the permission. This is deliberate: pi-sbx-style command routing
required constant attention and provided only partial isolation.

What crosses the boundary, by design:

| Channel | Direction | Notes |
|---|---|---|
| `/workspace` bind mount | read-write | the working repo only; writes sync to the host |
| `XIAOMI_TOKEN_PLAN_SGP_API_KEY` | env in | process environment inside the sandbox; never written to disk there |
| `pi-home/.env` visibility | only when this repo is the workspace | the `.env` file is bind-mounted along with `/workspace` **only** when you run `pis` inside pi-sandbox-local itself (as in the self-tests); for any other repo it is not mounted. Prefer keeping long-lived secrets out of repos you open in sandboxes. |
| Network egress | out | required for the Xiaomi API, npm, mise, Gradle, SDK downloads |
| pi-home overlay | read-only in | your settings/AGENTS.md/skills, re-seeded per start |
| `~/Android/Sdk` bind mount (android profile, `PI_SANDBOX_ANDROID_SDK`) | read-only in | the Android toolchain (SDK, emulator, system image); pure tooling — no credentials live there and the sandbox cannot write to it |

Everything else in your home directory — other repos, SSH keys, cloud
credentials, host pi sessions — is **not mounted and not reachable**. The one
carve-out is the Android SDK row above (toolchain only, read-only).

## Hardening (applied in `compose.yaml`)

- non-root user `pi`, UID/GID mapped to you (bind-mount writes are owned by you)
- `cap_drop: [ALL]`, `security_opt: [no-new-privileges:true]`, `init: true`
- no `docker.sock` mount (containers cannot control the Docker daemon)
- no published ports, no inbound network
- per-repo containers and volumes: one repo's sandbox cannot see another's
  sessions or agent state
- no sudo inside; need root anyway? `docker compose run --user root <profile>`

## Credentials: what env-var passthrough means

The chosen model injects the Xiaomi API key as process env. Consequences, stated
honestly:

- **Good**: the key is never on the sandbox's disk, never in a bind mount, and
  never in an image layer. Pi drops a benign **empty `{}` auth.json stub** at
  startup (no credential in it — verified); `seed-pi-home` deletes it before
  every run and loudly removes any *populated* auth.json it ever finds, so a real
  credential can never persist on the sandbox filesystem.
- **Exposure**: any process running inside the sandbox — including code the agent
  runs from the repo — can read the env var and could exfiltrate it over egress.
  The sandbox limits *blast radius to your machine*, not *secrets from a
  malicious repo*.
- **If that matters for a task** (running untrusted code), stronger options exist
  without changing this scaffold: run Docker Sandboxes (`sbx`) in front, which
  keeps the real key on the host and substitutes a per-request placeholder
  (`sbx secret set-custom --host <xiaomi-api-host> --env XIAOMI_TOKEN_PLAN_SGP_API_KEY
  --placeholder '{rand}'`), or point `models.json` at a local proxy that holds the
  key. The `pis` interface does not change.

## What this does NOT protect against

- **Malicious code with network access** can exfiltrate the env credential and
  anything in `/workspace` (see above).
- **Kernel/container escapes** — this is a container boundary, not a VM. Keep
  Docker updated.
- **The agent itself** deleting or rewriting files in `/workspace` — that's the
  point of the mount. Work on a branch / commit before long unattended runs.
- **Resource exhaustion** — an unattended agent can burn CPU/disk. Volumes are
  per-repo and removable with `pis clean -y`.

## Rules the scaffold enforces

- `auth.json` must never *contain credentials* under `pi-home/` or in sandboxes
  (`sync-config` asserts the overlay is clean; `seed-pi-home` deletes any
  auth.json in sandboxes and warns loudly if one held a credential).
- `.env` is gitignored; `install` creates it with mode 600.
- `pis` never silently degrades to host pi. `pis --host` is the only unsandboxed
  path and prints a loud warning.
