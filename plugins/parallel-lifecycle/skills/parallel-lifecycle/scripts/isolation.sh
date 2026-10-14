#!/usr/bin/env bash
# isolation.sh  (parallel-lifecycle, isolation driver contract)
#
# Three operations, nothing else. A caller (do-it, or you) selects this driver
# and never needs to know how the checkout or runtime is made.
#
#   isolation.sh create <slice> [--base <ref>]   make an isolated checkout + runtime, print its absolute path
#   isolation.sh remove <slice> [--force]        tear the runtime down, then remove the checkout
#   isolation.sh path   <slice>                  print the absolute path of the slice's checkout
#
# <slice> is an id matching [A-Za-z0-9._-]+; it names the branch (feat/<slice>)
# and the directory. Run from inside any checkout of the repo. Checkouts live in
# $PL_ISOLATION_ROOT (default: <main checkout>-worktrees/ next to the repo).
# Exit codes: 0 ok, 1 failure or not found, 2 usage. Stdout carries only the path.

set -euo pipefail

usage() { echo "usage: isolation.sh create <slice> [--base <ref>] | remove <slice> [--force] | path <slice>" >&2; exit 2; }

[ $# -ge 2 ] || usage
op=$1; slice=$2; shift 2
case "$slice" in *[!A-Za-z0-9._-]*|""|.|..) echo "isolation: invalid slice id '$slice'" >&2; exit 2;; esac

common=$(git rev-parse --path-format=absolute --git-common-dir)
main=$(cd "$(dirname "$common")" && pwd -P)
root="${PL_ISOLATION_ROOT:-$main-worktrees}"
mkdir -p "$root"
root=$(cd "$root" && pwd -P)   # git lists physical paths; match them
target="$root/$slice"
hooks="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../hooks" && pwd)"

registered() { git worktree list --porcelain | grep -Fxq "worktree $target"; }

case "$op" in
  create)
    base=HEAD
    if [ "${1:-}" = "--base" ]; then [ -n "${2:-}" ] || usage; base=$2; fi
    if registered; then echo "$target"; exit 0; fi   # idempotent
    git worktree add -b "feat/$slice" "$target" "$base" >&2
    (cd "$target" && bash "$hooks/worktree-bootstrap.sh") >&2
    echo "$target"
    ;;
  path)
    registered || { echo "isolation: no checkout for slice '$slice'" >&2; exit 1; }
    echo "$target"
    ;;
  remove)
    registered || { echo "isolation: no checkout for slice '$slice'" >&2; exit 1; }
    (cd "$target" && bash "$hooks/worktree-teardown.sh") >&2 || true
    rm -rf "$target/.wt" "$target/.env.worktree"
    if [ "${1:-}" = "--force" ]; then git worktree remove --force "$target"; else git worktree remove "$target"; fi
    ;;
  *) usage;;
esac
