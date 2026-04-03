#!/usr/bin/env bash
# Update the ollama package to the latest release.
#
# Usage:
#   ./scripts/update-ollama.sh              # update to latest release
#   ./scripts/update-ollama.sh 0.21.0       # update to specific version
#
# After running, verify with: nix build .#ollama
#
# What this updates:
#   - version, src.hash, vendorHash in pkgs/ollama/default.nix
#   - goTreeSitterSrc.rev + hash if go-tree-sitter version changed in go.mod
#   - treeSitterCppSrc.rev + hash if tree-sitter-cpp version changed in go.mod
#
# Background on tree-sitter patching:
#   go mod vendor omits C files not co-located with Go packages. go-tree-sitter
#   needs include/ + src/ (for api.h and lib.c via -Isrc); tree-sitter-cpp needs
#   src/ (referenced as ../../src/ from bindings/go/). These are fetched
#   separately and injected in overrideModAttrs.postInstall.

set -euo pipefail

PKG_FILE="$(cd "$(dirname "$0")/.." && pwd)/pkgs/ollama/default.nix"
FLAKE_DIR="$(dirname "$PKG_FILE")/../.."

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

# Update version and blank main hashes
sed -i "s/version = \"${CURRENT}\"/version = \"${VERSION}\"/" "$PKG_FILE"
sed -i '/repo = "ollama"/,/hash =/{s|hash = "sha256-[^"]*"|hash = ""|}'   "$PKG_FILE"
sed -i 's|vendorHash = "sha256-[^"]*"|vendorHash = ""|'                    "$PKG_FILE"

# -- Update tree-sitter source revisions if versions changed in go.mod ------

update_tree_sitter_src() {
  local module="$1"     # e.g. github.com/tree-sitter/go-tree-sitter
  local nix_var="$2"    # e.g. goTreeSitterSrc
  local new_ver
  new_ver=$(curl -s "https://raw.githubusercontent.com/ollama/ollama/v${VERSION}/go.mod" \
    | grep "^\s*${module} " | awk '{print $2}')
  if [[ -z "$new_ver" ]]; then
    echo "    ${nix_var}: not in go.mod, skipping"
    return
  fi

  local cur_rev
  cur_rev=$(grep -A3 "${nix_var}" "$PKG_FILE" | grep 'rev = ' | grep -oP '"\K[^"]+')

  local proxy_info
  proxy_info=$(curl -s "https://proxy.golang.org/${module}/@v/${new_ver}.info")
  local new_rev
  new_rev=$(echo "$proxy_info" | python3 -c "import json,sys; print(json.load(sys.stdin)['Origin']['Hash'])")

  if [[ "$cur_rev" == "$new_rev" ]]; then
    echo "    ${nix_var}: unchanged at ${new_ver}"
    return
  fi

  echo "    ${nix_var}: ${new_ver} → rev ${new_rev:0:8}"
  sed -i "/${nix_var}/,/hash = \"sha256/{s|rev = \"${cur_rev}\"|rev = \"${new_rev}\"|}" "$PKG_FILE"
  sed -i "/${nix_var}/,/};/{s|hash = \"sha256-[^\"]*\"|hash = \"\"|}" "$PKG_FILE"
}

echo "==> Checking tree-sitter dependency versions..."
update_tree_sitter_src "github.com/tree-sitter/go-tree-sitter"  "goTreeSitterSrc"
update_tree_sitter_src "github.com/tree-sitter/tree-sitter-cpp" "treeSitterCppSrc"

# -- Collect hashes via nix build -------------------------------------------

get_hash() {
  local label="$1"
  echo "==> Getting ${label}..."
  git -C "$FLAKE_DIR" add "$PKG_FILE"
  local h
  h=$(nix build "${FLAKE_DIR}#ollama" 2>&1 | grep "got:" | head -1 | awk '{print $NF}')
  if [[ -z "$h" ]]; then
    echo "ERROR: could not determine ${label}" >&2
    exit 1
  fi
  echo "$h"
}

# goTreeSitterSrc hash (only if blanked above)
if grep -q 'goTreeSitterSrc' "$PKG_FILE" && grep -A5 'goTreeSitterSrc' "$PKG_FILE" | grep -q 'hash = ""'; then
  TS_GO_HASH=$(get_hash "goTreeSitterSrc hash")
  sed -i "/goTreeSitterSrc/,/};/{s|hash = \"\"|hash = \"${TS_GO_HASH}\"|}" "$PKG_FILE"
fi

# treeSitterCppSrc hash (only if blanked above)
if grep -q 'treeSitterCppSrc' "$PKG_FILE" && grep -A5 'treeSitterCppSrc' "$PKG_FILE" | grep -q 'hash = ""'; then
  TS_CPP_HASH=$(get_hash "treeSitterCppSrc hash")
  sed -i "/treeSitterCppSrc/,/};/{s|hash = \"\"|hash = \"${TS_CPP_HASH}\"|}" "$PKG_FILE"
fi

# src hash
SRC_HASH=$(get_hash "src hash")
# Blank src hash is the one under fetchFromGitHub for ollama itself
sed -i '/repo = "ollama"/,/hash =/{s|hash = ""|hash = "'"${SRC_HASH}"'"|}' "$PKG_FILE"

# vendorHash
VENDOR_HASH=$(get_hash "vendorHash")
sed -i "s|vendorHash = \"\"|vendorHash = \"${VENDOR_HASH}\"|" "$PKG_FILE"

echo ""
echo "==> Updated pkgs/ollama/default.nix:"
grep -E '(version\s*=|hash\s*=|vendorHash|rev\s*=)' "$PKG_FILE" | grep -v '#' | head -12
echo ""
echo "==> Verify with: nix build .#ollama"
