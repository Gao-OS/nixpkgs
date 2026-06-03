{
  lib,
  stdenv,
  fetchFromGitHub,
  buildGoModule,
  makeWrapper,
  cacert,
  moreutils,
  jq,
  git,
  rsync,
  pkg-config,
  runCommand,
  python3,
  esbuild,
  nodejs_22,
  node-gyp,
  libsecret,
  libkrb5,
  libx11,
  libxkbfile,
  ripgrep,
  cctools,
  xcbuild,
  quilt,
  nixosTests,
  prefetch-npm-deps,
}:

let
  system = stdenv.hostPlatform.system;

  nodejs = nodejs_22;

  esbuild' = esbuild.override {
    buildGoModule =
      args:
      buildGoModule (
        args
        // rec {
          version = "0.27.2";
          src = fetchFromGitHub {
            owner = "evanw";
            repo = "esbuild";
            rev = "v${version}";
            hash = "sha256-JbJB3F1NQlmA5d0rdsLm4RVD24OPdV4QXpxW8VWbESA=";
          };
          vendorHash = "sha256-+BfxCyg0KkDQpHt/wycy/8CTG6YBA/VJvJFhhzUnSiQ=";
        }
      );
  };

  patchEsbuild = path: version: ''
    mkdir -p ${path}/node_modules/esbuild/bin
    jq "del(.scripts.postinstall)" ${path}/node_modules/esbuild/package.json | sponge ${path}/node_modules/esbuild/package.json
    sed -i 's/${version}/${esbuild'.version}/g' ${path}/node_modules/esbuild/lib/main.js
    ln -s -f ${lib.getExe esbuild'} ${path}/node_modules/esbuild/bin/esbuild
  '';

  vscodeTarget =
    {
      x86_64-linux = "linux-x64";
      aarch64-linux = "linux-arm64";
      x86_64-darwin = "darwin-x64";
      aarch64-darwin = "darwin-arm64";
    }
    .${system};

  # See https://github.com/NixOS/nixpkgs/pull/240001#discussion_r1244303617
  # VS Code needs this commit for display languages, cache busting, and bug reports.
  commit = "1c6fb2dc200eb57c5c7d612004e18a5e6ae8b0ed";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "code-server";
  version = "4.115.0";

  src = fetchFromGitHub {
    owner = "coder";
    repo = "code-server";
    rev = "v${finalAttrs.version}";
    fetchSubmodules = true;
    hash = "sha256-Hoi5QABYwRySGB9DNyEI6qMFYXCka3rfsE5j0Ww7Ax8=";
  };

  nodeModules =
    runCommand "code-server-node-modules"
      {
        inherit (finalAttrs) src;
        nativeBuildInputs = finalAttrs.nativeBuildInputs ++ [
          prefetch-npm-deps
        ];
        outputHashMode = "recursive";
        outputHashAlgo = "sha256";
        outputHash = "sha256-nsKsbSuIMvqKT9XVPIsEN6EgvnDvB7rAuUYZDLBBO4A=";
        env = {
          FORCE_EMPTY_CACHE = true;
          FORCE_GIT_DEPS = true;
          npm_config_progress = false;
          npm_config_cafile = "${cacert}/etc/ssl/certs/ca-bundle.crt";
        };
      }
      ''
        runPhase unpackPhase
        export HOME=$TMPDIR/home
        mkdir $out
        for p in $(find -name package-lock.json)
        do (
          echo "Prefetching $p"
          prefetch-npm-deps "$p" "$out/$(dirname $p)"
        )
        done
      '';

  nativeBuildInputs = [
    nodejs
    python3
    pkg-config
    makeWrapper
    git
    rsync
    jq
    moreutils
    prefetch-npm-deps
    quilt
  ];

  buildInputs = [
    libx11
    libxkbfile
    libkrb5
  ]
  ++ lib.optionals (!stdenv.hostPlatform.isDarwin) [
    libsecret
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    cctools
    xcbuild
  ];

  patches = [
    ./build-vscode-nogit.patch
  ];

  postPatch = ''
    export HOME=$PWD

    patchShebangs ./ci

    substituteInPlace ./ci/build/build-vscode.sh \
      --replace-fail '$(git rev-parse HEAD)' "${commit}"
    substituteInPlace ./ci/build/build-release.sh \
      --replace-fail '$(git rev-parse HEAD)' "${commit}"

    substituteInPlace ./lib/vscode/build/npm/postinstall.ts \
      --replace-fail "child_process.execSync('git config pull.rebase merges');" \
        "try { child_process.execSync('git config pull.rebase merges'); } catch {}" \
      --replace-fail "child_process.execSync('git config blame.ignoreRevsFile .git-blame-ignore-revs');" \
        "try { child_process.execSync('git config blame.ignoreRevsFile .git-blame-ignore-revs'); } catch {}"
  '';

  env = {
    NODE_OPTIONS = "--openssl-legacy-provider --max-old-space-size=4096";
    NODE_ENV = "development";
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
    ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
    NIX_NODEJS_BUILDNPMPACKAGE = "1";
    npm_config_nodedir = nodejs;
    npm_config_node_gyp = "${node-gyp}/lib/node_modules/node-gyp/bin/node-gyp.js";
    npm_config_offline = true;
    npm_config_progress = false;
    forceGitDeps = true;
  };

  preConfigure = ''
    export HOME=$TMPDIR/home
    mkdir -p $HOME
    cp -R $nodeModules $TMPDIR/cache
    chmod -R +w $TMPDIR/cache
  '';

  configurePhase = ''
    runHook preConfigure

    for p in $(find -name package-lock.json -exec dirname {} \;)
    do (
      echo "Setting up $p/node_modules"
      cd $p
      if [ -e node_modules ]
      then
        echo >&2 "File exists $p/node_modules"
        exit 0
      fi
      npm_config_cache=$TMPDIR/cache/$p npm ci --ignore-scripts
      patchShebangs node_modules
    )
    done

    mkdir -p $HOME/.node-gyp/${nodejs.version}
    echo 11 > $HOME/.node-gyp/${nodejs.version}/installVersion
    ln -sfv ${nodejs}/include $HOME/.node-gyp/${nodejs.version}

    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild

    quilt push -a

    export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
    export SKIP_SUBMODULE_DEPS=1
    export NODE_OPTIONS="--openssl-legacy-provider --max-old-space-size=4096"

    jq --slurp '.[0] * .[1]' "./lib/vscode/product.json" <(
      cat << EOF
    {
      "builtInExtensions": []
    }
    EOF
    ) | sponge ./lib/vscode/product.json

    sed -i '/update.mode/,/\}/{s/default:.*/default: "none",/g}' \
      lib/vscode/src/vs/platform/update/common/update.config.contribution.ts

    patch -p1 -i ${./remove-node-download.patch}

    patchShebangs .

    ${patchEsbuild "./lib/vscode/build" "0.27.2"}
    ${patchEsbuild "./lib/vscode/extensions" "0.27.2"}

    find -name ripgrep -type d \
      -execdir mkdir -p {}/bin \; \
      -execdir ln -s ${ripgrep}/bin/rg {}/bin/rg \;

    ${lib.optionalString stdenv.hostPlatform.isDarwin ''
      parcelWatcherPrebuild="./lib/vscode/remote/node_modules/@parcel/watcher-${vscodeTarget}/watcher.node"
      if [ ! -e "$parcelWatcherPrebuild" ]; then
        echo "No @parcel/watcher prebuild found at $parcelWatcherPrebuild" >&2
        find ./lib/vscode/remote/node_modules/@parcel -maxdepth 2 -type f >&2
        exit 1
      fi
      mkdir -p $TMPDIR/parcel-watcher
      cp "$parcelWatcherPrebuild" $TMPDIR/parcel-watcher/watcher.node
    ''}

    find -name package.json -type f -exec sh -c '
      if jq -e ".scripts.postinstall" {} >/dev/null
      then
        echo >&2 "Running postinstall script in $(dirname {})"
        npm --prefix=$(dirname {}) run postinstall
      fi
      exit 0
    ' \;
    patchShebangs .

  ''
  + lib.optionalString stdenv.hostPlatform.isDarwin ''
    pushd ./lib/vscode/remote/node_modules/@parcel/watcher
    mkdir -p ./build/Release
    cp $TMPDIR/parcel-watcher/watcher.node ./build/Release/watcher.node
    jq "del(.scripts) | .gypfile = false" ./package.json | sponge ./package.json
    popd
  ''
  + ''

    npm rebuild --offline
    npm rebuild --offline --prefix lib/vscode/remote

    npm run build
    VERSION=${finalAttrs.version} npm run build:vscode

    cp ${lib.getExe nodejs} ./lib/vscode-reh-web-${vscodeTarget}/node

    jq --slurp '.[0] * .[1]' ./package.json <(
      cat << EOF
    {
      "version": "${finalAttrs.version}"
    }
    EOF
    ) | sponge ./package.json

    KEEP_MODULES=1 npm run release

    npm prune --omit=dev --prefix release

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/libexec/code-server $out/bin

    cp -R -T release "$out/libexec/code-server"

    makeWrapper "${nodejs}/bin/node" "$out/bin/code-server" \
      --add-flags "$out/libexec/code-server/out/node/entry.js"

    runHook postInstall
  '';

  passthru = {
    prefetchNodeModules = lib.overrideDerivation finalAttrs.nodeModules (d: {
      outputHash = lib.fakeSha256;
    });
    tests = {
      inherit (nixosTests) code-server;
    };
    executableName = "code-server";
    longName = "Visual Studio Code Server";
  };

  meta = {
    changelog = "https://github.com/coder/code-server/blob/${finalAttrs.src.rev}/CHANGELOG.md";
    description = "Run VS Code on a remote server";
    longDescription = ''
      code-server is VS Code running on a remote server, accessible through the
      browser.
    '';
    homepage = "https://github.com/coder/code-server";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [
      henkery
      code-asher
    ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
    ];
    mainProgram = "code-server";
  };
})
