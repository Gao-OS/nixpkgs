#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/gen-openclaw-lockfile.sh"
TMP_ROOT="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

create_source_repo() {
  local repo="$1"
  local version="$2"
  local extension_workspace_dependency="${3:-@openclaw/ai}"

  mkdir -p "$repo/extensions/example"
  git -C "$repo" init -q
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "OpenClaw updater test"

  cat > "$repo/package.json" <<EOF
{
  "name": "openclaw",
  "version": "${version}",
  "dependencies": {
    "@openclaw/ai": "workspace:*"
  },
  "devDependencies": {}
}
EOF

  cat > "$repo/extensions/example/package.json" <<'EOF'
{
  "name": "@openclaw/example",
  "dependencies": {
EOF
  cat >> "$repo/extensions/example/package.json" <<EOF
    "${extension_workspace_dependency}": "workspace:*",
EOF
  cat >> "$repo/extensions/example/package.json" <<'EOF'
    "external-package": "1.2.3"
  }
}
EOF

  git -C "$repo" add package.json extensions/example/package.json
  git -C "$repo" commit -qm "fixture"
  git -C "$repo" tag "v${version}"
}

create_exact_revision_tag() {
  local repo="$1"
  local version="$2"

  python3 - "$repo/package.json" "$version" <<'PY'
import json
import sys

path, version = sys.argv[1:]
with open(path) as source:
    package = json.load(source)
package["version"] = version
with open(path, "w") as target:
    json.dump(package, target, indent=2)
PY
  git -C "$repo" add package.json
  git -C "$repo" commit -qm "exact revision fixture"
  git -C "$repo" tag "v${version}"
}

create_npm_tarball() {
  local tarball="$1"
  local version="$2"
  local package_dir

  package_dir="$(dirname "$tarball")/package"
  mkdir -p "$package_dir"
  cat > "$package_dir/package.json" <<EOF
{
  "name": "openclaw",
  "version": "${version}",
  "dependencies": {
    "@openclaw/ai": "${version}"
  },
  "optionalDependencies": {
    "sqlite-vec": "0.1.9"
  },
  "devDependencies": {}
}
EOF
  tar -czf "$tarball" -C "$(dirname "$package_dir")" package/package.json
  rm -rf "$package_dir"
}

create_mock_npm() {
  local bin_dir="$1"

  mkdir -p "$bin_dir"
  cat > "$bin_dir/npm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if grep -R '"workspace:' package.json >/dev/null; then
  echo 'npm error Unsupported URL Type "workspace:": workspace:*' >&2
  exit 1
fi

python3 - <<'PY'
import json

with open("package.json") as source:
    package = json.load(source)

with open("package-lock.json", "w") as target:
    json.dump(
        {
            "name": package["name"],
            "version": package["version"],
            "lockfileVersion": 3,
            "packages": {"": package},
        },
        target,
    )
PY
EOF
  chmod +x "$bin_dir/npm"
}

run_generator() {
  local version="$1"
  local repo="$2"
  local tarball="$3"
  local workdir="$4"
  local dest="$5"
  local mock_bin="$6"
  local repo_url="file://${repo}"

  mkdir -p "$dest" "$workdir"
  PATH="${mock_bin}:$PATH" \
    TMPDIR="$workdir" \
    OPENCLAW_REPO_URL="$repo_url" \
    OPENCLAW_TARBALL_URL="file://${tarball}" \
    OPENCLAW_DEST_DIR="$dest" \
    "$SCRIPT" "$version"
}

test_numeric_publish_revision_uses_base_source_tag() {
  local case_dir="${TMP_ROOT}/numeric-revision"
  local repo="${case_dir}/source"
  local tarball="${case_dir}/openclaw-2026.7.1-2.tgz"
  local output

  mkdir -p "$case_dir"
  create_source_repo "$repo" "2026.7.1"
  create_npm_tarball "$tarball" "2026.7.1-2"
  create_mock_npm "${case_dir}/bin"

  if ! output="$(
    run_generator \
      "2026.7.1-2" \
      "$repo" \
      "$tarball" \
      "${case_dir}/work" \
      "${case_dir}/dest" \
      "${case_dir}/bin" 2>&1
  )"; then
    echo "$output" >&2
    fail "numeric npm publish revision did not fall back to v2026.7.1"
  fi

  grep -F "Using source tag v2026.7.1" <<<"$output" >/dev/null ||
    fail "generator did not report the base source tag"
}

test_exact_source_tag_takes_precedence() {
  local case_dir="${TMP_ROOT}/exact-tag"
  local repo="${case_dir}/source"
  local tarball="${case_dir}/openclaw-2026.7.1-2.tgz"
  local output

  mkdir -p "$case_dir"
  create_source_repo "$repo" "2026.7.1"
  create_exact_revision_tag "$repo" "2026.7.1-2"
  create_npm_tarball "$tarball" "2026.7.1-2"
  create_mock_npm "${case_dir}/bin"

  output="$(
    run_generator \
      "2026.7.1-2" \
      "$repo" \
      "$tarball" \
      "${case_dir}/work" \
      "${case_dir}/dest" \
      "${case_dir}/bin" 2>&1
  )"

  grep -F "Using source tag v2026.7.1-2" <<<"$output" >/dev/null ||
    fail "generator did not prefer the exact source tag"
}

