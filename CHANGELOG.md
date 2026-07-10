# Changelog

All notable changes to the Medley plugin are documented here. This project adheres to
[Semantic Versioning](https://semver.org/). The plugin version tracks the engine version it pins.

## [0.1.0] — unreleased

### Added
- Initial public release of the Medley plugin, split out from the private engine repo.
- `/mission` and `/dashboard` skills.
- Self-bootstrapping engine install: on first session the plugin installs the pinned
  `@spine-ai/medley-engine` into `${CLAUDE_PLUGIN_DATA}` (no build step, native binary fetched
  automatically).
- Dual-mode engine resolution (`scripts/resolve-engine.sh`): dev override, sibling `dist/`, or the
  installed copy.
- `install.sh` one-time private-registry auth bootstrap.
- Distributed via the `medley` marketplace (`/plugin marketplace add Spine-AI/medley`).
