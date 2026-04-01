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
  version = "2026.3.31";

  # Use the pre-built npm registry tarball. OpenClaw's build from source
  # requires pnpm, tsdown, and a complex multi-stage pipeline. The npm
  # tarball ships pre-compiled dist/ and is the official release artifact.
  src = fetchurl {
    url = "https://registry.npmjs.org/${pname}/-/${pname}-${version}.tgz";
    hash = "sha256-Y4oU4JbL0ixX538X8b+3BVrP0coDnksD6/TvZdr2KOE=";
  };

  sourceRoot = "package";

  # Generated from package-lock.json (see update instructions above)
  npmDepsHash = "sha256-QA/UpcKJn69YrMaiH1Rdsm3dlLanDIGuT6tGLR9PE8w=";

  nativeBuildInputs = [ makeWrapper jq ];

  # postPatch is inherited by the internal fetchNpmDeps derivation, which has
  # a minimal build environment — only copy the lockfile here.
  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  # preConfigure runs only in the main derivation (not in fetchNpmDeps).
  # Strip lifecycle scripts that try to invoke pnpm, which is not available
  # in the Nix sandbox. The npm tarball already ships pre-built dist/.
  preConfigure = ''
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