test_base_source_tag_version_must_match() {
  local case_dir="${TMP_ROOT}/mismatched-base-tag"
  local repo="${case_dir}/source"
  local tarball="${case_dir}/openclaw-2026.7.1-2.tgz"
  local output

  mkdir -p "$case_dir"
  create_source_repo "$repo" "2026.7.0"
  git -C "$repo" tag -d v2026.7.0 >/dev/null
  git -C "$repo" tag v2026.7.1
  create_npm_tarball "$tarball" "2026.7.1-2"
  create_mock_npm "${case_dir}/bin"

  if output="$(
    run_generator \
      "2026.7.1-2" \
      "$repo" \
      "$tarball" \
      "${case_dir}/work" \
      "${case_dir}/dest" \
      "${case_dir}/bin" 2>&1
  )"; then
    fail "generator accepted a base tag with a mismatched package version"
  fi

  grep -F "Source tag v2026.7.1 contains package version 2026.7.0" <<<"$output" >/dev/null ||
    fail "generator did not explain the base tag version mismatch"
}

test_remote_query_errors_do_not_trigger_fallback() {
  local case_dir="${TMP_ROOT}/remote-error"
  local tarball="${case_dir}/openclaw-2026.7.1-2.tgz"
  local output

  mkdir -p "$case_dir/dest"
  create_npm_tarball "$tarball" "2026.7.1-2"
  create_mock_npm "${case_dir}/bin"

  if output="$(
    PATH="${case_dir}/bin:$PATH" \
      TMPDIR="${case_dir}" \
      OPENCLAW_REPO_URL="file://${case_dir}/missing-repository" \
      OPENCLAW_TARBALL_URL="file://${tarball}" \
      OPENCLAW_DEST_DIR="${case_dir}/dest" \
      "$SCRIPT" "2026.7.1-2" 2>&1
  )"; then
    fail "generator treated a remote query error as a missing exact tag"
  fi

  grep -F "Failed to query exact source tag v2026.7.1-2" <<<"$output" >/dev/null ||
    fail "generator did not preserve the remote query error"
}

test_published_manifest_replaces_workspace_dependencies() {
  local case_dir="${TMP_ROOT}/published-manifest"
  local repo="${case_dir}/source"
  local tarball="${case_dir}/openclaw-2026.7.1.tgz"
  local dest="${case_dir}/dest"

  mkdir -p "$case_dir"
  create_source_repo "$repo" "2026.7.1"
  create_npm_tarball "$tarball" "2026.7.1"
  create_mock_npm "${case_dir}/bin"

  run_generator \
    "2026.7.1" \
    "$repo" \
    "$tarball" \
    "${case_dir}/work" \
    "$dest" \
    "${case_dir}/bin" >/dev/null ||
    fail "generator did not accept the published npm manifest"

  python3 - "$dest/package.json" <<'PY'
import json
import sys

with open(sys.argv[1]) as source:
    package = json.load(source)

assert package["dependencies"]["@openclaw/ai"] == "2026.7.1"
assert package["dependencies"]["external-package"] == "1.2.3"
assert package["optionalDependencies"]["sqlite-vec"] == "0.1.9"
assert not any(
    isinstance(version, str) and version.startswith("workspace:")
    for version in package["dependencies"].values()
)
PY
}

test_unknown_runtime_workspace_dependency_fails() {
  local case_dir="${TMP_ROOT}/unknown-workspace"
  local repo="${case_dir}/source"
  local tarball="${case_dir}/openclaw-2026.7.1.tgz"
  local output

  mkdir -p "$case_dir"
  create_source_repo "$repo" "2026.7.1" "@openclaw/internal"
  create_npm_tarball "$tarball" "2026.7.1"
  create_mock_npm "${case_dir}/bin"

  if output="$(
    run_generator \
      "2026.7.1" \
      "$repo" \
      "$tarball" \
      "${case_dir}/work" \
      "${case_dir}/dest" \
      "${case_dir}/bin" 2>&1
  )"; then
    fail "generator silently dropped an unknown runtime workspace dependency"
  fi

  grep -F "Unresolved workspace dependency @openclaw/internal" <<<"$output" >/dev/null ||
    fail "generator did not explain the unresolved workspace dependency"
}

test_workdir_environment_cannot_delete_arbitrary_path() {
  local case_dir="${TMP_ROOT}/workdir-safety"
  local repo="${case_dir}/source"
  local tarball="${case_dir}/openclaw-2026.7.1.tgz"
  local sentinel="${case_dir}/sentinel"

  mkdir -p "$case_dir/dest" "$sentinel"
  touch "$sentinel/must-survive"
  create_source_repo "$repo" "2026.7.1"
  create_npm_tarball "$tarball" "2026.7.1"
  create_mock_npm "${case_dir}/bin"

  PATH="${case_dir}/bin:$PATH" \
    TMPDIR="${case_dir}" \
    OPENCLAW_REPO_URL="file://${repo}" \
    OPENCLAW_TARBALL_URL="file://${tarball}" \
    OPENCLAW_WORKDIR="$sentinel" \
    OPENCLAW_DEST_DIR="${case_dir}/dest" \
    "$SCRIPT" "2026.7.1" >/dev/null

  [ -f "$sentinel/must-survive" ] ||
    fail "generator deleted an arbitrary OPENCLAW_WORKDIR path"
}

test_numeric_publish_revision_uses_base_source_tag
test_exact_source_tag_takes_precedence
test_base_source_tag_version_must_match
test_remote_query_errors_do_not_trigger_fallback
test_published_manifest_replaces_workspace_dependencies
test_unknown_runtime_workspace_dependency_fails
test_workdir_environment_cannot_delete_arbitrary_path
echo "PASS: gen-openclaw-lockfile"
