#!/usr/bin/env python3
"""
connect.py - open the worktree's own Chrome over CDP and hand back a page.

Reads CDP_URL from .env.worktree (provisioned by worktree-bootstrap.sh), so it
always targets THIS worktree's ephemeral Chrome, never :9222 (the real
logged-in browser you drive manually for authenticated, bot-hostile sites).
Optionally loads a saved storageState so authenticated flows work without
sharing the real profile.

Usage:
    python3 scripts/connect.py            # smoke test: print app title
    # or import get_page() into your own test
"""
import os
import sys
import asyncio
from pathlib import Path
from playwright.async_api import async_playwright


def _load_env():
    env = {}
    f = Path(".env.worktree")
    if not f.exists():
        sys.exit("No .env.worktree. Is this a worktree, and did SessionStart run the bootstrap hook?")
    for line in f.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        env[k] = v
    return env


async def get_page(auth_state: str | None = None):
    """Connect to the worktree Chrome and return (pw, browser, ctx, page)."""
    env = _load_env()
    cdp_url = env["CDP_URL"]
    app_url = f"http://127.0.0.1:{env['APP_PORT']}"

    pw = await async_playwright().start()
    browser = await pw.chromium.connect_over_cdp(cdp_url)

    # storageState cannot be applied to an existing CDP context, so for
    # authenticated runs create a fresh context from the saved cookies/origin.
    if auth_state and Path(auth_state).exists():
        ctx = await browser.new_context(storage_state=auth_state)
    else:
        ctx = browser.contexts[0] if browser.contexts else await browser.new_context()

    page = ctx.pages[0] if ctx.pages else await ctx.new_page()
    await page.goto(app_url, wait_until="domcontentloaded", timeout=30000)
    return pw, browser, ctx, page


async def _smoke():
    pw, browser, ctx, page = await get_page(auth_state=os.environ.get("WT_AUTH"))
    print("OK", page.url, "|", await page.title())
    await pw.stop()


if __name__ == "__main__":
    asyncio.run(_smoke())
