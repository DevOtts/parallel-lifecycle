#!/usr/bin/env bash
# worktree-teardown.sh  (parallel-lifecycle, Layer 0)
#
# Fires on SessionEnd (and is safe to call from a WorktreeRemove hook).
# Kills the ephemeral Chrome this worktree owns. No-op outside a worktree or
# if nothing was provisioned.
#
# Note: the database (when enabled) lives on the BRANCH clock, not the session
# clock. It is intentionally NOT dropped here, only on worktree-remove, so
# closing the laptop never nukes seed data mid-branch.

set -euo pipefail

WT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
STATE_FILE="$WT_ROOT/.wt/state"
[ -f "$STATE_FILE" ] || exit 0

# shellcheck disable=SC1090
source "$STATE_FILE"

if [ -n "${CDP_PID:-}" ] && kill -0 "$CDP_PID" 2>/dev/null; then
  kill "$CDP_PID" 2>/dev/null || true
fi

rm -f "$STATE_FILE"
echo "[worktree-teardown] cleaned up $(basename "$WT_ROOT")"
