# Medley — missions inside Claude Code

Medley turns a complex, multi-step goal into a supervised swarm. **`/mission <your goal>`** makes
your Claude Code session the mission agent: it interviews you, decomposes the goal into a task DAG
with per-task model routing, and supervises parallel in-repo workers (Claude Code **and** Codex)
that inherit your full setup — skills, MCP servers, `CLAUDE.md`, permission grants, subscription
auth. A live localhost **dashboard** streams every worker, surfaces approvals, and lets you steer
in plain language.

This repository is the **public plugin**. The mission engine ships as a separate, versioned
package that the plugin installs for you on first run — there's no build step and nothing to clone.

## Install

**1. One-time auth** (the engine is a private package, so npm needs a token once):

```bash
curl -fsSL https://raw.githubusercontent.com/Spine-AI/medley/main/install.sh | bash
# or, from a clone:  ./install.sh
```

It writes a scoped line to `~/.npmrc` (using your `gh` login if present, else a pasted token with
the `read:packages` scope).

**2. Add the plugin** inside Claude Code:

```
/plugin marketplace add Spine-AI/medley
/plugin install medley
```

That's it. Your **next session** installs the engine automatically (~30–60s, one-time — it fetches
the right native `better-sqlite3` binary for your platform), then everything just works. No
`--plugin-dir`, no build toolchain.

Then: `/mission <your goal>` → answer the interview → review the proposed DAG (each task's routed
runtime + model) → say "go". Steer with plain language ("tell the UI task to use shadcn", "kill the
flaky one"). Open the dashboard any time with `/dashboard`.

**Optional statusline** — a one-line mission ticker. Add to your `settings.json`:

```json
"statusLine": { "type": "command", "command": "<path-to-plugin>/scripts/statusline.sh" }
```

### Requirements
- Node ≥ 22.5.0 (the engine also supports Node 20/23/24/25/26).
- The `claude` CLI on your PATH (workers spawn via the Claude Agent SDK for subscription auth).
- Optional: the `codex` CLI (`codex login`) to add Codex workers to the routing pool.

## Update

Engine updates are shipped by bumping the plugin. Refresh and update:

```
/plugin marketplace update medley
/plugin update medley
```

The next session detects the new pinned engine version and reinstalls it automatically. To re-run
the auth step (e.g. token rotation), run `install.sh` again.

## Develop (this plugin)

The plugin is self-contained; the only moving part is **how it finds the engine**. `scripts/resolve-engine.sh`
picks, in order: `$MEDLEY_ENGINE` (dev override) → a sibling `../dist/medley-engine.cjs` → the copy
installed under `${CLAUDE_PLUGIN_DATA}` → the path cached in `~/.medley/engine-path`.

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
  engine/package.json             pins the engine version installed into ${CLAUDE_PLUGIN_DATA}
  skills/mission, skills/dashboard the /mission and /dashboard skills (+ per-runtime routing guides)
install.sh                        one-time private-registry auth
```

## License

MIT — see [LICENSE](./LICENSE). (The mission engine is a separate, closed package.)
