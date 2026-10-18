# Changelog

All notable changes to parallel-lifecycle are documented here. This project adheres to
[Semantic Versioning](https://semver.org/).

## 1.0.0 — 2026-10-14

Major release: parallel-lifecycle moves to 1.0.0 together with the rest of the *-it
lifecycle family (prompt-it 1.0.0, plan-it 5.0.0, build-it 4.0.0, review-it 2.0.0,
conclude-it 2.0.0). No behaviour change beyond 0.2.0; the do-it isolation driver
(`isolation.sh` with exactly `create` / `remove` / `path`) is carried unchanged.
Version bump in `plugin.json`, `marketplace.json` and root `SKILL.md` frontmatter.

## 0.2.0 — 2026-10-14

do-it integration: `isolation.sh` exposes the isolation driver contract do-it selects
via its `isolation` setting (`create` / `remove` / `path`), built on the existing
bootstrap and teardown hooks. Documented in both `SKILL.md` copies.
