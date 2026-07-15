#!/usr/bin/env bash
# headersHelper for the Medley MCP server (.mcp.json, type:http). Claude Code runs this on each
# CONNECTION and expects exactly one JSON object of header name→value on stdout, within 10s.
#
# It supplies the Bearer token for the daemon's /mcp (a stable per-user secret; the repo itself
# rides a STATIC `X-Medley-Repo-Raw: ${CLAUDE_PROJECT_DIR}` header in .mcp.json — this helper does
# NOT receive CLAUDE_PROJECT_DIR). CC CACHES this output and reuses it verbatim on reconnect (it does
# NOT re-run the helper), so the token must be STABLE and correct on the first call — including cold
# start, before the daemon's first boot. Hence read-or-create the shared token file here; the daemon
# (dashboard-server.stableToken) reads the very same file, so both agree.
#
# Fail-soft: always print a valid JSON object; never block on a download.
set -u

# Mirror the engine's userDataDir(): MEDLEY_DATA_DIR (inherited from the env when set) else the
# global default. So the token file the helper reads is the SAME one the daemon reads/creates.
STATE="${MEDLEY_DATA_DIR:-${HOME}/.medley/state}"
TOKENFILE="${STATE}/mcp-token"
PORT="${MEDLEY_DASHBOARD_PORT:-8730}"

read_token() { tr -d ' \t\n\r' < "$TOKENFILE" 2>/dev/null; }
is_token() { printf '%s' "$1" | grep -qE '^[0-9a-f]{32}$'; }

mkdir -p "$STATE" 2>/dev/null || true
TOKEN="$(read_token)"
if ! is_token "$TOKEN"; then
  NEW="$(openssl rand -hex 16 2>/dev/null || (head -c16 /dev/urandom | xxd -p | tr -d '\n') 2>/dev/null)"
  if is_token "$NEW"; then
    # Atomic create so a racing daemon boot / sibling session converges on one token: if the file
    # appeared first, keep theirs. `set -C` (noclobber) makes `>` fail when the file already exists.
    if ( set -C; printf '%s' "$NEW" > "$TOKENFILE" ) 2>/dev/null; then
      chmod 600 "$TOKENFILE" 2>/dev/null || true
      TOKEN="$NEW"
    else
      TOKEN="$(read_token)"
    fi
  fi
fi

# Worker recursion guard (layer 1 over HTTP): a Medley worker inherits the plugin, so its own CC
# session connects here too. It sends X-Medley-Worker so the daemon binds the no-op stub, never the
# orchestrator (deniedTools is the independent layer 2). The worker's daemon is already up — no nudge.
if [ "${MEDLEY_WORKER:-}" = "1" ]; then
  printf '{"Authorization":"Bearer %s","X-Medley-Worker":"1"}\n' "$TOKEN"
  exit 0
fi

# Cold-start bridge: MCP connect races the SessionStart pre-warm (they run concurrently), so the
# daemon may not be listening yet. Nudge it (fully detached, never blocking) so CC's connection
# retries find a live port. `service start` no-ops fast when a healthy daemon already answers.
if ! curl -fsS "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1; then
  DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ENGINE="$("$DIR/resolve-engine.sh" 2>/dev/null || true)"
  if [ -n "$ENGINE" ]; then
    case "$ENGINE" in
      *.cjs|*.js|*.mjs) ( node "$ENGINE" service start >/dev/null 2>&1 & ) ;;
      *)                ( "$ENGINE" service start >/dev/null 2>&1 & ) ;;
    esac
  fi
fi

printf '{"Authorization":"Bearer %s"}\n' "$TOKEN"
