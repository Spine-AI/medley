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
# One-time CLI offer: if the `medley-engine` command isn't on the user's PATH, offer (once) to add
# a shell alias so the advanced CLI (`service dashboard --setup`, service start/stop/logs) is
# reachable. Mirrors the statusline offer above — never auto-writes, single-shot via a marker.
CLI_MARKER="${HOME}/.medley/cli-offered"
if [ ! -e "$CLI_MARKER" ]; then
  if ! command -v medley-engine >/dev/null 2>&1; then
    cat <<'MEDLEY_CLI_OFFER'
[medley] One-time setup offer: the `medley-engine` CLI (advanced — dashboard branding via `service dashboard --setup`, plus service start/stop/restart/logs) is not on the user's PATH. Only with the user's explicit yes, append this exact block to ~/.zshrc (create the file if it doesn't exist):
# >>> medley cli >>>
alias medley-engine='"$(cat ~/.medley/engine-path)"'
# <<< medley cli <<<
Then tell them to run `source ~/.zshrc` or open a new terminal. The alias re-reads ~/.medley/engine-path on each call, so it survives engine upgrades. To remove it later, delete that marked block from ~/.zshrc. If the user is on a non-zsh shell (bash/fish), show them the same alias for their own rc. If they decline, drop it — this offer never repeats.
MEDLEY_CLI_OFFER
  fi
  touch "$CLI_MARKER" 2>/dev/null || true
fi
case "$ENGINE" in
  *.cjs|*.js|*.mjs) exec node "$ENGINE" status --brief 2>/dev/null ;;
  *)                exec "$ENGINE" status --brief 2>/dev/null ;;
esac
