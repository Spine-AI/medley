# Medley — missions inside Claude Code

Medley turns a complex, multi-step goal into a supervised swarm. **`/mission <your goal>`** makes
your Claude Code session the mission agent: it interviews you, decomposes the goal into a task DAG
with per-task model routing, and supervises parallel in-repo workers (Claude Code, Codex, **and**
Cursor) that inherit your full setup — skills, MCP servers, `CLAUDE.md`, permission grants, subscription
auth. A live localhost **dashboard** streams every worker, surfaces approvals, and lets you steer
in plain language.

This repository is the **public plugin**. The mission engine ships as a separate, self-contained
binary that the plugin downloads for you on first run — no auth, no Node, no build step, nothing to
clone.

## Install

Inside Claude Code:

```
/plugin marketplace add Spine-AI/medley
/plugin install medley
```

That's it. Your **next session** downloads the engine automatically (a single code-signed binary
from `engine.getmedley.ai`, with the public GitHub Release as fallback — no token, no npm), then
everything just works. No `--plugin-dir`, no build toolchain.

Then: `/mission <your goal>` → answer the interview → review the proposed DAG (each task's routed
runtime + model) → say "go". Steer with plain language ("tell the UI task to use shadcn", "kill the
flaky one"). Open the dashboard any time with `/dashboard`.

**Statusline** — a one-line mission ticker (`medley ▸ <title> · RUNNING · 4/9` while a mission runs,
empty when no mission is active) is set up automatically. On first session
Medley adds a `statusLine` entry to your `~/.claude/settings.json` pointing at a stable copy it
refreshes each session (`~/.medley/statusline.sh`), so it survives plugin updates. It never touches a
statusline you already have. To turn it off, delete the `statusLine` block from your `settings.json`
(Medley won't re-add it); a full uninstall removes it for you.

### Requirements
- macOS on Apple Silicon (arm64). The engine is a self-contained binary — **Node is not
  required**. (Intel Macs are not supported; on other platforms the plugin no-ops cleanly.)
- The `claude` CLI on your PATH (workers spawn via the Claude Agent SDK for subscription auth).
- Optional: the `codex` CLI (`codex login`) to add Codex workers to the routing pool.
- Optional: the `agent` CLI (`agent login`, from [cursor.com/install](https://cursor.com/install))
  to add Cursor workers to the routing pool.
- Any subset works — Medley auto-discovers whichever of these are installed and logged in, and
  routes only among the runtimes actually present.

## Update

Engine updates are shipped by bumping the plugin. Refresh and update:

```
/plugin marketplace update medley
/plugin update medley
```

The next session detects the new pinned engine version and downloads it automatically; the running
engine daemon rolls itself forward to the new version on next use (only ever forward, never back to an
older one), then prunes the superseded binaries so only the current engine remains.

## Develop (this plugin)

The plugin is self-contained; the only moving part is **how it finds the engine**. `scripts/resolve-engine.sh`
picks, in order: `$MEDLEY_ENGINE` (dev override) → the downloaded binary under
`${CLAUDE_PLUGIN_DATA}/bin/medley-engine-<version>` → the path cached in `~/.medley/engine-path`.

To hack on the plugin against a **local engine build** (from the private `medley-engine` repo):

```bash
# in the engine repo:  npm install && npm run build   → produces dist/medley-engine.cjs
MEDLEY_ENGINE=/path/to/medley-engine/dist/medley-engine.cjs \
  claude --plugin-dir /path/to/medley/plugin
```

Validate before pushing:

```bash
claude plugin validate ./plugin --strict
```

See `CLAUDE.md` for contributor notes (the marketplace-cache constraints, the engine-install idiom,
and what must never land in this public repo).

## What's inside

```
.claude-plugin/marketplace.json   the "medley" marketplace catalog (lists this plugin)
plugin/
  .claude-plugin/plugin.json      plugin manifest
  .mcp.json                       registers the medley MCP server (via scripts/run-engine.sh)
  hooks/hooks.json                SessionStart reminder + PreToolUse edit-conflict gate
  scripts/                        {resolve,ensure,run}-engine.sh, session-start.sh, statusline.sh,
                                  edit-conflict-gate.py
  engine/version                  pins the engine version the plugin downloads (release-managed)
  skills/mission, skills/dashboard the /mission and /dashboard skills (+ per-runtime routing guides)
```

## Security & privacy

What this plugin does on your machine, stated plainly:

- **Downloads and runs a compiled binary.** On session start the plugin downloads the Medley
  engine — a closed-source, self-contained executable — from `engine.getmedley.ai` (Cloudflare R2),
  falling back to the [public GitHub Release](https://github.com/Spine-AI/medley/releases). The
  version is pinned in `plugin/engine/version` (release-managed), the download is verified against
  the release's `SHA256SUMS`, and the binary is Developer ID code-signed (not notarized — a CLI
  fetched via `curl` is never quarantined, so Gatekeeper's notarization check does not apply).
- **Runs a background daemon.** The engine installs a single launchd LaunchAgent
  (`ai.getmedley.daemon`) so missions keep running between sessions. It binds to
  `127.0.0.1:8730` only — the MCP server and dashboard are never exposed off-host, and `/api` +
  `/mcp` require a local bearer token or same-origin browser request.
- **Local state.** Mission state lives in SQLite under `~/.medley/`; nothing is synced anywhere.
- **Telemetry is consent-gated and content-free.** Usage telemetry (PostHog) and crash reports
  (Sentry) are only sent with consent, and events carry enums, counts, durations, and exit codes
  only — never prompts, file contents, paths, or repo names. (The pipeline currently ships
  disabled.)
- **Workers run with your own auth.** Spawned workers use the `claude` / `codex` / `agent` CLIs
  already installed and logged in on your machine; the plugin never handles your credentials.

Uninstall: `/plugin uninstall medley` unregisters the plugin but leaves the daemon and state
behind — run `plugin/scripts/uninstall.sh` for a complete removal (LaunchAgent, downloaded
binaries, `~/.medley/` state; `--dry-run` shows the plan first, `--keep-data` preserves mission
history).

## License

The code in this repository — the plugin shim (scripts, hooks, skills, manifests) — is MIT-licensed;
see [LICENSE](./LICENSE). **Medley itself is not open source**: the mission engine the plugin
downloads is proprietary, closed-source software © Spine, distributed only as a compiled binary and
licensed for use with Medley. The MIT grant does not extend to the engine.
