# Sandbox operating instructions

These instructions apply to every pi sandbox started with `pis` (pi-sandbox-local marker).
They are the user-level AGENTS.md from the sandbox agent directory; project AGENTS.md
files in `/workspace` layer on top and take precedence for project-specific detail.

## Where you are

- You run inside a Docker sandbox. `/workspace` is the mounted working repo —
  writes there sync to the host immediately.
- You have the full toolset with **zero approval prompts**: act decisively instead
  of asking for permission. The container boundary is the safety net; nothing you
  do inside it can affect the host beyond the mounted repo.
- There is no host machine access, no host home directory, and no credentials on
  disk. The model credential arrives as process environment and must never be
  written to a file.

## How to work

- Prefer `mise` for any toolchain you need (`mise use`, `mise install`); the
  environment already provides node, JDK 21 (android sandbox), git, ripgrep, fd,
  jq, build tools. There is no sudo — stay inside the provisioned toolset.
- Verify before you claim done: build, run the project's tests, and report the
  exact commands and outcomes. Never summarize a change as working without
  evidence.
- On Android repos, end-to-end tests run through the emulator and are already
  wired up: `./scripts/run-tests.sh` (optionally with a test class filter). The
  AVD boots headless in 1–2 minutes; be patient rather than killing it. On
  failure, crash logs are captured automatically under `test-results/`.
- On web repos, browser e2e runs through Playwright with pre-installed Chromium.
  Launch it with `chromiumSandbox: false` — the container is the sandbox.
- Keep long-running output tidy (tail, summarize); you cannot scroll a terminal
  you don't control.
- If you get stuck on environment issues, run `mise`, `java -version`,
  `node --version`, `adb devices`, or `emulator -accel-check` to diagnose rather
  than guessing.

## Finishing up

- End with a short summary: what changed, how it was verified, what remains.
- Leave the repo clean: no stray scratch files at the repo root; put temporary
  artifacts under `test-results/` or delete them.
