#!/usr/bin/env bash
# Generate a complete package-lock.json for the openclaw Nix package.
#
# Background: openclaw is a pnpm monorepo. The npm registry tarball only ships
# the root package.json (47 deps), but the actual build needs deps from all
# extensions/ subpackages too. Additionally, the tarball's package.json includes
# devDependencies (lit, @lit-labs/signals, etc.) that must be present in the
# lockfile to keep it consistent with what npm sees at build time.
#
# This script:
#   1. Clones the source at the given git tag
#   2. Merges all extensions/*/package.json deps into the root package.json
#   3. Preserves devDependencies from the root (required for lockfile consistency)
#   4. Runs npm install --package-lock-only to produce a complete lockfile
#
# Usage:
#   ./scripts/gen-openclaw-lockfile.sh <version>
#   ./scripts/gen-openclaw-lockfile.sh 2026.3.31
#
# After running, update pkgs/openclaw/default.nix:
#   1. Set version = "<new-version>"
#   2. Set src.hash = "" and run nix build .#openclaw to get the correct hash
#   3. Set npmDepsHash = "" and run nix build .#openclaw again for that hash

set -euo pipefail

VERSION="${1:?Usage: $0 <version>}"
REPO="openclaw/openclaw"
TAG="v${VERSION}"
WORKDIR="/tmp/openclaw-lockgen-${VERSION}"
DEST="$(cd "$(dirname "$0")/.." && pwd)/pkgs/openclaw/package-lock.json"

echo "==> Cloning openclaw ${TAG}..."
rm -rf "$WORKDIR"
git clone --depth=1 --branch "$TAG" "https://github.com/${REPO}.git" "$WORKDIR"

echo "==> Merging extension deps into root package.json..."
cd "$WORKDIR"
python3 - <<'PYEOF'
import json, glob, sys

with open("package.json") as f:
    root = json.load(f)

all_deps = dict(root.get("dependencies", {}))
added = []

for pkg_json in sorted(glob.glob("extensions/*/package.json")):
    with open(pkg_json) as f:
        ext = json.load(f)
    for key in ("dependencies", "peerDependencies"):
        for name, ver in ext.get(key, {}).items():
            if name not in all_deps:
                all_deps[name] = ver
                added.append(f"  + {name}@{ver}  (from {pkg_json})")

for line in added:
    print(line)

root["dependencies"] = all_deps
# Keep devDependencies: the npm tarball's package.json includes them, so the
# lockfile must reference them too or npm will try to fetch them at build time.
root.pop("scripts", None)
root.pop("peerDependencies", None)
root.pop("optionalDependencies", None)

with open("package.json", "w") as f:
    json.dump(root, f, indent=2)

print(f"Total runtime dependencies: {len(all_deps)}")
print(f"devDependencies kept: {len(root.get('devDependencies', {}))}")
PYEOF

echo "==> Running npm install --package-lock-only..."
npm install --package-lock-only --ignore-scripts 2>&1 | tail -3

LOCKFILE_COUNT=$(python3 -c "import json; d=json.load(open('package-lock.json')); print(len(d['packages']))")
echo "==> Generated lockfile with ${LOCKFILE_COUNT} packages"

cp package-lock.json "$DEST"
echo "==> Copied to ${DEST}"
echo ""
echo "Next steps — update pkgs/openclaw/default.nix:"
echo "  1. version = \"${VERSION}\""
echo "  2. src.hash = \"\"  then: nix build .#openclaw  (get hash from error)"
echo "  3. npmDepsHash = \"\"  then: nix build .#openclaw  (get hash from error)"
echo "  4. nix build .#openclaw  (should succeed)"
