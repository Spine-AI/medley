#!/bin/bash
# SessionStart / PreCompact hook: (1) ensure the engine is installed into the plugin data dir,
# then (2) inject a 3-line "active mission" reminder so mission mode survives restarts and
# compaction. Prints nothing when no mission is active.
# Workers inherit the plugin (settingSources) — the mission-agent reminder must never reach a
# WORKER's context (it would misdirect it to orchestrate), and workers must not (re)install.
[ "$MEDLEY_WORKER" = "1" ] && exit 0
# Capture the hook payload (SessionStart / PreCompact deliver JSON on stdin). We only need the event
# name: starter /mission suggestions are offered on SessionStart, never on PreCompact (mid-work).
INPUT="$(cat 2>/dev/null || true)"
HOOK_EVENT="$(printf '%s' "$INPUT" | sed -n 's/.*"hook_event_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$DIR/ensure-engine.sh" 2>/dev/null || true
ENGINE="$("$DIR/resolve-engine.sh" 2>/dev/null || true)"
[ -n "$ENGINE" ] || exit 0
# ~/.medley/engine-path (the cache the statusline + resolver fall back to when the plugin env is
# unset) is written ONLY by ensure-engine.sh:record_engine_path, which advances it monotonically —
# so a stale older-pin session can never downgrade it. We do NOT rewrite it here: a second,
# unguarded writer defeats that guard and lets an older session drag the pointer (and, via the
# prewarm below, the daemon) backward. Just ensure the dir exists for the marker files further down.
mkdir -p "${HOME}/.medley" 2>/dev/null || true
# Keep a STABLE copy of the statusline script at a fixed path outside the versioned plugin cache. A
# statusLine wired in settings.json can't use ${CLAUDE_PLUGIN_*}, so it must hard-code a path — and a
# path into the versioned cache dir (…/cache/medley/medley/<ver>/scripts/statusline.sh) silently
# breaks the moment that version's cache is pruned on a later /plugin update. Pointing settings.json at
# this stable copy instead means the statusline keeps working across every update. The copy resolves
# the engine via ~/.medley/engine-path when run from here (see statusline.sh). Atomic (tmp + mv);
# best-effort.
if [ -f "$DIR/statusline.sh" ]; then
  _sl_tmp="${HOME}/.medley/statusline.sh.tmp.$$"
  if cp "$DIR/statusline.sh" "$_sl_tmp" 2>/dev/null; then
    chmod +x "$_sl_tmp" 2>/dev/null || true
    mv -f "$_sl_tmp" "${HOME}/.medley/statusline.sh" 2>/dev/null || rm -f "$_sl_tmp" 2>/dev/null || true
  fi
fi
# Pre-warm the shared daemon out-of-band so it's already up (or already warming) by the time the MCP
# server (.mcp.json → run-engine.sh mcp) attaches. Otherwise a cold session pays the daemon boot +
# health poll INSIDE Claude Code's MCP init window and tools can fail to register on session 1.
# Fully detached `( … & )` so the hook never blocks; `service start` no-ops fast when a healthy
# daemon already answers. Skipped for the legacy in-process mode.
if [ "${MEDLEY_DAEMON:-}" != "0" ]; then
  case "$ENGINE" in
    *.cjs|*.js|*.mjs) ( node "$ENGINE" service start >/dev/null 2>&1 & ) ;;
    *)                ( "$ENGINE" service start >/dev/null 2>&1 & ) ;;
  esac
fi
# Everything this hook prints is PLAIN TEXT added to Claude's context (the one-time setup offers below
# and the starter menu from `status --brief --suggest` alike) — no JSON control fields — so any of them
# may fire together in one session and simply concatenate. (The engine used to emit starters as a
# `systemMessage` JSON, which couldn't mix with the plain-text offers and which Claude Code silently
# dropped anyway; it now emits a plain-text menu instead, so there is nothing to defer.)
# One-time statusline offer: if no statusLine is configured, ask the host to OFFER wiring the
# medley statusline (never auto-write settings; never suggest replacing an existing one).
# The marker makes this a single-shot regardless of the outcome. Fail-soft throughout.
MARKER="${HOME}/.medley/statusline-offered"
if [ ! -e "$MARKER" ]; then
  if ! grep -q '"statusLine"' "${HOME}/.claude/settings.json" 2>/dev/null; then
    printf '%s\n' "[medley] One-time setup offer: no statusLine is configured. Offer the user the Medley statusline (live mission state — e.g. 'medley ▸ <title> · RUNNING · 4/9', or 'medley ▸ no mission · 3 starters · /mission' when idle — in the status bar). Only with their explicit yes, add to ~/.claude/settings.json: \"statusLine\": {\"type\": \"command\", \"command\": \"${HOME}/.medley/statusline.sh\"}. That path is a stable copy Medley refreshes each session, so it survives plugin updates. If they already have a statusline configured anywhere, do NOT replace or rewire it — just show them that snippet to integrate manually. If they decline, drop it; this offer never repeats."
    OFFERED=1
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
    OFFERED=1
  fi
  touch "$CLI_MARKER" 2>/dev/null || true
fi
# Starter /mission suggestions ride --brief on SessionStart only (skipped on PreCompact so a
# mid-work compaction isn't interrupted). The engine emits them as a hook `systemMessage` JSON so the
# user SEES them at the prompt — so we skip --suggest when an offer already wrote plain text this
# session (mixing the two would corrupt the JSON; deferred to the next, offer-free session).
BRIEF_ARGS=()
[ "$HOOK_EVENT" = "SessionStart" ] && [ "$OFFERED" = "0" ] && BRIEF_ARGS+=(--suggest)
case "$ENGINE" in
  *.cjs|*.js|*.mjs) exec node "$ENGINE" status --brief "${BRIEF_ARGS[@]}" 2>/dev/null ;;
  *)                exec "$ENGINE" status --brief "${BRIEF_ARGS[@]}" 2>/dev/null ;;
esac
