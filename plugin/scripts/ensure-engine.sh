#!/usr/bin/env bash
# SessionStart bootstrap: make sure the pinned Medley engine BINARY for this platform is downloaded
# into the plugin's persistent data dir (${CLAUDE_PLUGIN_DATA}/bin). The engine ships as a
# self-contained, code-signed executable served from the R2 CDN (engine.getmedley.ai) with
# the public GitHub Release as a fallback mirror — so there is no auth, no npm, and no Node
# requirement. Downloads only when the pinned version isn't already cached.
# No-ops for workers and for the dev override. Fails soft (exits 0) so the session always starts.
set -u

# Workers inherit the plugin; they were spawned by a live engine and must never (re)download.
[ "${MEDLEY_WORKER:-}" = "1" ] && exit 0
# Dev override: a local build is in use — nothing to download.
[ -n "${MEDLEY_ENGINE:-}" ] && exit 0
# The data dir is only provided by Claude Code at hook runtime; without it we can't cache.
[ -n "${CLAUDE_PLUGIN_DATA:-}" ] || exit 0

VERSION_FILE="${CLAUDE_PLUGIN_ROOT:-}/engine/version"
[ -f "$VERSION_FILE" ] || exit 0
VERSION="$(tr -d ' \t\n\r' < "$VERSION_FILE")"
[ -n "$VERSION" ] || exit 0

BIN_DIR="${CLAUDE_PLUGIN_DATA}/bin"
BIN_PATH="${BIN_DIR}/medley-engine-${VERSION}"
# Already cached for this version? Record the path (for the statusline) and we're done.
if [ -x "$BIN_PATH" ]; then
  mkdir -p "${HOME}/.medley" 2>/dev/null && printf '%s\n' "$BIN_PATH" > "${HOME}/.medley/engine-path" 2>/dev/null
  exit 0
fi

# Map platform → release asset name (must match the release workflow's outputs).
os="$(uname -s)"; arch="$(uname -m)"
case "$os" in
  Darwin) os_tag="darwin" ;;
  *) echo "medley: Medley is macOS-only (this is $os)." >&2; exit 0 ;;
esac
case "$arch" in
  arm64|aarch64) arch_tag="arm64" ;;
  x86_64|amd64)
    # Medley ships a macOS arm64 binary only — there is no darwin-x64 asset to download.
    echo "medley: requires an Apple Silicon (arm64) Mac. This shell reports x86_64 — if you're on" >&2
    echo "        Apple Silicon it's running under Rosetta 2; relaunch Claude Code in a native arm64" >&2
    echo "        terminal. (Intel Macs are not supported.)" >&2
    exit 0 ;;
  *) echo "medley: unsupported architecture '$arch'." >&2; exit 0 ;;
esac
asset="medley-engine-${os_tag}-${arch_tag}"
# Primary: the R2 download CDN (branded domain, zero egress). Fallback: the public GitHub Release.
# Both are populated by the engine repo's release workflow.
base_r2="https://engine.getmedley.ai/v${VERSION}"
base_gh="https://github.com/Spine-AI/medley/releases/download/v${VERSION}"

mkdir -p "$BIN_DIR"
# Single-flight download lock. On a cold first session, session-start.sh AND run-engine.sh (via
# .mcp.json) can call this concurrently — without a lock they'd fire two curls at the same path and
# race the `mv`. An atomic `mkdir` lock means exactly ONE process downloads; the others wait for the
# binary to appear (bounded) and reuse it. Fail-soft: a stale lock (downloader died) is reclaimed.
LOCK_DIR="${BIN_DIR}/.downloading-${VERSION}.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  for _ in $(seq 1 180); do   # ~90s: wait out the other process's download instead of double-fetching
    if [ -x "$BIN_PATH" ]; then
      mkdir -p "${HOME}/.medley" 2>/dev/null && printf '%s\n' "$BIN_PATH" > "${HOME}/.medley/engine-path" 2>/dev/null
      exit 0
    fi
    sleep 0.5
  done
  rmdir "$LOCK_DIR" 2>/dev/null || true   # looks stale — reclaim and download ourselves
  mkdir "$LOCK_DIR" 2>/dev/null || true
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

echo "medley: downloading engine ${VERSION} (${asset})…" >&2
tmp="$(mktemp)"
sums="$(mktemp)"
cleanup() { rm -f "$tmp" "$sums"; }

# Try R2 first, then the GitHub Release. Remember which origin served the binary so the checksum
# file is fetched from the same place.
base=""
for b in "$base_r2" "$base_gh"; do
  if curl -fsSL "${b}/${asset}" -o "$tmp"; then base="$b"; break; fi
done
if [ -z "$base" ]; then
  cleanup
  echo "medley: engine download failed (network?) — will retry next session." >&2
  exit 0
fi

# Verify the checksum when SHA256SUMS is published (best-effort — skip if unavailable).
if curl -fsSL "${base}/SHA256SUMS" -o "$sums" 2>/dev/null; then
  expected="$(grep -E "  ${asset}\$" "$sums" 2>/dev/null | awk '{print $1}' | head -1)"
  if [ -n "$expected" ]; then
    if command -v shasum >/dev/null 2>&1; then
      actual="$(shasum -a 256 "$tmp" | awk '{print $1}')"
    else
      actual="$(sha256sum "$tmp" | awk '{print $1}')"
    fi
    if [ "$expected" != "$actual" ]; then
      echo "medley: checksum mismatch for ${asset} — refusing to install." >&2
      cleanup
      exit 0
    fi
  fi
fi

chmod +x "$tmp"
mv "$tmp" "$BIN_PATH"
rm -f "$sums"
# Prune superseded binaries — only the pinned version is ever run, and each is ~80MB, so old ones
# (from prior /plugin updates) just pile up. Safe: macOS keeps a running binary's inode alive after
# unlink, and stray old daemons are reaped by the engine on next boot. Fail-soft.
find "$BIN_DIR" -maxdepth 1 -type f -name 'medley-engine-*' ! -name "medley-engine-${VERSION}" -delete 2>/dev/null || true
mkdir -p "${HOME}/.medley" 2>/dev/null && printf '%s\n' "$BIN_PATH" > "${HOME}/.medley/engine-path" 2>/dev/null
echo "medley: engine ready." >&2
exit 0
