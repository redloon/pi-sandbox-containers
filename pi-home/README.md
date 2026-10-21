# pi-home — the generated pi configuration mirror

**Mental model: `~/.pi/agent` on this machine is the single place you manage pi
configuration.** This directory is a *generated mirror* of it (minus secrets),
refreshed automatically at the start of every `pis` / `pis run` / `pis shell`,
and seeded into every sandbox's pi agent directory. You never need to remember
to "update pi-home" — if it's on your machine, the next `pis` has it.

Only one file is hand-curated: `AGENTS.md` (your sandbox standing instructions).
Everything else here is generated — edit the host originals instead of these
copies. `pis sync-config` forces a refresh; `PI_SANDBOX_NO_SYNC=1` disables the
automatic one (e.g. for controlled/CI runs).

## What's generated (edit the HOST originals, not these)

| Path | Source |
|---|---|
| `settings.json` | Host `~/.pi/agent/settings.json` + the two sandbox deltas below. Don't hand-edit — change the host file. |
| `keybindings.json` `mcp.json` `models.json` `SYSTEM.md` `APPEND_SYSTEM.md` | Host files, mirrored (removed on host → removed here). |
| `skills/` `prompts/` `extensions/` `themes/` | Host dirs, mirrored with deletion propagation (`sandbox.json`, pi-sbx's policy file, is skipped). |
| `AGENTS.md` | **Curated — this one is yours.** Auto-sync never touches it; `pis sync-config --with-agents` replaces it from the host on request. |

## What's generated elsewhere / never allowed

| Path | Rule |
|---|---|
| `npm/` | Pre-warm copy of installed pi packages (gitignored). Refreshed automatically. |
| `auth.json` | **Forbidden.** Auth is env-var passthrough only (see `docs/security.md`); `sync-config` asserts the overlay is clean and `seed-pi-home` deletes any auth.json in sandboxes (pi's empty `{}` startup stub included) — loudly warning if one held real credentials. |
| `sessions/` | Never synced — each sandbox keeps its own session history in its volume. |
| `.sync-stamp` | Machine-local change bookkeeping (gitignored) that makes the automatic sync a fast no-op when nothing changed. |

## Sync model

Automatic sync mirrors the host agent dir here, with these sandbox-only deltas
applied to `settings.json`:

1. `npm:pi-sbx` removed from `packages` — pi-sbx routed commands one at a time and
   prompted constantly (the friction that motivated this setup); inside the
   container everything already runs within the boundary. Re-add with
   `pis sync-config --keep-pi-sbx`.
2. `defaultProjectTrust: "always"` — unattended runs must not stop at trust prompts.

Mirror semantics: files removed on the host are removed here, so sandboxes never
load stale extensions. Host symlinks in `extensions/` etc. are skipped with a
warning on manual syncs (they would dangle inside containers) — copy the target
in here manually if a sandbox needs it. Edits here apply on the next `pis` — no
rebuild, no container restart.
