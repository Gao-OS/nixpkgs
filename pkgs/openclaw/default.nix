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
  version = "2026.8.2";

  # Use the pre-built npm registry tarball. OpenClaw's build from source
  # requires pnpm, tsdown, and a complex multi-stage pipeline. The npm
  # tarball ships pre-compiled dist/ and is the official release artifact.
  src = fetchurl {
    url = "https://registry.npmjs.org/${pname}/-/${pname}-${version}.tgz";
    hash = "sha256-IOnC8WdC386/shUE5RBn0x4AChlXcSb/T6sRfl6H2+I=";
  };

  sourceRoot = "package";

  # Generated from package-lock.json (see update instructions above)
  npmDepsHash = "sha256-tGUcnXNvzZjfXRPfS+/sOv+r6BOdwuVbVgb+d0fG9MI=";

  nativeBuildInputs = [ makeWrapper jq ];

  # postPatch is inherited by the internal fetchNpmDeps derivation, which has
  # a minimal build environment — only copy generated npm metadata here.
  postPatch = ''
    rm -f npm-shrinkwrap.json
    cp ${./package.json} package.json
    cp ${./package-lock.json} package-lock.json
  '';

  # preConfigure runs only in the main derivation (not in fetchNpmDeps).
  # Strip lifecycle scripts that try to invoke pnpm or enforce version gates
  # that are not applicable in the Nix sandbox. The npm tarball already ships
  # pre-built dist/.
  preConfigure = ''
    jq 'del(.scripts.preinstall, .scripts.prepack, .scripts.prepare, .scripts.postinstall, .scripts.build)' \
      package.json > package.json.tmp && mv package.json.tmp package.json

    # The bundled Node.js SQLite is usable here despite OpenClaw's version gate.
    for file in $(grep -rl 'if (isSqliteWalResetSafeVersion(version)) return;' dist/ || true); do
      substituteInPlace "$file" \
        --replace-fail \
          'if (isSqliteWalResetSafeVersion(version)) return;' \
          'return;'
    done
  '';

  # The npm tarball already contains pre-built dist/, no build needed
  dontNpmBuild = true;

  nodejs = nodejs_24;

  npmFlags = [ "--legacy-peer-deps" "--ignore-scripts" ];

  postInstall = ''
    # Wrap the entry point with the correct node version
    makeWrapper ${nodejs_24}/bin/node "$out/bin/openclaw" \
      --add-flags "$out/lib/node_modules/openclaw/openclaw.mjs"

    # The pre-built npm tarball ships a `.openclaw-lifecycle-pending`
    # marker; on first invocation the runtime tries
    # `mkdir .openclaw-lifecycle-lock` inside the package directory and
    # crashes against the read-only Nix store. Run the upstream
    # postinstall (which calls `completePackageLifecycle()` and clears
    # the marker) so the gateway starts in a clean state. Preinstall
    # remains skipped because its `enforceSupportedNodeRuntime` rejects
    # Node <24.15.0; the bundled postinstall has no version gate.
    lib="$out/lib/node_modules/openclaw"
    ${nodejs_24}/bin/node "$lib/scripts/postinstall-bundled-plugins.mjs" \
      || echo "openclaw postinstall script failed; relying on marker cleanup only"
    # Defense-in-depth: even if the upstream script changes shape in the
    # future, ensure the marker never ships in the Nix output.
    rm -f "$lib/.openclaw-lifecycle-pending"

    # Expose bundled extension node_modules in the main node_modules so that
    # shared dist chunks can find them via normal Node.js resolution.
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
