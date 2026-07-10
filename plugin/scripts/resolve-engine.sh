#!/usr/bin/env bash
# Resolve the Medley engine bundle. Prints the absolute path and exits 0 if found; else exits 1
# with no output. Pure — no side effects (see ensure-engine.sh for the installer).
#
# Resolution order:
#   1. $MEDLEY_ENGINE                                        — explicit dev override (a local build)
#   2. ${CLAUDE_PLUGIN_ROOT}/../dist/medley-engine.cjs       — in-place checkout with a sibling dist/
#   3. ${CLAUDE_PLUGIN_DATA}/node_modules/@spine-ai/medley-engine/dist/medley-engine.cjs  — installed
#   4. path cached in ~/.medley/engine-path                  — for contexts without the plugin env
#      (e.g. the statusline command, which is wired via settings.json, not as a plugin hook, so
#       ${CLAUDE_PLUGIN_DATA} is unset there; session-start.sh writes this cache each session).
cached=""
[ -f "${HOME:-/nonexistent}/.medley/engine-path" ] && cached="$(cat "${HOME}/.medley/engine-path" 2>/dev/null)"
for candidate in \
  "${MEDLEY_ENGINE:-}" \
  "${CLAUDE_PLUGIN_ROOT:-/nonexistent}/../dist/medley-engine.cjs" \
  "${CLAUDE_PLUGIN_DATA:-/nonexistent}/node_modules/@spine-ai/medley-engine/dist/medley-engine.cjs" \
  "$cached"; do
  if [ -n "$candidate" ] && [ -f "$candidate" ]; then
    printf '%s\n' "$candidate"
    exit 0
  fi
done
exit 1
