# Usage

Everything keys off one generated file, `.env.worktree`, written by the
`SessionStart` hook when you are inside a linked worktree.

## Every session: preflight

```bash
test -f .env.worktree && cat .env.worktree || echo "NOT PROVISIONED"
```

If it says `NOT PROVISIONED` and you are in a worktree, run the bootstrap once by
hand, then load the contract:

```bash
worktree-bootstrap.sh        # the bundled Layer 0 provisioner
set -a; source .env.worktree; set +a
```

## Run the app on the worktree's port

Never hardcode 3000. Read `$PORT`:

```bash
npm run dev                       # framework reads PORT from env
# or: npm run dev -- --port "$PORT"   (Vite)
#     next dev -p "$PORT"             (Next)

until curl -sf "http://127.0.0.1:$PORT" >/dev/null; do sleep 0.5; done
```

## Drive the worktree's browser

The bundled helper reads `$CDP_URL` and connects to this worktree's Chrome:

```bash
python3 connect.py        # smoke test: prints the app title
```

In your own tests:

```python
from scripts.connect import get_page
pw, browser, ctx, page = await get_page(auth_state="~/.config/wt-auth/app.json")
# ... drive page ...
await pw.stop()
```

## Authenticated flows without sharing your real profile

The ephemeral Chrome starts logged out. Export a `storageState` once from your
real, logged-in browser, then inject it into worktree tests:

```python
# against your real logged-in browser
state = await ctx.storage_state()
import json, pathlib
p = pathlib.Path.home() / ".config/wt-auth/app.json"
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text(json.dumps(state))
```

Refresh it when the session expires. Never copy the real `--user-data-dir` into a
worktree.

## When a test needs the real browser

Some tests genuinely need your real, logged-in, anti-detection Chrome (on
`:9222`). That browser is a resource of one. Serialize it with a file lock so two
sessions never drive it at once:

```bash
flock /tmp/cdp-9222.lock -c 'python3 run_e2e.py'
```

Only the browser step serializes; code generation and dev servers stay parallel.

## Database

If two worktrees write to the same local database, browser isolation buys you
nothing. Until automatic per-worktree database provisioning ships, isolate the
database yourself, or serialize the database-touching tests behind a lock like
the one above. See [architecture.md](architecture.md#database-isolation-planned).

## Cleanup

Teardown runs automatically on `SessionEnd` and kills this worktree's ephemeral
Chrome. By hand:

```bash
worktree-teardown.sh
git worktree remove "$(git rev-parse --show-toplevel)"   # once merged or binned
```

Stale ephemeral Chromes are the main resource leak. If
`ps aux | grep remote-debugging-port` shows orphans from removed worktrees, kill
them.

## Hard rules

- Never connect to `:9222` from the default flow; that browser is for your
  supervised real-Chrome automation.
- Never hardcode a port. Read `$PORT` / `$CDP_URL` from `.env.worktree`.
- Never run two sessions against the same database without isolation or a lock.
- Never copy the real Chrome profile into a worktree; use `storageState`.
- Never commit `.env.worktree` or `.wt/`.
