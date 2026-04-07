# OpenClaw - Multi-channel AI gateway
#
# To update:
#   1. Change `version` below
#   2. Update `src.hash` (set to "" and nix will report the correct hash)
#   3. Regenerate package-lock.json using the helper script:
#        ./scripts/gen-openclaw-lockfile.sh <new-version>
#   4. Update `npmDepsHash` (set to "" and nix will report the correct hash)
#   5. Test: nix build .#openclaw
#
# Why the symlink step in postInstall:
#   The npm tarball ships 7 pre-built extension bundles under dist/extensions/
#   (slack, telegram, amazon-bedrock, discord, feishu, diffs, qqbot), each with
#   its own node_modules. openclaw's bundled dist/ chunks (e.g. sticker-cache-*.js)
#   are shared across extensions and import those packages (grammy, @slack/bolt,
#   @aws-sdk/client-bedrock, …) using bare specifiers. Node.js resolves bare
#   specifiers by walking up from the importing file — dist/*.js never reaches
#   dist/extensions/*/node_modules, so we expose them via the main node_modules.
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
  version = "2026.4.5";

  # Use the pre-built npm registry tarball. OpenClaw's build from source
  # requires pnpm, tsdown, and a complex multi-stage pipeline. The npm
  # tarball ships pre-compiled dist/ and is the official release artifact.
  src = fetchurl {
    url = "https://registry.npmjs.org/${pname}/-/${pname}-${version}.tgz";
    hash = "sha256-3x5XpflbaWj1rAvcr8X5cBeMBPSvhXeaUMqISHdD0NU=";
  };

  sourceRoot = "package";

  # Generated from package-lock.json (see update instructions above)
  npmDepsHash = "sha256-lMr4+nIrt/FCLLe0lCcOlzegnlhuvq40n3kSoCKYEu0=";

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

    # Expose bundled extension node_modules in the main node_modules so that
    # shared dist chunks can find them via normal Node.js resolution.
    lib="$out/lib/node_modules/openclaw"
    for ext_nm in "$lib/dist/extensions/"*/node_modules; do
      [ -d "$ext_nm" ] || continue
      for entry in "$ext_nm/"*; do
        name=$(basename "$entry")
        dest="$lib/node_modules/$name"
        if [[ "$name" == @* ]]; then
          # Scoped package scope dir (e.g. @slack, @grammyjs)
          mkdir -p "$dest"
          for sub in "$entry/"*; do
            subname=$(basename "$sub")
            [ -e "$dest/$subname" ] || ln -s "$sub" "$dest/$subname"
          done
        else
          [ -e "$dest" ] || ln -s "$entry" "$dest"
        fi
      done
    done
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
