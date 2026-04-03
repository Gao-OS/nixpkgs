#!/usr/bin/env bash
# Update the ollama package to the latest release.
#
# Usage:
#   ./scripts/update-ollama.sh              # update to latest release
#   ./scripts/update-ollama.sh 0.20.0       # update to specific version
#
# After running, verify with: nix build .#ollama

set -euo pipefail

PKG_FILE="$(cd "$(dirname "$0")/.." && pwd)/pkgs/ollama/default.nix"

# Resolve target version
if [[ $# -ge 1 ]]; then
  VERSION="$1"
else
  echo "==> Fetching latest ollama release..."
  VERSION=$(gh api repos/ollama/ollama/releases/latest --jq '.tag_name | ltrimstr("v")')
fi
echo "==> Target version: ${VERSION}"

CURRENT=$(grep 'version = "' "$PKG_FILE" | head -1 | grep -oP '"\K[^"]+')
if [[ "$CURRENT" == "$VERSION" ]]; then
  echo "==> Already at ${VERSION}, nothing to do."
  exit 0
fi

echo "==> Updating ${CURRENT} → ${VERSION}"

# Update version
sed -i "s/version = \"${CURRENT}\"/version = \"${VERSION}\"/" "$PKG_FILE"

# Blank out hashes so nix reports the correct values
sed -i 's|hash = "sha256-[^"]*"|hash = ""|' "$PKG_FILE"
sed -i 's|vendorHash = "sha256-[^"]*"|vendorHash = ""|' "$PKG_FILE"

echo "==> Getting src hash..."
git add "$PKG_FILE"
SRC_HASH=$(nix build "$(dirname "$PKG_FILE")/../../#ollama" 2>&1 | grep "got:" | head -1 | awk '{print $NF}')
if [[ -z "$SRC_HASH" ]]; then
  echo "ERROR: could not determine src hash" >&2
  exit 1
fi
sed -i "s|hash = \"\"|hash = \"${SRC_HASH}\"|" "$PKG_FILE"

echo "==> Getting vendorHash..."
git add "$PKG_FILE"
VENDOR_HASH=$(nix build "$(dirname "$PKG_FILE")/../../#ollama" 2>&1 | grep "got:" | head -1 | awk '{print $NF}')
if [[ -z "$VENDOR_HASH" ]]; then
  echo "ERROR: could not determine vendorHash" >&2
  exit 1
fi
sed -i "s|vendorHash = \"\"|vendorHash = \"${VENDOR_HASH}\"|" "$PKG_FILE"

echo "==> Hashes updated:"
grep -E '(version|hash|vendorHash)' "$PKG_FILE" | grep -v "#" | head -5

echo ""
echo "==> Verify with: nix build .#ollama"
