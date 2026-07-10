#!/usr/bin/env bash
# Resolve (installing on demand) the Medley engine and exec it with the given args.
# Used by .mcp.json to launch the MCP server (`run-engine.sh mcp`); also usable ad hoc.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENGINE="$("$DIR/resolve-engine.sh" 2>/dev/null || true)"
if [ -z "$ENGINE" ]; then
  # Not present yet (e.g. very first session before the SessionStart hook finished) — install now.
  "$DIR/ensure-engine.sh" || true
  ENGINE="$("$DIR/resolve-engine.sh" 2>/dev/null || true)"
fi
if [ -z "$ENGINE" ]; then
  echo "medley: engine not found and could not be installed. Run the medley repo's install.sh" >&2
  echo "        (sets up private-registry auth in ~/.npmrc), then restart Claude Code." >&2
  exit 1
fi
exec node "$ENGINE" "$@"
