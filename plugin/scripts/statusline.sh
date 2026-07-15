#!/bin/bash
# Statusline command: `medley ▸ 3/9 done · 2 running · 1 needs you` (empty when no active
# mission). Wired in settings.json (see the plugin README):
#   "statusLine": { "type": "command", "command": "/abs/path/to/plugin/scripts/statusline.sh" }
# Runs in a settings.json context that lacks ${CLAUDE_PLUGIN_DATA}; resolve-engine.sh falls back
# to the ~/.medley/engine-path cache that session-start.sh writes. Never installs (stays instant).

# Update-state fast path (engine-free): while an engine download or a version roll is in flight,
# surface it straight from $HOME-reachable state — ensure-engine.sh's update.json download breadcrumb
# and the engine daemon's .rolling marker. Runs BEFORE resolving the engine because during a first
# install / binary swap the engine may not be runnable yet (the one moment we most want to show it).
STATE_DIR="${MEDLEY_DATA_DIR:-$HOME/.medley/state}"
if [ -f "$STATE_DIR/update.json" ] || [ -f "$STATE_DIR/.rolling" ]; then
  ind=$(STATE_DIR="$STATE_DIR" python3 - <<'PY' 2>/dev/null
import json, os, time
sd = os.environ.get("STATE_DIR", "")
now = time.time() * 1000
line = ""
# download breadcrumb — 30-min crash-net (ensure-engine.sh removes it when the download settles)
try:
    with open(os.path.join(sd, "update.json")) as f:
        u = json.load(f)
    if u.get("state") == "downloading" and now - float(u.get("since", 0)) < 1_800_000:
        v = u.get("version", "")
        line = "medley ▸ ⟳ downloading engine" + ((" v" + v) if v else "") + "…"
    elif u.get("state") == "pending":
        # A newer engine is installed but the roll is DEFERRED until the daemon goes idle (the engine
        # writes this + clears it on roll). No freshness bound: a deferred upgrade can legitimately
        # wait hours (e.g. a worker sleeping on a wakeup) before it applies.
        v = u.get("version", "")
        line = "medley ▸ ⟳ update" + ((" v" + v) if v else "") + " pending"
except Exception:
    pass
# version roll — 60s freshness (matches roll-marker.ts FRESH_MS)
if not line:
    try:
        with open(os.path.join(sd, ".rolling")) as f:
            ts = float(f.read().strip())
        if now - ts < 60_000:
            line = "medley ▸ ⟳ updating engine…"
    except Exception:
        pass
if line:
    print(line)
PY
)
  if [ -n "$ind" ]; then printf '%s' "$ind"; exit 0; fi
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$("$DIR/resolve-engine.sh" 2>/dev/null || true)"
[ -n "$ENGINE" ] || exit 0
input=$(cat)
project=$(printf '%s' "$input" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('workspace',{}).get('project_dir') or d.get('cwd') or '')" 2>/dev/null)
if [ -n "$project" ]; then cd "$project" 2>/dev/null || true; fi
case "$ENGINE" in
  *.cjs|*.js|*.mjs) exec node "$ENGINE" status --statusline 2>/dev/null ;;
  *)                exec "$ENGINE" status --statusline 2>/dev/null ;;
esac
