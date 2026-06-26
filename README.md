# parallel-lifecycle

A [Claude Code](https://www.claude.com/product/claude-code) plugin that gives every git worktree its own isolated, disposable environment, so you can run many parallel coding sessions without them colliding.

Run N sessions, one per worktree, and each gets its own app port, its own ephemeral Chrome/CDP endpoint, and (planned) its own database, all behind a single `.env.worktree` contract file. No more two sessions fighting over port 3000 or the one browser.

## The problem

If you run multiple agentic coding sessions in parallel, each in its own git worktree, the worktrees isolate your *files* but nothing else. Every session still wants port 3000, the same local database, and the same browser. They overwrite each other's dev servers, corrupt each other's test data, and serialize on a single Chrome. Most "isolation" setups also auto-increment ports ("3000 busy, use 3001"), which silently points your test harness at the wrong URL so it tests nothing.

## The approach

A thin, layered substrate with one contract between the layers:

| Layer | Owns | Form |
|---|---|---|
| 0. Provisioning | ports, ephemeral Chrome, (planned) per-worktree DB, lifecycle | hooks (deterministic, no model discretion) |
| 1. Contract | `.env.worktree`: `APP_PORT`, `CDP_URL`, `DATABASE_URL` | one file, the thin waist |
| 2. Capabilities | run the app, run tests, drive the browser | read the contract, never hardcode |

A `SessionStart` hook detects when you're in a linked worktree and provisions deterministic free ports plus a throwaway Chrome bound to its own debugging port. It writes everything to `.env.worktree`. Your app and your tests read that one file. A `SessionEnd` hook tears down the ephemeral Chrome. See [docs/architecture.md](docs/architecture.md) for the full design and the rationale behind each decision.

## Install

Add the marketplace and install the plugin:

```
/plugin marketplace add DevOtts/parallel-lifecycle
/plugin install parallel-lifecycle@parallel-lifecycle
```

The plugin ships the provisioning hooks; they activate automatically and no-op outside a linked worktree, so they are safe to leave enabled everywhere. For manual installation (or to register the hooks without the plugin), see [docs/installation.md](docs/installation.md).

## Quick start

From inside a linked git worktree:

```bash
# 1. The SessionStart hook has already written the contract. Load it:
set -a; source .env.worktree; set +a

# 2. Start your app on the worktree's port (never hardcode 3000):
npm run dev          # frameworks read PORT from the environment

# 3. Drive the worktree's own Chrome over CDP:
python3 scripts/connect.py
```

Open a second worktree and repeat: it gets different ports and a separate Chrome. The two never collide. See [docs/usage.md](docs/usage.md) for authenticated flows, serializing the real browser, and cleanup.

## Status

This is an early release (`0.1.0`). Implemented today: per-worktree app port and ephemeral Chrome/CDP isolation behind the contract file. Planned: automatic, stack-detected per-worktree database isolation, and capability skills that read the contract directly. See [docs/architecture.md](docs/architecture.md#roadmap).

## License

MIT. See [LICENSE](LICENSE).

---

Built by [DevOtts](https://github.com/DevOtts).
