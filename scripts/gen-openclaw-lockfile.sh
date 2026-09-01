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
#   1. Resolves the npm version to its matching source tag
#   2. Reads the published package.json from the npm tarball
#   3. Merges external extensions/*/package.json deps into the published manifest
#   4. Preserves published devDependencies (required for lockfile consistency)
#   5. Runs npm install --package-lock-only to produce a complete lockfile
#   6. Copies the matching package.json and package-lock.json to pkgs/openclaw
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
REPO_URL="${OPENCLAW_REPO_URL:-https://github.com/${REPO}.git}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST_DIR="${OPENCLAW_DEST_DIR:-${ROOT_DIR}/pkgs/openclaw}"
PACKAGE_JSON_DEST="${DEST_DIR}/package.json"
LOCKFILE_DEST="${DEST_DIR}/package-lock.json"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/openclaw-lockgen-${VERSION}.XXXXXX")"

cleanup() {
  rm -rf -- "$WORKDIR"
}
trap cleanup EXIT

tag_exists() {
  git ls-remote --exit-code --tags "$REPO_URL" "refs/tags/$1" >/dev/null 2>&1
}

resolve_source_tag() {
  local exact_tag="v${VERSION}"
  local base_version
  local base_tag
  local status

  if tag_exists "$exact_tag"; then
    echo "$exact_tag"
    return
  else
    status=$?
    if [ "$status" -ne 2 ]; then
      echo "::error::Failed to query exact source tag ${exact_tag}" >&2
      return "$status"
    fi
  fi

  if [[ "$VERSION" =~ ^(.+)-[0-9]+$ ]]; then
    base_version="${BASH_REMATCH[1]}"
    base_tag="v${base_version}"
    if tag_exists "$base_tag"; then
      echo "$base_tag"
      return
    else
      status=$?
      if [ "$status" -ne 2 ]; then
        echo "::error::Failed to query base source tag ${base_tag}" >&2
        return "$status"
      fi
    fi
  fi

  echo "::error::No source tag found for npm version ${VERSION}" >&2
  return 1
}

TAG="$(resolve_source_tag)"
echo "==> Using source tag ${TAG} for npm version ${VERSION}"
echo "==> Cloning openclaw ${TAG}..."
git -c advice.detachedHead=false clone --depth=1 --branch "$TAG" "$REPO_URL" "$WORKDIR"

SOURCE_VERSION="$(jq -r '.version // empty' "${WORKDIR}/package.json")"
if [ "$SOURCE_VERSION" != "${TAG#v}" ]; then
  echo "::error::Source tag ${TAG} contains package version ${SOURCE_VERSION:-<missing>}" >&2
  exit 1
fi

TARBALL_URL="${OPENCLAW_TARBALL_URL:-}"
if [ -z "$TARBALL_URL" ]; then
  echo "==> Resolving npm tarball for openclaw@${VERSION}..."
  TARBALL_URL="$(
    curl -fsSL "https://registry.npmjs.org/openclaw/${VERSION}" |
      jq -r '.dist.tarball // empty'
  )"
fi

if [ -z "$TARBALL_URL" ]; then
  echo "::error::npm tarball URL is missing for openclaw@${VERSION}" >&2
  exit 1
fi

PUBLISHED_PACKAGE_JSON="${WORKDIR}/.published-package.json"
echo "==> Reading published package.json..."
curl -fsSL "$TARBALL_URL" |
  tar -xzOf - package/package.json > "$PUBLISHED_PACKAGE_JSON"

echo "==> Merging extension deps into root package.json..."
cd "$WORKDIR"
OPENCLAW_VERSION="$VERSION" python3 - <<'PYEOF'
import json, glob, sys
import os

with open(".published-package.json") as f:
    root = json.load(f)

version = os.environ["OPENCLAW_VERSION"]
if root.get("version") != version:
    sys.exit(
        f"Published package version mismatch: expected {version}, "
        f"got {root.get('version')}"
    )

all_deps = dict(root.get("dependencies", {}))
added = []
skipped = []

for pkg_json in sorted(glob.glob("extensions/*/package.json")):
    with open(pkg_json) as f:
        ext = json.load(f)
    for key in ("dependencies", "peerDependencies"):
        for name, ver in ext.get(key, {}).items():
            if name == "openclaw" or name == root.get("name"):
                continue
            if isinstance(ver, str) and ver.startswith("workspace:"):
                published_version = all_deps.get(name)
                if (
                    isinstance(published_version, str)
                    and not published_version.startswith("workspace:")
                ):
                    skipped.append(
                        f"  = {name}@{published_version} replaces {ver}  "
                        f"(from {pkg_json})"
                    )
                    continue
                sys.exit(
                    f"Unresolved workspace dependency {name}@{ver} "
                    f"from {pkg_json}"
                )
            if name not in all_deps:
                all_deps[name] = ver
                added.append(f"  + {name}@{ver}  (from {pkg_json})")

for line in added:
    print(line)

if skipped:
    print("Skipped workspace-only extension dependencies:")
    for line in skipped:
        print(line)

root["dependencies"] = all_deps
# Keep published devDependencies: the npm tarball's package.json includes them,
# so the lockfile must reference them too or npm will fetch them during build.
root.pop("scripts", None)
root.pop("peerDependencies", None)

with open("package.json", "w") as f:
    json.dump(root, f, indent=2)

print(f"Total runtime dependencies: {len(all_deps)}")
print(f"devDependencies kept: {len(root.get('devDependencies', {}))}")
PYEOF

echo "==> Running npm install --package-lock-only..."
rm -f npm-shrinkwrap.json
# Match the package build flags. OpenClaw can ship extension dependencies whose
# peer ranges lag the versions selected by the release package metadata.
npm install --package-lock-only --package-lock=true --ignore-scripts --legacy-peer-deps

if [ ! -f package-lock.json ]; then
  echo "::error::npm did not generate package-lock.json"
  exit 1
fi

LOCKFILE_COUNT=$(python3 -c "import json; d=json.load(open('package-lock.json')); print(len(d['packages']))")
echo "==> Generated lockfile with ${LOCKFILE_COUNT} packages"

cp package.json "$PACKAGE_JSON_DEST"
cp package-lock.json "$LOCKFILE_DEST"
echo "==> Copied to ${PACKAGE_JSON_DEST}"
echo "==> Copied to ${LOCKFILE_DEST}"
echo ""
echo "Next steps — update pkgs/openclaw/default.nix:"
echo "  1. version = \"${VERSION}\""
echo "  2. src.hash = \"\"  then: nix build .#openclaw  (get hash from error)"
echo "  3. npmDepsHash = \"\"  then: nix build .#openclaw  (get hash from error)"
echo "  4. nix build .#openclaw  (should succeed)"
