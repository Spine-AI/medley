#!/usr/bin/env bash
# Tests statusline.sh's update-state fast path: the download breadcrumb (update.json, written by
# ensure-engine.sh) and the version-roll marker (.rolling, written by the engine daemon). Pure and
# file-driven — no engine binary required, since the fast path runs before engine resolution. HOME is
# pointed at a throwaway dir so resolve-engine.sh finds no cached engine (the delegate→silent cases).
# Run: bash plugin/scripts/test_statusline.sh
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SL="$DIR/statusline.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail=0
now_ms=$(( $(date +%s) * 1000 ))

# No engine on PATH/cache (HOME=tmp), state dir = tmp. Empty stdin (statusline reads it after the fast path).
run() { HOME="$tmp" MEDLEY_DATA_DIR="$tmp" CLAUDE_PLUGIN_DATA="" MEDLEY_ENGINE="" bash "$SL" </dev/null 2>/dev/null; }
assert_contains() { case "$1" in *"$2"*) : ;; *) echo "FAIL [$3]: expected '$2' in '$1'"; fail=1 ;; esac; }
assert_empty() { [ -z "$1" ] && return; echo "FAIL [$2]: expected empty, got '$1'"; fail=1; }

# 1. fresh download breadcrumb → "downloading engine v<version>"
printf '{"state":"downloading","version":"0.4.3","since":%s}\n' "$now_ms" > "$tmp/update.json"
assert_contains "$(run)" "downloading engine v0.4.3" "fresh update.json"
rm -f "$tmp/update.json"

# 2. fresh roll marker → "updating engine"
printf '%s' "$now_ms" > "$tmp/.rolling"
assert_contains "$(run)" "updating engine" "fresh .rolling"
rm -f "$tmp/.rolling"

# 3. stale download breadcrumb (ancient since) → ignored → silent (no engine to delegate to)
printf '{"state":"downloading","version":"0.4.3","since":1}\n' > "$tmp/update.json"
assert_empty "$(run)" "stale update.json"
rm -f "$tmp/update.json"

# 4. stale roll marker (>60s) → ignored → silent
printf '%s' "$(( now_ms - 120000 ))" > "$tmp/.rolling"
assert_empty "$(run)" "stale .rolling"
rm -f "$tmp/.rolling"

# 5. nothing in flight → silent (falls through to engine delegation; none present)
assert_empty "$(run)" "idle"

if [ "$fail" = 0 ]; then echo "ok: statusline update-state fast path"; else exit 1; fi
