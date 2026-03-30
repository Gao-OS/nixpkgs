# OpenClaw - Multi-channel AI gateway
#
# To update:
#   1. Change `version` below
#   2. Update `src.hash` (set to "" and nix will report the correct hash)
#   3. Regenerate package-lock.json:
#        npm pack openclaw@<new-version> && tar xzf openclaw-*.tgz
#        cd package && npm install --package-lock-only --ignore-scripts
#        cp package-lock.json <this-directory>/package-lock.json
#   4. Update `npmDepsHash` (set to "" and nix will report the correct hash)
#   5. Test: nix build .#openclaw
{
  lib,
  buildNpmPackage,
  fetchurl,
  nodejs_24,
  makeWrapper,
  jq,
}:

buildNpmPackage rec {
  pname = "openclaw";
  version = "2026.3.28";

  # Use the pre-built npm registry tarball. OpenClaw's build from source
  # requires pnpm, tsdown, and a complex multi-stage pipeline. The npm
  # tarball ships pre-compiled dist/ and is the official release artifact.
  src = fetchurl {
    url = "https://registry.npmjs.org/${pname}/-/${pname}-${version}.tgz";
    hash = "sha256-/XCaOfXRTAL3c/N+GKq8D1GAw3N7Jvce+pCwba/D7cI=";
  };

  sourceRoot = "package";

  # Generated from package-lock.json (see update instructions above)
  npmDepsHash = "sha256-s2aCZtLkuzPXT+f/5udPd+MnwTak5zC7JA0QnasF9w0=";

  nativeBuildInputs = [ makeWrapper jq ];

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
    # Strip lifecycle scripts that try to run pnpm (not available in sandbox).
    # The npm tarball already ships pre-built dist/, so these are unnecessary.
    jq 'del(.scripts.prepack, .scripts.prepare, .scripts.postinstall, .scripts.build)' \
      package.json > package.json.tmp && mv package.json.tmp package.json
  '';

  # The npm tarball already contains pre-built dist/, no build needed
  dontNpmBuild = true;

  nodejs = nodejs_24;

  npmInstallFlags = [ "--ignore-scripts" ];

  postInstall = ''
    # Wrap the entry point with the correct node version
    makeWrapper ${nodejs_24}/bin/node "$out/bin/openclaw" \
      --add-flags "$out/lib/node_modules/openclaw/openclaw.mjs"
  '';

  meta = with lib; {
    description = "Multi-channel AI gateway with extensible messaging integrations";
    homepage = "https://github.com/openclaw/openclaw";
    license = licenses.mit;
    mainProgram = "openclaw";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  };
}
