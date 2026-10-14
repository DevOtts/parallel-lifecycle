---
name: parallel-lifecycle
description: Run and CDP-test a feature inside its own git worktree without colliding with other parallel coding sessions. Use whenever you are testing a feature locally in a worktree, running Playwright/CDP against your own app, or running two or more agent sessions in parallel that each need a dev server and a browser. Trigger on "test this feature", "run the e2e", "test it in the browser", "test this worktree", "spin up the app and check it", or any local CDP/Playwright testing that is NOT driving your real, logged-in, anti-detection Chrome. Each worktree gets its own app port, ephemeral Chrome/CDP endpoint, and (planned) database behind a single .env.worktree contract.
version: 0.2.0
license: MIT
author: DevOtts
author_url: https://github.com/DevOtts
homepage: https://github.com/DevOtts/parallel-lifecycle
repository: https://github.com/DevOtts/parallel-lifecycle
metadata:
  platforms: [claude-code, cursor, codex, github-copilot, opencode, openclaw, windsurf, gemini-cli]
  category: "Dev Environment & Tooling"
---

# parallel-lifecycle

Give every git worktree its own isolated, disposable runtime, so N parallel coding sessions never fight over port 3000, the database, or the browser. Everything keys off one generated contract file, `.env.worktree`.

> **Claude Code** gets the full plugin: a `SessionStart` hook provisions each worktree automatically and a `SessionEnd` hook tears it down. On **every other tool**, this skill is the workflow and you run the provisioning script yourself (one command). The behavior is identical; only the auto-wiring differs.

## 0. Preflight (every session)

Confirm the worktree is provisioned:

```bash
test -f .env.worktree && cat .env.worktree || echo "NOT PROVISIONED"
```

If `NOT PROVISIONED` and you are inside a linked worktree
(`git rev-parse --git-dir` != `--git-common-dir`), provision it once:

```bash
bash worktree-bootstrap.sh        # the bundled Layer 0 script
```

Then load the contract before any dev/test command:

```bash
set -a; source .env.worktree; set +a
```

`.env.worktree` carries `APP_PORT` / `PORT`, `CDP_URL`, and `DATABASE_URL`. Ports
are deterministic free ports, written once — never auto-incremented (that
silently points the test harness at the wrong URL).

## 1. Pick the browser model

| Situation | Model | What to do |
|---|---|---|
| Testing your own app | 1 (default) | Use the worktree's ephemeral Chrome on `$CDP_URL`. Fully parallel. |
| Must use the real logged-in / anti-detection Chrome | 3 (serialize) | Drive it through your real-Chrome flow AND wrap the run in `flock /tmp/cdp-9222.lock` so only one session uses it at a time. |

## 2. Run the app on the worktree's port

```bash
npm run dev                                   # framework reads PORT from env
until curl -sf "http://127.0.0.1:$PORT" >/dev/null; do sleep 0.5; done
```

## 3. Drive the worktree's Chrome (not :9222)

Connect over CDP to `$CDP_URL`. The repo ships a Playwright helper
(`connect.py`) that reads the contract and returns a page. For authenticated
flows, inject a saved Playwright `storageState` — never the real profile.

## 4. Cleanup

On Claude Code, teardown is automatic on `SessionEnd`. Otherwise:

```bash
bash worktree-teardown.sh
git worktree remove "$(git rev-parse --show-toplevel)"   # once merged or binned
```

## Isolation driver contract

For orchestrators (such as do-it, via its `isolation` setting) the same machinery is callable as a driver with exactly three operations. `isolation.sh` ships at `plugins/parallel-lifecycle/skills/parallel-lifecycle/scripts/isolation.sh`:

| Operation | Does | Prints |
|---|---|---|
| `create <slice> [--base <ref>]` | make an isolated checkout (branch `feat/<slice>`) and provision its runtime; idempotent | its absolute path |
| `remove <slice> [--force]` | tear the runtime down, then remove the checkout | nothing |
| `path <slice>` | look up the slice's checkout | its absolute path (exit 1 if none) |

Checkouts live in `$PL_ISOLATION_ROOT` (default `<repo>-worktrees/`). Stdout carries only the path; progress goes to stderr. Exit codes: 0 ok, 1 failure or not found, 2 usage. do-it's default driver is plain git worktrees; this one adds the per-worktree runtime.

## Hard rules

- Never hardcode a port. Read `$PORT` / `$CDP_URL` from `.env.worktree`.
- Never connect to `:9222` from the default flow; that browser is the real one.
- Never run two sessions against the same database without isolation or a lock.
- Never copy the real Chrome profile into a worktree; use `storageState`.
- Never commit `.env.worktree` or `.wt/`.

Full design and per-tool install: https://github.com/DevOtts/parallel-lifecycle

---
_Authored by [DevOtts](https://github.com/DevOtts)._
