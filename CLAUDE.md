# CLAUDE.md — medley (public plugin) contributor guide

This is the **public** Medley plugin repo. It contains only the thin, publishable plugin. The
mission **engine is a separate, private package** (`@spine-ai/medley-engine`, repo `Spine-AI/medley-engine`)
published to private GitHub Packages.

> Note: Claude Code does **not** load a plugin-repo `CLAUDE.md` into user sessions — this file is
> contributor guidance only. User-facing behavior comes from the skills under `plugin/skills/`.

## Hard rules

- **Never commit engine source or the built bundle here.** No `electron/`, no `src/`, no
  `dist/medley-engine.cjs`. Only the plugin (skills, hooks, scripts, manifests) and repo docs.
- **`plugin/engine/package.json` is release-managed** — it pins the engine version the plugin
  installs. The engine repo's release workflow bumps it; don't hand-edit.
- **Keep the product/plugin/marketplace name `medley`.** Install is `/plugin install medley`
  (the plugin name alone is enough — no redundant `@medley` qualifier).

## How the engine is found (the one real mechanism)

A marketplace install **copies** the plugin into a read-only cache (`~/.claude/plugins/cache/...`),
**forbids `../` traversal** outside the plugin dir, and runs **no** `npm install`. So the engine is
not shipped in the plugin — it's installed on first session into the persistent, writable
`${CLAUDE_PLUGIN_DATA}` dir (the documented idiom).

- `scripts/resolve-engine.sh` — pure resolver. Order: `$MEDLEY_ENGINE` → `${CLAUDE_PLUGIN_ROOT}/../dist/…`
  → `${CLAUDE_PLUGIN_DATA}/node_modules/@spine-ai/medley-engine/dist/…` → `~/.medley/engine-path` cache.
- `scripts/ensure-engine.sh` — SessionStart bootstrap. Diffs `engine/package.json` against the copy
  in `${CLAUDE_PLUGIN_DATA}` and runs `npm install` there only when it changed. No-ops for workers
  (`MEDLEY_WORKER=1`) and for the dev override. Fails soft (session still starts).
- `scripts/run-engine.sh` — used by `.mcp.json`; resolves (installing on demand) and execs the engine.
- `~/.medley/engine-path` — written by `session-start.sh` each session so the **statusline** (wired
  via `settings.json`, where `${CLAUDE_PLUGIN_DATA}` is unset) can still find the engine.

`.mcp.json` uses the canonical wrapped `{ "mcpServers": { … } }` form and sets
`env.NODE_PATH=${CLAUDE_PLUGIN_DATA}/node_modules` so the bundle + Codex sidecars resolve their deps.

Because paths must not leave the plugin dir after caching, **never** reintroduce a `../dist`
reference in a shipped file — always go through the resolver.

## Develop & test

- **Against a local engine build** (from the private repo): build it, then
  `MEDLEY_ENGINE=/path/to/medley-engine/dist/medley-engine.cjs claude --plugin-dir ./plugin`.
- **Installed mode** (what users get): `/plugin marketplace add <local path or Spine-AI/medley>` →
  `/plugin install medley` → new session installs the engine into `${CLAUDE_PLUGIN_DATA}`.
- **Validate** before pushing: `claude plugin validate ./plugin --strict`. Shellcheck the
  `scripts/*.sh`.

## Layout

```
.claude-plugin/marketplace.json   the "medley" marketplace (lists this plugin, source ./plugin)
plugin/.claude-plugin/plugin.json manifest (identity metadata: name, version, author, license, …)
plugin/.mcp.json                  wrapped mcpServers → scripts/run-engine.sh, NODE_PATH set
plugin/hooks/hooks.json           SessionStart/PreCompact → session-start.sh; PreToolUse gate
plugin/scripts/                   {resolve,ensure,run}-engine.sh, session-start.sh, statusline.sh,
                                  edit-conflict-gate.py
plugin/engine/package.json        engine version pin (release-managed)
plugin/skills/mission|dashboard   the /mission and /dashboard skills (+ runtimes/ routing guides)
install.sh                        one-time private-registry auth (~/.npmrc)
```
