# AGENTS.md — developing pi-sandbox-containers

Standing instructions for agents (and humans) working **on this repo**.
This is not the sandbox instruction file: `pi-home/AGENTS.md` governs work
inside every sandbox started with `pis`. Different file, different audience —
never merge the two.

## The gate

Before declaring any change done, run:

```bash
scripts/check.sh
```

It lints every shell script (shellcheck + shfmt) and runs the hermetic bats
suite in `tests/`. Everything must be green. "It works on my machine" is not
evidence — report the exact command and its result.

After touching `bin/pis` or `docker/`, also run `scripts/check.sh --slow` when
Docker is available (adds `pis doctor --smoke` and a compose lifecycle smoke).
`scripts/qa.sh` is a thin compatibility wrapper for the same gate.

## Text/Writing

Be concise. Do not give excessive detail when responding to the user, when writing docs, or writing git commits especially. Don't leave out critical elements, but you also don't need to include every ephemeral detail.
## Tests

- The suite lives in `tests/*.bats`, one bats case per invariant. New behavior
  gets a new case; a bug fix gets a failing case first.
- Fixtures are built in `setup()`, throwaway trees in `teardown()` — see
  `tests/test_helper.bash`. Nothing may touch real host or sandbox state.
- The seams are the env vars the real tools honor: `PI_SANDBOX_HOME`,
  `PI_AGENT_DIR`, `PI_HOME_SRC`, `PI_CODING_AGENT_DIR`, `PI_SANDBOX_CONFIG`.
- The fast tier is hermetic by design: it needs only bash, jq, rsync and
  coreutils — no Docker, no network. Docker is a test double where needed.
- Shell tests are shellcheck+shfmt clean; `.bats` files are shfmt-clean
  (`shfmt -ln bats -i 2 -ci`).

## Invariants that must never regress

- **Never fall back to host pi.** Any failure in the sandbox chain is a hard
  error with a fix hint; whenever `pis` runs pi, the boundary is real.
- **`auth.json` never on disk in sandboxes.** Auth is the `.env` passthrough
  contract (every variable in `.env` is injected into every sandbox; host
  `*_API_KEY` / `PI_SANDBOX_EXTRA_ENV` vars pass per exec); seeding removes pi's
  empty `{}` stub and loudly removes any populated one;
  a credential appearing in the `pi-home/` overlay aborts the sync.
- **Git identity crosses read-only; credentials never.** `~/.gitconfig` and
  `~/.config/git` are mounted read-only so commits inside carry the host
  identity; `~/.ssh`, `~/.git-credentials` and ssh-agent are never mapped —
  push/PR stays on the host.
- **Deletions propagate host → overlay → container agent dir.** Removing
  something on the host must remove it everywhere; stale copies from older
  seeds must not linger in volumes.
- **Un-loadable extensions never cross a layer.** Empty files, files without
  exports, and symlinks are quarantined at sync and seed, loudly.
- **`sessions/`, `install/`, `models-store.json` survive seeding** (per-sandbox
  state lives in the volume); `.sync-stamp` is host bookkeeping and is never
  delivered.
- **`docker/` content and `PI_VERSION` stamp the images.** Anything changing
  under `docker/` or a `PI_VERSION` bump must mark images stale so `pis`
  rebuilds automatically.
- **The mirror deltas are exactly:** `npm:pi-sbx` stripped from settings and
  npm `package.json`, and `defaultProjectTrust: "always"`. Nothing else drifts.

## Tooling

Tool versions for the gate are pinned in `mise.toml` (shellcheck, shfmt, bats),
but `scripts/check.sh` resolves **system binaries first** and only falls back to
the pins, printing every resolved tool + version so skew is visible. Use
`--pinned` (or `CHECK_PREFER=mise`) for deterministic tooling. `./install` runs
a non-fatal `mise install`; mise installs are machine-wide, `mise.toml` files
are configuration only.

Future upgrades (documented, deliberately not built yet): a pi extension
(`agent_before_settle`) scoped to this repo by a `scripts/check.sh` presence
check, and a `core.hooksPath` pre-commit hook that runs the gate.
