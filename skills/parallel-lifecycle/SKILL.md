---
name: parallel-lifecycle
description: Run and CDP-test a feature inside its own git worktree without colliding with other parallel coding sessions. Use this whenever you are testing a feature locally in a worktree, running Playwright/CDP against your own app, or running two or more sessions in parallel that each need a dev server and a browser. Trigger on "test this feature", "run the e2e", "test it in the browser", "test this worktree", "spin up the app and check it", or any local CDP/Playwright testing that is NOT driving your real, logged-in, anti-detection Chrome. For that real-browser case (posting to a logged-in site, bot-hostile third-party sites), use your dedicated real-Chrome automation flow instead. This skill assumes the worktree-bootstrap.sh SessionStart hook has already provisioned per-worktree ports and an ephemeral Chrome; if it has not, this skill installs/repairs that first.
author: DevOtts
author_url: https://github.com/DevOtts
---

# Parallel lifecycle: worktree test isolation

Test a feature in its own worktree against that worktree's own app, port, and browser, so N parallel sessions never fight over port 3000 or Chrome.

This is the "model 1" browser: an isolated, throwaway Chrome per worktree. It is a different tool from your real-browser automation flow, which drives the one real logged-in Chrome on `:9222` under manual supervision. Do not connect to `:9222` from here.

The mechanical isolation (allocate ports, launch the ephemeral Chrome, write the contract file) is provided by the Layer 0 `worktree-bootstrap.sh` hook. This skill is the workflow that rides on top of the contract it produces. See `docs/architecture.md` for the layering.

---

## 0. Preflight (every session)

Confirm the bootstrap hook provisioned this worktree:

```bash
test -f .env.worktree && cat .env.worktree || echo "NOT PROVISIONED"
```

If `NOT PROVISIONED` and you are inside a worktree (`git rev-parse --git-dir` != `--git-common-dir`), the hook did not run. Run it once by hand, then continue:

```bash
bash "${CLAUDE_PLUGIN_ROOT:-.}"/hooks/worktree-bootstrap.sh
```

If it is still empty, the hook is not installed. See `docs/installation.md` and stop until it is wired into settings, otherwise every session will keep colliding.

Load the contract into the shell before any dev/test command:

```bash
set -a; source .env.worktree; set +a
```

---

## 1. Pick the model before you touch a browser

| Situation | Model | What to do |
|---|---|---|
| Testing your own app | 1 (this skill) | Use the worktree's ephemeral Chrome on `$CDP_URL`. Fully parallel. |
| Must use the real logged-in / anti-detection Chrome | 3 (serialize) | Defer to your real-Chrome automation flow AND wrap the run in a lock (section 5) so only one session drives `:9222` at a time. |
| Two sessions, both need the real Chrome at once | not possible | Serialize. The real browser is a resource of one. |

Default is model 1. Only fall to model 3 when the test genuinely needs your authenticated real profile against a bot-hostile site.

---

## 2. Start the app on the worktree's port

Never hardcode 3000. Always use `$PORT` from the contract:

```bash
set -a; source .env.worktree; set +a
npm run dev            # framework reads PORT from env
# or explicit: npm run dev -- --port "$PORT"   (Vite)
#              next dev -p "$PORT"              (Next)
```

Wait for it to be reachable before testing:

```bash
until curl -sf "http://127.0.0.1:$PORT" >/dev/null; do sleep 0.5; done
```

---

## 3. Connect to the worktree's Chrome, not :9222

Use the bundled helper, which reads `$CDP_URL` from `.env.worktree`:

```bash
python3 scripts/connect.py      # smoke test
```

For real tests, import it:

```python
from scripts.connect import get_page
pw, browser, ctx, page = await get_page(auth_state="~/.config/wt-auth/app.json")
# ... drive page ...
await pw.stop()
```

Use stable selectors (roles, test ids, accessible names), wait on conditions instead of sleeping, and treat each connection as stateless. Do not invent new selector patterns per test.

---

## 4. Authenticated flows (without sharing the real profile)

The ephemeral Chrome starts logged out. Inject a saved `storageState` instead of pointing tests at the real profile.

One-time export, done through your REAL Chrome (via your real-Chrome automation flow) while you are logged in:

```python
# against the real, logged-in browser on :9222
state = await ctx.storage_state()
import json, pathlib
p = pathlib.Path.home() / ".config/wt-auth/app.json"
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text(json.dumps(state))
```

Then every worktree test loads it via `get_page(auth_state=...)`. Refresh the file when the session expires. Never copy the real `--user-data-dir` into a worktree.

---

## 5. Model 3: serialize the one real browser

When a test must use `:9222`, prevent two sessions from driving it at once:

```bash
flock /tmp/cdp-9222.lock -c 'python3 run_e2e.py'
```

Code generation and the dev servers stay parallel across worktrees; only the browser step is serialized behind the lock. This is the pragmatic default whenever the real authenticated Chrome is required.

---

## 6. Database isolation

If two worktrees hit the same local DB, browser isolation buys nothing: writes from one test corrupt reads in the other. A future release provisions a per-worktree database automatically (detection-first, one database per worktree). Until then, isolate the DB yourself for any feature whose tests write to the database, or serialize the DB-touching tests behind a lock like section 5. See `docs/architecture.md` for the planned model.

---

## 7. Cleanup

Teardown is automatic on SessionEnd (kills this worktree's ephemeral Chrome). To clean up by hand:

```bash
bash "${CLAUDE_PLUGIN_ROOT:-.}"/hooks/worktree-teardown.sh
```

Then remove the worktree itself with git once the branch is merged or binned:

```bash
git worktree remove "$(git rev-parse --show-toplevel)"
```

Stale ephemeral Chromes are the main resource leak here. If `ps aux | grep remote-debugging-port` shows orphans from removed worktrees, kill them.

---

## 8. Hard rules

- Never connect to `:9222` from this skill. That browser belongs to your supervised real-Chrome flow.
- Never hardcode 3000 (or any port). Read `$PORT` / `$CDP_URL` from `.env.worktree`.
- Never run two sessions against the same DB without isolation or a lock.
- Never copy the real Chrome profile into a worktree. Use `storageState`.
- Never commit `.env.worktree` or `.wt/`. They are per-machine, per-worktree.
- Always preflight (section 0) and source the contract before dev/test commands.
- Default to model 1; fall to model 3 (serialize) only when the real authenticated browser is genuinely required.

---
_Authored by [DevOtts](https://github.com/DevOtts)._
