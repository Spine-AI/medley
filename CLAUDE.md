# CLAUDE.md — medley (public plugin) contributor guide

This is the **public** Medley plugin repo. It contains only the thin, publishable plugin. The
mission **engine is a separate, private repo** (`Spine-AI/medley-engine`) that builds a
self-contained, code-signed binary. The binary is served from the **R2 CDN**
(`updates.getmedley.ai/engine/`) and mirrored to a **public GitHub Release on THIS repo** as a
fallback (so users download it with no auth), while the engine **source stays closed** — the release
workflow in the engine repo uploads the compiled binaries to both.

> Note: Claude Code does **not** load a plugin-repo `CLAUDE.md` into user sessions — this file is
> contributor guidance only. User-facing behavior comes from the skills under `plugin/skills/`.

## Hard rules

- **Never commit engine source or the built bundle here.** No `electron/`, no `src/`, no
  `dist/medley-engine.cjs`. Only the plugin (skills, hooks, scripts, manifests) and repo docs.
  (The compiled binaries live on GitHub **Releases**, not in the git tree.)
- **`plugin/engine/version` is release-managed** — a plain-text version the plugin downloads. The
  engine repo's release workflow bumps it; don't hand-edit.
- **Keep the product/plugin/marketplace name `medley`.** Install is `/plugin install medley`
  (the plugin name alone is enough — no redundant `@medley` qualifier).

## How the engine is found (the one real mechanism)

A marketplace install **copies** the plugin into a read-only cache (`~/.claude/plugins/cache/...`),
**forbids `../` traversal** outside the plugin dir, and runs **no** install. So the engine is not
shipped in the plugin — a self-contained **binary** is downloaded on first session into the
persistent, writable `${CLAUDE_PLUGIN_DATA}/bin` dir. No auth, no Node, no npm.

- `scripts/resolve-engine.sh` — pure resolver. Order: `$MEDLEY_ENGINE` (dev, `.cjs` or binary) →
  `${CLAUDE_PLUGIN_DATA}/bin/medley-engine-<version>` → `~/.medley/engine-path` cache.
- `scripts/ensure-engine.sh` — SessionStart bootstrap. Reads `engine/version`, maps `uname`
  → asset (`medley-engine-darwin-{arm64,x64}`), `curl`s it + `SHA256SUMS` from the R2 CDN
  (`updates.getmedley.ai/engine/v<version>`) — falling back to this repo's GitHub Release —
  verifies the checksum, `chmod +x`, caches it. No-ops for workers
  (`MEDLEY_WORKER=1`) and the dev override. Fails soft (session still starts).
- `scripts/run-engine.sh` — used by `.mcp.json`; resolves (downloading on demand) and execs the
  engine (a `.cjs` dev build via `node`; a binary directly).
- `~/.medley/engine-path` — written by `session-start.sh`/`ensure-engine.sh` so the **statusline**
  (wired via `settings.json`, where `${CLAUDE_PLUGIN_DATA}` is unset) can still find the engine.

`.mcp.json` uses the canonical wrapped `{ "mcpServers": { … } }` form. The self-contained binary
needs no `NODE_PATH` (only a dev `.cjs` run via `node` relies on ambient resolution).

Because paths must not leave the plugin dir after caching, **never** reintroduce a `../dist`
reference in a shipped file — always go through the resolver.

## Develop & test

- **Against a local engine build** (from the private repo): build it, then
  `MEDLEY_ENGINE=/path/to/medley-engine/dist/medley-engine.cjs claude --plugin-dir ./plugin`.
- **Installed mode** (what users get): `/plugin marketplace add <local path or Spine-AI/medley>` →
  `/plugin install medley` → new session downloads the engine binary into `${CLAUDE_PLUGIN_DATA}/bin`.
- **Validate** before pushing: `claude plugin validate ./plugin --strict`. Shellcheck the
  `scripts/*.sh`.

## Layout

```
.claude-plugin/marketplace.json   the "medley" marketplace (lists this plugin, source ./plugin)
plugin/.claude-plugin/plugin.json manifest (identity metadata: name, version, author, license, …)
plugin/.mcp.json                  wrapped mcpServers → scripts/run-engine.sh
plugin/hooks/hooks.json           SessionStart/PreCompact → session-start.sh; PreToolUse gate
plugin/scripts/                   {resolve,ensure,run}-engine.sh, session-start.sh, statusline.sh,
                                  edit-conflict-gate.py
plugin/engine/version             engine version pin (release-managed)
plugin/skills/mission|dashboard   the /mission and /dashboard skills (+ runtimes/ routing guides)
```
