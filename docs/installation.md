# Installation

## Recommended: as a plugin

```
/plugin marketplace add DevOtts/parallel-lifecycle
/plugin install parallel-lifecycle@parallel-lifecycle
```

The plugin bundles the provisioning hooks and registers them automatically. They
no-op outside a linked git worktree, so they are safe to leave enabled in every
project.

## Manual: register the hooks yourself

If you want the hooks active without installing the plugin (for example, to have
them load in every repo regardless of plugin scope), copy the scripts and
register them in your Claude Code settings.

1. Copy the two scripts somewhere stable and make them executable:

   ```bash
   mkdir -p ~/.claude/hooks
   cp hooks/worktree-bootstrap.sh hooks/worktree-teardown.sh ~/.claude/hooks/
   chmod +x ~/.claude/hooks/worktree-bootstrap.sh ~/.claude/hooks/worktree-teardown.sh
   ```

2. Register them in your settings (`~/.claude/settings.json` or a project
   `.claude/settings.json`). **Merge** these entries into any existing `hooks`
   block; do not overwrite it.

   ```json
   {
     "hooks": {
       "SessionStart": [
         { "matcher": "startup|resume", "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/worktree-bootstrap.sh" } ] }
       ],
       "SessionEnd": [
         { "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/worktree-teardown.sh" } ] }
       ]
     }
   }
   ```

   Hook event names have shifted across Claude Code versions. If
   `SessionStart`/`SessionEnd` are not honored on your version, check the current
   event names in the docs.

## Per-repo gitignore

In every repo where you use this, ignore the generated state:

```
.env.worktree
.wt/
```

## Dependencies

- **Node.js** — the bootstrap allocates free ports with Node's `net` module
  (already present if you run JS apps).
- **A Chrome/Chromium binary** — the hook launches an ephemeral instance. On
  macOS it defaults to Google Chrome; on Linux, set `WT_CHROME` to your binary
  (e.g. `/usr/bin/google-chrome`).
- **Playwright (Python)** for the bundled CDP helper:

  ```bash
  pip3 install playwright
  ```

  The helper connects to the Chrome the hook already launched, so you do **not**
  need `playwright install chromium` unless you also launch Playwright's own
  bundled browser.

## Verify

From inside a linked worktree:

```bash
bash hooks/worktree-bootstrap.sh
cat .env.worktree
set -a; source .env.worktree; set +a
curl -s "$CDP_URL/json/version"     # the worktree's own Chrome answers
```

Two parallel worktrees should show different `APP_PORT` / `CDP_PORT` and two
separate Chrome processes (`ps aux | grep remote-debugging-port`).
