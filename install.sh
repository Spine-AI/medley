#!/usr/bin/env bash
# Medley one-time bootstrap. Configures npm auth for the private engine package
# (@spine-ai/medley-engine on GitHub Packages), then points you at the two /plugin commands.
# Safe to re-run. Usage:  ./install.sh   (or)   curl -fsSL <raw-url>/install.sh | bash
set -euo pipefail

SCOPE="@spine-ai"
REGISTRY_HOST="npm.pkg.github.com"
NPMRC="${HOME}/.npmrc"
MARKETPLACE="Spine-AI/medley"

echo "Medley installer — sets up access to the private engine package (${SCOPE}/medley-engine)."
echo

# 1. Get a token with the read:packages scope.
TOKEN="${GITHUB_TOKEN:-}"
if [ -z "$TOKEN" ] && command -v gh >/dev/null 2>&1; then
  TOKEN="$(gh auth token 2>/dev/null || true)"
fi
if [ -z "$TOKEN" ]; then
  echo "No token found. Create a GitHub token with the 'read:packages' scope:"
  echo "  https://github.com/settings/tokens  (classic, read:packages) — authorize SSO for Spine-AI if prompted."
  printf "Paste the token: "
  read -r TOKEN </dev/tty
fi
if [ -z "$TOKEN" ]; then
  echo "No token provided — aborting." >&2
  exit 1
fi

# 2. Write the scoped registry + auth to ~/.npmrc (idempotent — replaces any prior medley lines).
touch "$NPMRC"
tmp="$(mktemp)"
grep -v -e "^${SCOPE}:registry=" -e "^//${REGISTRY_HOST}/:_authToken=" "$NPMRC" > "$tmp" 2>/dev/null || true
{
  echo "${SCOPE}:registry=https://${REGISTRY_HOST}"
  echo "//${REGISTRY_HOST}/:_authToken=${TOKEN}"
} >> "$tmp"
mv "$tmp" "$NPMRC"
chmod 600 "$NPMRC"
echo "✓ Wrote ${SCOPE} registry auth to ${NPMRC}"

# 3. Best-effort verification.
if ver="$(npm view "${SCOPE}/medley-engine" version 2>/dev/null)"; then
  echo "✓ Verified read access — latest engine is ${ver}."
else
  echo "! Could not read ${SCOPE}/medley-engine yet. Ensure the token has 'read:packages' and"
  echo "  (for SSO orgs) is authorized for Spine-AI, then re-run this script."
fi

echo
echo "Now, inside Claude Code, run:"
echo "  /plugin marketplace add ${MARKETPLACE}"
echo "  /plugin install medley"
echo
echo "The first session installs the engine automatically (~30-60s, one-time). Done."
