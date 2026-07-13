#!/bin/bash
# SessionStart / PreCompact hook: (1) ensure the engine is installed into the plugin data dir,
# then (2) inject a 3-line "active mission" reminder so mission mode survives restarts and
# compaction. Prints nothing when no mission is active.
# Workers inherit the plugin (settingSources) — the mission-agent reminder must never reach a
# WORKER's context (it would misdirect it to orchestrate), and workers must not (re)install.
[ "$MEDLEY_WORKER" = "1" ] && exit 0
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$DIR/ensure-engine.sh" 2>/dev/null || true
ENGINE="$("$DIR/resolve-engine.sh" 2>/dev/null || true)"
[ -n "$ENGINE" ] || exit 0
# Cache the resolved path for contexts that lack the plugin env (e.g. the statusline command).
if mkdir -p "${HOME}/.medley" 2>/dev/null; then
  printf '%s\n' "$ENGINE" > "${HOME}/.medley/engine-path" 2>/dev/null || true
fi
# One-time statusline offer: if no statusLine is configured, ask the host to OFFER wiring the
# medley statusline (never auto-write settings; never suggest replacing an existing one).
# The marker makes this a single-shot regardless of the outcome. Fail-soft throughout.
MARKER="${HOME}/.medley/statusline-offered"
if [ ! -e "$MARKER" ]; then
  if ! grep -q '"statusLine"' "${HOME}/.claude/settings.json" 2>/dev/null; then
    printf '%s\n' "[medley] One-time setup offer: no statusLine is configured. Offer the user the Medley statusline (live mission state — e.g. 'medley ▸ <title> · RUNNING · 4/9' — in the status bar). Only with their explicit yes, add to ~/.claude/settings.json: \"statusLine\": {\"type\": \"command\", \"command\": \"$DIR/statusline.sh\"}. If they already have a statusline configured anywhere, do NOT replace or rewire it — just show them that snippet to integrate manually. If they decline, drop it; this offer never repeats."
  fi
  touch "$MARKER" 2>/dev/null || true
fi
case "$ENGINE" in
  *.cjs|*.js|*.mjs) exec node "$ENGINE" status --brief 2>/dev/null ;;
  *)                exec "$ENGINE" status --brief 2>/dev/null ;;
esac
