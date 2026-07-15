# Changelog

All notable changes to the Medley plugin are documented here. This project adheres to
[Semantic Versioning](https://semver.org/). The plugin version tracks the engine version it pins.

## [0.4.7] — 2026-07-15

Tracks engine v0.4.7 — no plugin-script change. Engine-side dashboard cleanup for the free
OpenRouter tier: the topbar credit pill is removed (usage lives in Settings only), the
Medley-free ↔ your-own-key switch is fixed (instant, with an Edit-key flow instead of an
always-open input), the model picker is uncapped (full open-source catalog), and bringing your
own key now unlocks the full OpenRouter catalog (closed models too). See the engine changelog.

## [0.4.6] — 2026-07-15

### Fixed
- **`~/.medley/engine-path` could get stuck on an older engine after `/plugin update`.**
  `session-start.sh` was a second, unguarded writer of the cache; it overrode `ensure-engine.sh`'s
  advance-only guard, so a stale older-pin session (a concurrent Claude Code window still on a prior
  plugin cache) stamped the pointer — and, via the daemon prewarm, the shared daemon itself — back to
  an older version. `ensure-engine.sh` (`record_engine_path`) is now the sole, monotonic writer.
- Pairs with engine v0.4.6, which refuses to roll the shared daemon to an older version and prunes
  superseded engine binaries down to a single one (see the engine changelog for engine-side detail).

## [0.4.1] – [0.4.5] — 2026-07-15

Plugin releases tracking engine v0.4.1–v0.4.5; the engine-side changes (daemon/launchd boot fixes, the
crash-loop self-heal, and the free OpenRouter tier) are documented in the engine changelog. The one
notable plugin-script change in this range shipped in v0.4.4: `ensure-engine.sh` gained the
keep-two-newest binary prune and the advance-only `record_engine_path` engine-path cache.

## [0.4.0] — 2026-07-14

### Changed
- **One shared daemon for every repo (was one daemon per repo).** All Claude sessions now talk to a
  single background daemon over `http://localhost:8730`, backed by one shared SQLite DB; each session
  declares its repo on the wire, so the daemon keeps every repo's missions isolated by project. No
  plugin-script change was needed — the `mcp` proxy sends the repo header itself.
- **Unified dashboard.** The web dashboard now lists every repo's missions in one place, and
  `dashboard_url` deep-links straight to your current mission (`?mission=…`); the first
  `mission_start` auto-opens that deep link. `/mission` + `/dashboard` docs updated.

## [0.1.0] — unreleased

### Added
- Initial public release of the Medley plugin, split out from the private engine repo.
- `/mission` and `/dashboard` skills.
- **Persistent engine daemon.** The engine now runs as a per-repo background daemon that
  outlives Claude sessions; `.mcp.json`'s `mcp` command is a thin proxy that lazily starts it
  and, on session close, disconnects without stopping the daemon. Workers and the dashboard URL
  stay live across sessions, so `mission_resume` is only needed after a true crash/reboot
  (`/mission` and `/dashboard` docs updated accordingly). `MEDLEY_DAEMON=0` opts back into the
  legacy in-process engine.
- **Public binary distribution (no auth, no Node).** On first session the plugin downloads a
  self-contained, notarized engine binary for the platform (`medley-engine-{darwin,linux}-{arm64,x64}`)
  from this repo's public GitHub Releases into `${CLAUDE_PLUGIN_DATA}/bin`, verifies its checksum, and
  runs it directly. Replaces the previous private-npm install: removed `install.sh` (private-registry
  auth) and the `NODE_PATH` env in `.mcp.json`; `engine/package.json` → plain-text `engine/version`.
- Engine resolution (`scripts/resolve-engine.sh`): dev override (`$MEDLEY_ENGINE`) → downloaded
  binary (`${CLAUDE_PLUGIN_DATA}/bin/medley-engine-<version>`) → `~/.medley/engine-path` cache.
- Distributed via the `medley` marketplace (`/plugin marketplace add Spine-AI/medley`).
