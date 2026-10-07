#!/usr/bin/env bash
# Regression test for Gao-OS/nixpkgs#34.
# See the inline docs in pkgs/openclaw/default.nix for the patch context.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PKG="${ROOT_DIR}/pkgs/openclaw/default.nix"

if [ ! -f "${PKG}" ]; then
  echo "FAIL: ${PKG} not found" >&2
  exit 1
fi

assert_grep() {
  local pattern="$1"
  local label="$2"
  if ! grep -F -- "${pattern}" "${PKG}" >/dev/null; then
    echo "FAIL: ${label}" >&2
    echo "  pattern: ${pattern}" >&2
    echo "  file:    ${PKG}" >&2
    exit 1
  fi
}

# Property 1: substituteInPlace wired into preConfigure on the buggy chunk file.
assert_grep \
  "substituteInPlace dist/doctor-config-preflight-B-Zv4Qey.js" \
  "warning-gate substituteInPlace call missing from preConfigure"

# Property 2: substituteInPlace must use --replace-fail so the 2026.8.2
# bundle's warning gate is verified before applying the patch.
assert_grep \
  "--replace-fail" \
  "substituteInPlace must use --replace-fail to verify the patched bundle"

# Property 3: original buggy text referenced verbatim so substituteInPlace can
# match it in the bundled dist/ tree.
assert_grep \
  "if (params.startupMigrationWarnings.length > 0) throwStartupMigrationRefusal" \
  "warning-only fatal gate text not referenced as a substituteInPlace argument"

# Property 4: upstream resolution is documented next to the version guard.
assert_grep \
  "8c5442c01bb0a529c001b5082d051f61e8e6682d" \
  "upstream commit 8c5442c0 reference missing"

assert_grep \
  "openclaw/openclaw#135713" \
  "upstream PR openclaw/openclaw#135713 reference missing"

assert_grep \
  "Gao-OS/nixpkgs#34" \
  "downstream issue Gao-OS/nixpkgs#34 reference missing"

# Property 5: evaluate preConfigure for the patched and current release.
# A future version must retain common setup without targeting an obsolete chunk.
WORKDIR="$(mktemp -d)"
trap 'rm -rf -- "$WORKDIR"' EXIT
for version in 2026.8.2 2026.9.8; do
  sed "s/^  version = \"[^\"]*\";/  version = \"${version}\";/" \
    "$PKG" > "$WORKDIR/default.nix"
  nix-instantiate --eval --strict --json \
    --argstr packageFile "$WORKDIR/default.nix" \
    --expr '{ packageFile }: let
      package = import (builtins.toPath packageFile) {
        lib.optionalString = condition: value: if condition then value else "";
        buildNpmPackage = value: value;
        fetchurl = value: value;
        nodejs_24 = "node";
        makeWrapper = "wrapper";
        jq = "jq";
      };
    in package.preConfigure' > "$WORKDIR/${version}.json"
done

python3 - "$WORKDIR" <<'PY'
import json
import pathlib
import sys

directory = pathlib.Path(sys.argv[1])
old = json.loads((directory / "2026.8.2.json").read_text())
new = json.loads((directory / "2026.9.8.json").read_text())
chunk = "substituteInPlace dist/doctor-config-preflight-B-Zv4Qey.js"
assert chunk in old, "2026.8.2 must retain the warning-gate patch"
assert chunk not in new, "2026.9.8 must use the upstream warning policy"
for script in (old, new):
    assert "del(.scripts.preinstall" in script, "lifecycle script cleanup missing"
    assert "isSqliteWalResetSafeVersion" in script, "SQLite setup missing"
PY

echo "PASS: openclaw-warning-gate-patch (Gao-OS/nixpkgs#34)"
