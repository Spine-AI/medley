#!/usr/bin/env bash
# SessionStart bootstrap: make sure the pinned Medley engine BINARY for this platform is downloaded
# into the plugin's persistent data dir (${CLAUDE_PLUGIN_DATA}/bin). The engine ships as a
# self-contained, notarized executable published as a PUBLIC GitHub Release asset — so there is no
# auth, no npm, and no Node requirement. Downloads only when the pinned version isn't already cached.
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
  Linux)  os_tag="linux" ;;
  *) echo "medley: unsupported OS '$os' (need macOS or Linux)." >&2; exit 0 ;;
esac
case "$arch" in
  arm64|aarch64) arch_tag="arm64" ;;
  x86_64|amd64)  arch_tag="x64" ;;
  *) echo "medley: unsupported architecture '$arch'." >&2; exit 0 ;;
esac
asset="medley-engine-${os_tag}-${arch_tag}"
base="https://github.com/Spine-AI/medley/releases/download/v${VERSION}"

echo "medley: downloading engine ${VERSION} (${asset})…" >&2
mkdir -p "$BIN_DIR"
tmp="$(mktemp)"
sums="$(mktemp)"
cleanup() { rm -f "$tmp" "$sums"; }

if ! curl -fsSL "${base}/${asset}" -o "$tmp"; then
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
mkdir -p "${HOME}/.medley" 2>/dev/null && printf '%s\n' "$BIN_PATH" > "${HOME}/.medley/engine-path" 2>/dev/null
echo "medley: engine ready." >&2
exit 0
