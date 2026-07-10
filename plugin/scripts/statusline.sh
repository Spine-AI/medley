#!/bin/bash
# Statusline command: `medley ▸ 3/9 done · 2 running · 1 needs you` (empty when no active
# mission). Wired in settings.json (see the plugin README):
#   "statusLine": { "type": "command", "command": "/abs/path/to/plugin/scripts/statusline.sh" }
# Runs in a settings.json context that lacks ${CLAUDE_PLUGIN_DATA}; resolve-engine.sh falls back
# to the ~/.medley/engine-path cache that session-start.sh writes. Never installs (stays instant).
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$("$DIR/resolve-engine.sh" 2>/dev/null || true)"
[ -n "$ENGINE" ] || exit 0
input=$(cat)
project=$(printf '%s' "$input" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('workspace',{}).get('project_dir') or d.get('cwd') or '')" 2>/dev/null)
[ -n "$project" ] && cd "$project" 2>/dev/null
exec node "$ENGINE" status --statusline 2>/dev/null
