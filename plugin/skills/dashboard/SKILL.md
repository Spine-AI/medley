---
name: dashboard
description: Open the Medley web dashboard — live worker streams, approvals, steering, mission history, and the Settings page (providers, routing tiers, permission defaults). Works any time the medley plugin is loaded, no mission required.
---

# /dashboard — surface the Medley web UI

Call the `dashboard_url` tool on the `medley` MCP server (if it isn't loaded yet:
ToolSearch `"select:mcp__plugin_medley_medley__dashboard_url"`, then call it) and give the
user the URL it returns, e.g. "Medley dashboard: http://127.0.0.1:PORT/?token=… — the
settings button (top right) has providers, routing tiers, and approval defaults."

Notes:
- The URL is engine-scoped: it dies with this session and a fresh session mints a new one
  (this skill always returns the current one).
- Outside a Claude Code session, run the engine's `dashboard` command directly against the
  installed bundle — `node "$(cat ~/.medley/engine-path)" dashboard` — to start a standalone
  dashboard (history + Settings; live worker control needs the owning session).
- If the tool reports the server isn't running, relay that honestly — don't invent a URL.
