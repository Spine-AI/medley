# Changelog

All notable changes to the Medley plugin are documented here. This project adheres to
[Semantic Versioning](https://semver.org/). The plugin version tracks the engine version it pins.

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
