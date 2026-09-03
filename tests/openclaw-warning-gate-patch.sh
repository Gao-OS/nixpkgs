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

# Property 2: substituteInPlace must use --replace-fail so an upstream rename
# of the chunk fails the build (the desired signal to revisit the patch).
assert_grep \
  "--replace-fail" \
  "substituteInPlace must use --replace-fail so upstream renames fail the build"

# Property 3: original buggy text referenced verbatim so substituteInPlace can
# match it in the bundled dist/ tree.
assert_grep \
  "if (params.startupMigrationWarnings.length > 0) throwStartupMigrationRefusal" \
  "warning-only fatal gate text not referenced as a substituteInPlace argument"

# Property 4: removal triggers documented in adjacent comments so a future
# bump that ships openclaw@>=2026.9.1 stable (which carries 8c5442c0 on its
# mainline tarball) makes the removal a visible code-review decision, not a
# silent one.
assert_grep \
  "8c5442c01bb0a529c001b5082d051f61e8e6682d" \
  "upstream commit 8c5442c0 reference missing"

assert_grep \
  "openclaw/openclaw#135713" \
  "upstream PR openclaw/openclaw#135713 reference missing"

assert_grep \
  "Gao-OS/nixpkgs#34" \
  "downstream issue Gao-OS/nixpkgs#34 reference missing"

echo "PASS: openclaw-warning-gate-patch (Gao-OS/nixpkgs#34)"
