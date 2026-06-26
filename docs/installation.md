# Installation

`parallel-lifecycle` has two install paths: the **Claude Code plugin** (hooks
auto-provision every worktree) and the **portable skill + bash substrate** (any
other agent, or no agent at all).

## Claude Code — native, auto-provisioning

```
/plugin marketplace add DevOtts/parallel-lifecycle
/plugin install parallel-lifecycle@parallel-lifecycle
```

The plugin bundles `SessionStart` / `SessionEnd` hooks and registers them
automatically. They no-op outside a linked git worktree, so they're safe to
leave enabled in every project. You never run a setup command.

## Any other agent — the portable skill

The universal installers understand the `SKILL.md` standard and place the skill
where your tool reads it:

```sh
npx skills add DevOtts/parallel-lifecycle -a <agent>   # -a cursor | codex | github-copilot | … ; -g for global
gh skill install DevOtts/parallel-lifecycle
```

List supported agents with `npx skills add DevOtts/parallel-lifecycle --list`.
These tools have no deterministic session hook, so you provision each worktree
yourself with the bundled script (next section).

## Manual provisioning (any tool, or a real git hook)

The provisioning layer is plain bash keyed off `git worktree`. Copy the two
scripts somewhere on your `PATH`:

```sh
git clone https://github.com/DevOtts/parallel-lifecycle /tmp/pl
cp /tmp/pl/plugins/parallel-lifecycle/hooks/worktree-bootstrap.sh \
   /tmp/pl/plugins/parallel-lifecycle/hooks/worktree-teardown.sh ~/.local/bin/
chmod +x ~/.local/bin/worktree-*.sh
```

Then either call `worktree-bootstrap.sh` whenever you enter a worktree, or wire
it into a hook so it's automatic:

- **git hook** — call it from `.git/hooks/post-checkout` (fires on worktree add).
- **direnv** — add `worktree-bootstrap.sh` to the worktree's `.envrc`.
- **Makefile / shell alias** — `make dev` runs it before starting the app.

### Registering it as a Claude Code hook by hand

If you want the auto-provisioning without installing the plugin (for example to
have it active in every repo), register the scripts in your settings. **Merge**
into any existing `hooks` block; do not overwrite it.

```json
{
  "hooks": {
    "SessionStart": [
      { "matcher": "startup|resume", "hooks": [ { "type": "command", "command": "bash ~/.local/bin/worktree-bootstrap.sh" } ] }
    ],
    "SessionEnd": [
      { "hooks": [ { "type": "command", "command": "bash ~/.local/bin/worktree-teardown.sh" } ] }
    ]
  }
}
```

Hook event names have shifted across Claude Code versions; if `SessionStart` /
`SessionEnd` aren't honored on yours, check the current event names in the docs.

## Per-repo gitignore

In every repo where you use this, ignore the generated state:

```
.env.worktree
.wt/
```

## Dependencies

- **Node.js** — the bootstrap allocates free ports with Node's `net` module
  (already present if you run JS apps).
- **A Chrome/Chromium binary** — the hook launches an ephemeral instance. macOS
  uses Google Chrome by default; on Linux set `WT_CHROME` to your binary (e.g.
  `/usr/bin/google-chrome`). Toggle a visible window with `WT_HEADED=1`.
- **Playwright (Python)** for the bundled CDP helper:

  ```sh
  pip3 install playwright
  ```

  It connects to the Chrome the hook already launched, so you do **not** need
  `playwright install chromium` for the CDP path.

## Verify

From inside a linked worktree:

```bash
worktree-bootstrap.sh
cat .env.worktree
set -a; source .env.worktree; set +a
curl -s "$CDP_URL/json/version"     # the worktree's own Chrome answers
```

Two parallel worktrees should show different `APP_PORT` / `CDP_PORT` and two
separate Chrome processes (`ps aux | grep remote-debugging-port`).
