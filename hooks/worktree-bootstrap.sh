#!/usr/bin/env bash
# worktree-bootstrap.sh  (parallel-lifecycle, Layer 0)
#
# Fires on SessionStart. No-op unless the session's cwd is a LINKED git
# worktree (not the main checkout). When it is, it provisions isolated,
# per-worktree resources so two parallel coding sessions never collide:
#
#   - a unique app port            (PORT / APP_PORT)
#   - a unique CDP port + an ephemeral Chrome bound to it (CDP_URL)
#   - a unique DB port             (DB_PORT / DATABASE_URL)  [optional, see step 5]
#
# Values land in $WT_ROOT/.env.worktree (app + tests read this).
# Runtime PIDs land in $WT_ROOT/.wt/state (teardown reads this).
#
# Idempotent: re-running for the same worktree reuses ports and skips relaunch
# while the Chrome process is still alive (SessionStart can fire on resume).
#
# Defaults target macOS. For Linux, set CHROME to your binary (see step 4).

set -euo pipefail

# 1. Run only inside a linked worktree -------------------------------------
git_dir=$(git rev-parse --git-dir 2>/dev/null)        || exit 0
common_dir=$(git rev-parse --git-common-dir 2>/dev/null) || exit 0
# Main worktree: these resolve equal. Linked worktree: they differ.
[ "$git_dir" = "$common_dir" ] && exit 0

WT_ROOT=$(git rev-parse --show-toplevel)
WT_NAME=$(basename "$WT_ROOT")
ENV_FILE="$WT_ROOT/.env.worktree"
STATE_DIR="$WT_ROOT/.wt"
STATE_FILE="$STATE_DIR/state"
mkdir -p "$STATE_DIR"

free_port() {
  node -e 'const s=require("net").createServer();s.listen(0,"127.0.0.1",()=>{console.log(s.address().port);s.close()})'
}

# 2. Idempotency: provisioned already and Chrome still alive? ---------------
if [ -f "$STATE_FILE" ]; then
  # shellcheck disable=SC1090
  source "$STATE_FILE"
  if [ -n "${CDP_PID:-}" ] && kill -0 "$CDP_PID" 2>/dev/null; then
    echo "[worktree-bootstrap] $WT_NAME already up: APP=$APP_PORT CDP=$CDP_PORT DB=$DB_PORT"
    exit 0
  fi
fi

# 3. Allocate ports --------------------------------------------------------
APP_PORT=$(free_port)
CDP_PORT=$(free_port)
DB_PORT=$(free_port)

# 4. Ephemeral Chrome for CDP ----------------------------------------------
# This is an ISOLATED, throwaway Chrome with its own profile dir. It is NOT
# the real logged-in browser you drive manually for authenticated, bot-hostile
# sites. For testing your own apps that distinction does not matter; for auth,
# inject a saved Playwright storageState in the test (see the skill), do not
# share the real profile.
#
# Linux: set CHROME to e.g. /usr/bin/google-chrome or /usr/bin/chromium.
CHROME="${WT_CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
CHROME_PROFILE="$STATE_DIR/chrome"
HEADLESS_FLAG="--headless=new"
[ "${WT_HEADED:-0}" = "1" ] && HEADLESS_FLAG=""

"$CHROME" \
  --remote-debugging-port="$CDP_PORT" \
  --user-data-dir="$CHROME_PROFILE" \
  --remote-allow-origins='*' \
  --no-first-run --no-default-browser-check \
  $HEADLESS_FLAG \
  about:blank >/dev/null 2>&1 &
CDP_PID=$!

# 5. Optional: isolated DB per worktree ------------------------------------
# Disabled by default. A future release detects the project's stack and
# provisions a database per worktree automatically (one shared server, one
# database per worktree). Until then, uncomment and adapt to your stack. A
# compose project (or container name) keyed to the worktree namespaces
# containers, networks and volumes so two worktrees never share a database.
# Without this, browser isolation is pointless: test A's writes corrupt test
# B's reads.
#
# DB_CONTAINER="db-$WT_NAME"
# docker run -d --rm --name "$DB_CONTAINER" \
#   -e POSTGRES_PASSWORD=dev -e POSTGRES_DB=app \
#   -p "$DB_PORT:5432" postgres:16 >/dev/null
# # or: COMPOSE_PROJECT_NAME="$WT_NAME" docker compose up -d

# 6. Persist ---------------------------------------------------------------
cat > "$ENV_FILE" <<EOF
# Auto-generated per worktree. Do not commit. Load before dev/test:
#   set -a; source .env.worktree; set +a
APP_PORT=$APP_PORT
PORT=$APP_PORT
CDP_PORT=$CDP_PORT
CDP_URL=http://127.0.0.1:$CDP_PORT
DB_PORT=$DB_PORT
DATABASE_URL=postgres://postgres:dev@127.0.0.1:$DB_PORT/app
WT_NAME=$WT_NAME
EOF

cat > "$STATE_FILE" <<EOF
APP_PORT=$APP_PORT
CDP_PORT=$CDP_PORT
DB_PORT=$DB_PORT
CDP_PID=$CDP_PID
# DB_CONTAINER=db-$WT_NAME
EOF

echo "[worktree-bootstrap] $WT_NAME -> APP=$APP_PORT CDP=$CDP_PORT DB=$DB_PORT (chrome pid $CDP_PID)"
