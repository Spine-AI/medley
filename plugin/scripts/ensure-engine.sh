#!/usr/bin/env bash
# SessionStart bootstrap: make sure the pinned Medley engine is installed into the plugin's
# persistent data dir (${CLAUDE_PLUGIN_DATA}). This is the documented "install deps into the
# plugin data dir" idiom — a marketplace install copies the plugin to a read-only cache and
# runs no npm install, so the engine bundle (native better-sqlite3 + codex sidecars) is
# installed here on first session instead.
#
# Runs `npm install` only when the pin (plugin/engine/package.json) differs from what's already
# installed. No-ops for workers and for the dev override. On failure it prints the fix and exits
# 0 so the session still starts (the engine will simply be reported missing until fixed).

# Workers inherit the plugin; they were spawned by a live engine and must never (re)install.
[ "${MEDLEY_WORKER:-}" = "1" ] && exit 0
# Dev override: a local build is in use — nothing to install.
[ -n "${MEDLEY_ENGINE:-}" ] && exit 0
# The data dir is only provided by Claude Code at hook runtime; without it we can't install.
[ -n "${CLAUDE_PLUGIN_DATA:-}" ] || exit 0

PIN="${CLAUDE_PLUGIN_ROOT:-}/engine/package.json"
[ -f "$PIN" ] || exit 0

INSTALLED="${CLAUDE_PLUGIN_DATA}/node_modules/@spine-ai/medley-engine/dist/medley-engine.cjs"

# Up to date? (same manifest already installed AND the bundle is present)
if diff -q "$PIN" "${CLAUDE_PLUGIN_DATA}/package.json" >/dev/null 2>&1 && [ -f "$INSTALLED" ]; then
  exit 0
fi

echo "medley: installing engine (one-time, ~30-60s)…" >&2
mkdir -p "$CLAUDE_PLUGIN_DATA"
cp "$PIN" "${CLAUDE_PLUGIN_DATA}/package.json"
if (cd "$CLAUDE_PLUGIN_DATA" && npm install --no-audit --no-fund --loglevel=error) >&2 2>&1; then
  echo "medley: engine ready." >&2
else
  # Leave no stale manifest, so the next session retries the install.
  rm -f "${CLAUDE_PLUGIN_DATA}/package.json"
  echo "medley: engine install FAILED — likely missing private-registry auth. Run the medley" >&2
  echo "        repo's install.sh to set up ~/.npmrc, then restart Claude Code." >&2
fi
exit 0
