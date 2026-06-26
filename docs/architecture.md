# Architecture

The goal is to let N coding sessions build features in parallel, one per git
worktree, end to end, without colliding, and converge cleanly back to `main`.

Git worktrees isolate file edits. They do nothing about runtime resources: the
dev server port, the local database, and the browser. parallel-lifecycle adds a
thin substrate that isolates those, with one contract file between the moving
parts.

## Layers

| Layer | Owns | Form |
|---|---|---|
| 0. Provisioning | ports, ephemeral Chrome, per-worktree DB (planned), lifecycle | hooks: deterministic, zero model discretion |
| 1. Contract | `.env.worktree` | one file, the thin waist |
| 2. Capabilities | run the app, run tests, drive the browser | read the contract, never hardcode |

The load-bearing idea: capabilities stop knowing about worktrees. A test runner
reads `$CDP_URL` and `$PORT` from the contract and is done. It does not overlap
with the isolation logic, because it contains none. Single responsibility per
component, one shared contract, no duplicated environment assumptions.

## Why provisioning is a hook, not a skill

Mechanical isolation (allocate ports, write the contract, launch Chrome) must
fire **every time**, with no discretion. A prose instruction a model reads is
something a model can skip or forget, which is the original non-determinism bug.
So provisioning lives in a `SessionStart` hook. Judgment and workflow (which
browser model to use, how to authenticate, when to serialize) live in a skill
that assumes the environment already exists.

The hook no-ops unless the session's working directory is a **linked** worktree.
It detects this by comparing `git rev-parse --git-dir` with `--git-common-dir`:
they are equal in the main checkout and differ in a linked worktree. That makes
it safe to register globally.

`SessionStart` was chosen over a worktree-creation hook because, in current
Claude Code, a `WorktreeCreate` hook *replaces* git's own worktree creation,
which would force you to reimplement branch-from-origin, base-ref, and
branch-from-PR logic. `SessionStart` avoids all of that.

## The contract (`.env.worktree`)

One generated file is the single source of truth. Nothing above it re-derives
ports or endpoints.

```
APP_PORT=<free port>
PORT=<same as APP_PORT>
CDP_URL=http://127.0.0.1:<free port>
DATABASE_URL=postgres://.../app   # planned; see DB isolation
WT_NAME=<worktree dir name>
```

Ports are deterministic free ports written once, not auto-incremented. Auto
increment ("3000 busy, use 3001") is rejected: the test harness then points at
the wrong URL and silently tests nothing. The app and the tests both read this
file, so they always agree on where the app and the browser are.

## The two browser models

1. **Ephemeral (default).** A throwaway Chrome per worktree with its own
   `--user-data-dir` and debugging port, launched headless by the hook. Used for
   testing your own apps. Fully parallel. It starts logged out; for
   authenticated flows you inject a saved Playwright `storageState`, never the
   real profile.
2. **The real browser (serialize).** When a test genuinely needs your real,
   logged-in, anti-detection Chrome (bot-hostile third-party sites), that
   browser is a resource of one. Drive it through your dedicated real-Chrome
   automation flow and wrap the browser step in a file lock
   (`flock /tmp/cdp-9222.lock`) so only one session uses it at a time. Code
   generation and dev servers stay parallel; only the browser step serializes.

A third option (two sessions sharing one browser via scoped tabs) was considered
and rejected as too fragile for autonomous use.

## Lifecycle clocks

Different resources live on different clocks. Conflating them causes data loss.

- **Session clock.** Cheap-to-rebuild resources (the ephemeral Chrome, the port)
  are created on `SessionStart` and killed on `SessionEnd`.
- **Branch clock.** The database (when enabled) is created once at provision and
  dropped only on worktree-remove or merge. Dropping it on `SessionEnd` would
  nuke seed data every time you close the laptop, and risk dropping it mid-run.

This is why teardown kills Chrome but never touches the database.

## Database isolation (planned)

There is no fixed engine. The substrate is generic: the stack is whatever the
target project uses. A future release scans the codebase (web framework, DB
engine, how the app reads its connection string), caches a stack profile, and
provisions DB isolation from it. Never hardcoded to one engine.

Default model: one shared DB server, one **database** per worktree (logical
isolation, near-zero cost, scales to many worktrees). Escalate to a container
per worktree only when a branch changes the engine, version, or extensions.
Schema-per-worktree is rejected: it is fragile if any query hardcodes a schema
prefix.

Per-engine clone mechanisms differ. Postgres can clone the local database
near-instantly with `CREATE DATABASE wt_<slug> TEMPLATE <local_db>`. Engines
without templates dump-and-restore once, or create the namespaced database lazily
and run the project's seed script.

Scaling caveat: many parallel apps plus test runners against one Postgres can
exhaust `max_connections` (default 100). Cap each app's pool, raise
`max_connections`, or front it with a pooler. The practical ceiling is around 15
parallel worktrees before connection limits bite.

### Create vs seed

Provisioning creates the empty namespaced database and writes `DATABASE_URL`.
The project's own init/seed step sources the contract and runs migrations and
seeds against `$DATABASE_URL`. Migrations are project-specific and stay out of
the global hook.

## Roadmap

- **0.1 (now):** Layer 0 + Layer 1. Per-worktree app port and ephemeral
  Chrome/CDP isolation behind `.env.worktree`. Proven across parallel worktrees.
- **Next:** stack detection + cached stack profile + per-worktree database
  provisioning (Postgres database-per-worktree first, other engines after).
- **Later:** capability skills (app-run, test runners) that read the contract
  directly; fleet and merge-state tracking to converge many branches back to
  `main`.
