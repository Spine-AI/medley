# CLAUDE.md — medley (public plugin) contributor guide

This is the **public** Medley plugin repo. It contains only the thin, publishable plugin. The
mission **engine is a separate, private repo** (`Spine-AI/medley-engine`) that builds a
self-contained, code-signed binary. The binary is served from the **R2 CDN**
(`engine.getmedley.ai`) and mirrored to a **public GitHub Release on THIS repo** as a
fallback (so users download it with no auth), while the engine **source stays closed** — the release
workflow in the engine repo uploads the compiled binaries to both.

> Note: Claude Code does **not** load a plugin-repo `CLAUDE.md` into user sessions — this file is
> contributor guidance only. User-facing behavior comes from the skills under `plugin/skills/`.

## Hard rules

- **Never commit engine source or the built bundle here.** No `engine/`, no `src/`, no
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
  → asset (`medley-engine-darwin-arm64` — Apple Silicon only; x86_64 fails soft with a
  "requires arm64 / relaunch out of Rosetta" message), `curl`s it + `SHA256SUMS` from the R2 CDN
  (`engine.getmedley.ai/v<version>`) — falling back to this repo's GitHub Release —
  verifies the checksum, `chmod +x`, caches it. No-ops for workers
  (`MEDLEY_WORKER=1`) and the dev override. Fails soft (session still starts).
- `scripts/mcp-headers.sh` — the `.mcp.json` **`headersHelper`** (see below). Emits the Bearer token
  for the daemon's `/mcp` (read-or-create from the stable `<dataDir>/mcp-token`, shared with the
  engine), nudges the daemon awake if the port isn't answering (cold-start bridge), and tags a worker
  session with `X-Medley-Worker`. Prints one JSON header object; must stay fast (10s CC budget).
- `scripts/run-engine.sh` — the **stdio fallback** transport (`run-engine.sh mcp` → the engine's
  `mcp` proxy) for Claude Code older than the http/`headersHelper` baseline, and the binary resolver
  `mcp-headers.sh` reuses. Not on the default path.
- `~/.medley/engine-path` — written by `session-start.sh`/`ensure-engine.sh` so the **statusline**
  (wired via `settings.json`, where `${CLAUDE_PLUGIN_DATA}` is unset) can still find the engine.
- `~/.medley/state/update.json` — a download breadcrumb `ensure-engine.sh` writes while fetching a
  new engine (`{"state":"downloading","version","since"}`, epoch-ms; removed when the download
  settles). `statusline.sh` reads it — and the engine daemon's `.rolling` roll marker (60s freshness)
  — on a fast, engine-free path *before* delegating to `status --statusline`, so `/plugin update`
  surfaces `medley ▸ ⟳ downloading engine v…` / `medley ▸ ⟳ updating engine…`.

**`.mcp.json` is a DIRECT HTTP MCP server** (`type:"http"`, `url http://127.0.0.1:8730/mcp`) — Claude
Code talks straight to the shared daemon's `/mcp`, so CC's native HTTP auto-reconnect rides out a
daemon roll (engine auto-update) and the tools survive; the old per-session stdio proxy died on a
roll and broke them. The repo rides a **static** `X-Medley-Repo-Raw: ${CLAUDE_PROJECT_DIR}` header
(CC interpolates it; the `headersHelper` does NOT get `CLAUDE_PROJECT_DIR`); the token rides the
`headersHelper`. Requires the loopback port reachable — a stale pf redirect from an old
`service dashboard --setup --portless` breaks `127.0.0.1:8730`; clear it with
`medley-engine service dashboard --teardown` (`doctor` flags this). To revert to stdio for an old CC,
set `.mcp.json` back to `{ "command": "bash", "args": ["${CLAUDE_PLUGIN_ROOT}/scripts/run-engine.sh","mcp"] }`.

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
plugin/.mcp.json                  http MCP server → daemon /mcp (headersHelper: scripts/mcp-headers.sh)
plugin/hooks/hooks.json           SessionStart/PreCompact → session-start.sh; PreToolUse gate
plugin/scripts/                   {resolve,ensure,run}-engine.sh, session-start.sh, statusline.sh,
                                  edit-conflict-gate.py
plugin/engine/version             engine version pin (release-managed)
plugin/skills/mission|dashboard   the /mission and /dashboard skills (+ runtimes/ routing guides)
```
