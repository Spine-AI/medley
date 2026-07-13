---
name: dashboard
description: Open the Medley web dashboard — live worker streams, approvals, steering, mission history, and the Settings page (providers, routing tiers, permission defaults). Works any time the medley plugin is loaded, no mission required.
---

# /dashboard — surface the Medley web UI

Call the `dashboard_url` tool on the `medley` MCP server (if it isn't loaded yet:
ToolSearch `"select:mcp__plugin_medley_medley__dashboard_url"`, then call it) and give the
user the URL it returns, e.g. "Medley dashboard: http://localhost:8730/ — the
settings button (top right) has providers, routing tiers, and approval defaults."

Notes:
- The URL is owned by the per-repo **daemon**, which outlives your session — so the same URL
  stays live across sessions (it only changes when the daemon restarts, e.g. after an upgrade
  or reboot). This skill always returns the current one.
- Outside a Claude Code session, the daemon's dashboard is usually already up; check with
  `"$(cat ~/.medley/engine-path)" service status` (the engine is a self-contained binary — run it
  directly). If none is running, start one with `"$(cat ~/.medley/engine-path)" service start`, or
  open the dashboard in the browser directly with `"$(cat ~/.medley/engine-path)" service dashboard --open`.
- If the tool reports the server isn't running, relay that honestly — don't invent a URL.
