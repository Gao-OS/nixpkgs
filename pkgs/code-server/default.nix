{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchNpmDeps,
  buildGoModule,
  makeWrapper,
  cacert,
  moreutils,
  jq,
  git,
  rsync,
  pkg-config,
  yarn,
  python3,
  esbuild,
  nodejs,
  node-gyp,
  libsecret,
  xorg,
  ripgrep,
  cctools,
  xcbuild,
  quilt,
  nixosTests,
}:

let
  system = stdenv.hostPlatform.system;

  python = python3;
  yarn' = yarn.override { inherit nodejs; };
  defaultYarnOpts = [ ];

  esbuild' = esbuild.override {
    buildGoModule =
      args:
      buildGoModule (
        args
        // rec {
          version = "0.16.17";
          src = fetchFromGitHub {
            owner = "evanw";
            repo = "esbuild";
            rev = "v${version}";
            hash = "sha256-8L8h0FaexNsb3Mj6/ohA37nYLFogo5wXkAhGztGUUsQ=";
          };
          vendorHash = "sha256-+BfxCyg0KkDQpHt/wycy/8CTG6YBA/VJvJFhhzUnSiQ=";
        }
      );
  };

  # replaces esbuild's download script with a binary from nixpkgs
  patchEsbuild = path: version: ''
    mkdir -p ${path}/node_modules/esbuild/bin
    jq "del(.scripts.postinstall)" ${path}/node_modules/esbuild/package.json | sponge ${path}/node_modules/esbuild/package.json
    sed -i 's/${version}/${esbuild'.version}/g' ${path}/node_modules/esbuild/lib/main.js
    ln -s -f ${esbuild'}/bin/esbuild ${path}/node_modules/esbuild/bin/esbuild
  '';

  # Comment from @code-asher, the code-server maintainer
  # See https://github.com/NixOS/nixpkgs/pull/240001#discussion_r1244303617
  #
  # If the commit is missing it will break display languages (Japanese, Spanish,
  # etc). For some reason VS Code has a hard dependency on the commit being set
  # for that functionality.
  # The commit is also used in cache busting. Without the commit you could run
  # into issues where the browser is loading old versions of assets from the
  # cache.
  # Lastly, it can be helpful for the commit to be accurate in bug reports
  # especially when they are built outside of our CI as sometimes the version
  # numbers can be unreliable (since they are arbitrarily provided).
  #
  # To compute the commit when upgrading this derivation, do:
  # `$ git rev-parse <git-rev>` where <git-rev> is the git revision of the `src`
  # Example: `$ git rev-parse v4.16.1`
  commit = "811ec6c1d60add2eb92446161ca812828fdbaa7f";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "code-server";
  version = "4.105.1";

  src = fetchFromGitHub {
    owner = "coder";
    repo = "code-server";
    rev = "v${finalAttrs.version}";
    fetchSubmodules = true;
    hash = "sha256-BdJU8Guj5YUQ9eWmwETB00EvS71AiDI0YH+pOpR3Hjw=";
  };

  yarnCache = stdenv.mkDerivation {
    name = "${finalAttrs.pname}-${finalAttrs.version}-${system}-yarn-cache";
    inherit (finalAttrs) src;

    nativeBuildInputs = [
      yarn'
      git
      cacert
    ];

    buildPhase = ''
      runHook preBuild

      export HOME=$PWD
      export GIT_SSL_CAINFO="${cacert}/etc/ssl/certs/ca-bundle.crt"

      yarn --cwd "./vendor" install --modules-folder modules --ignore-scripts --frozen-lockfile

      yarn config set yarn-offline-mirror $out
      find "$PWD" -name "yarn.lock" -printf "%h\n" | \
        xargs -I {} yarn --cwd {} \
          --frozen-lockfile --ignore-scripts --ignore-platform \
          --ignore-engines --no-progress --non-interactive

      find ./lib/vscode -name "yarn.lock" -printf "%h\n" | \
        xargs -I {} yarn --cwd {} \
          --ignore-scripts --ignore-engines

      runHook postBuild
    '';

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-3xDinhLSZJoz7N7Z/+ttDLh82fwyunOTeSE3ULOZcHA=";
  };

  npmDeps = fetchNpmDeps {
    src = finalAttrs.src;
    hash = "sha256-mfKXZtUizQ8kzJOvCc9weLhdSFMAuLWiV/hxePlxF6k=";
  };

  vscodeNpmDeps = fetchNpmDeps {
    # Apply patch to remove git dependency before fetching npm deps
    src = stdenv.mkDerivation {
      name = "vscode-source";
      src = "${finalAttrs.src}/lib/vscode";
      patches = [ ./use-npm-parcel-watcher.patch ];
      postPatch = ''
        # Replace git URL with npm registry URL for @parcel/watcher in package-lock.json
        sed -i 's|"resolved": "git+ssh://git@github.com/parcel-bundler/watcher.git#[^"]*"|"resolved": "https://registry.npmjs.org/@parcel/watcher/-/watcher-2.5.1.tgz"|g' package-lock.json
        # Also update the integrity hash to match npm registry version
        sed -i '/node_modules\/@parcel\/watcher"/,/"integrity":/ s|"integrity": "sha512-[^"]*"|"integrity": "sha512-dfUnCxiN9H4ap84DvD2ubjw+3vUNpstxa0TneY/Paat8a3R4uQZDLSvWjmznAY/DoahqTHl9V46HF/Zs3F29pg=="|' package-lock.json
      '';
      dontBuild = true;
      installPhase = "cp -r . $out";
    };
    hash = "sha256-CFDUyINXtJ52f4tAYbhGIQPNZe3/w1NHlYnAuOv6t5Q=";
  };

  vscodeBuildNpmDeps = fetchNpmDeps {
    src = "${finalAttrs.src}/lib/vscode/build";
    hash = "sha256-uF0pRPorBej3OXH+Mhq7wT28I8NBFLdZ1tdIDFpMQmU=";
  };

  nativeBuildInputs = [
    nodejs
    yarn'
    python
    pkg-config
    makeWrapper
    git
    rsync
    jq
    moreutils
    quilt
  ];

  buildInputs = [
    xorg.libX11
    xorg.libxkbfile
  ]
  ++ lib.optionals (!stdenv.hostPlatform.isDarwin) [
    libsecret
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    cctools
    xcbuild
  ];

  patches = [
    # Remove all git calls from the VS Code build script except `git rev-parse
    # HEAD` which is replaced in postPatch with the commit.
    ./build-vscode-nogit.patch
    # Fix tsc command to use yarn tsc for proper PATH resolution
    ./fix-tsc-path.patch
    # Fix empty local extensions stream (v4.105.1 builds for web have no local extensions)
    ./fix-empty-extensions.patch
  ];

  postPatch = ''
    export HOME=$PWD

    patchShebangs ./ci

    # inject git commit
    substituteInPlace ./ci/build/build-vscode.sh \
      --replace-fail '$(git rev-parse HEAD)' "${commit}"
    substituteInPlace ./ci/build/build-release.sh \
      --replace-fail '$(git rev-parse HEAD)' "${commit}"

    # Patch lib/vscode to replace @parcel/watcher git dependency with npm version
    sed -i 's|"@parcel/watcher": "parcel-bundler/watcher#[^"]*"|"@parcel/watcher": "^2.5.1"|g' lib/vscode/package.json
    sed -i 's|"resolved": "git+ssh://git@github.com/parcel-bundler/watcher.git#[^"]*"|"resolved": "https://registry.npmjs.org/@parcel/watcher/-/watcher-2.5.1.tgz"|g' lib/vscode/package-lock.json
    # Also update the integrity hash to match npm registry version
    sed -i '/node_modules\/@parcel\/watcher"/,/"integrity":/ s|"integrity": "sha512-[^"]*"|"integrity": "sha512-dfUnCxiN9H4ap84DvD2ubjw+3vUNpstxa0TneY/Paat8a3R4uQZDLSvWjmznAY/DoahqTHl9V46HF/Zs3F29pg=="|' lib/vscode/package-lock.json
  '';

  configurePhase = ''
    runHook preConfigure

    # run yarn offline by default
    echo '--install.offline true' >> .yarnrc

    # set default yarn opts
    ${lib.concatMapStrings (option: ''
      yarn --offline config set ${option}
    '') defaultYarnOpts}

    # set offline mirror to yarn cache we created in previous steps
    yarn --offline config set yarn-offline-mirror "${finalAttrs.yarnCache}"

    # skip unnecessary electron download
    export ELECTRON_SKIP_BINARY_DOWNLOAD=1

    # set nodedir to prevent node-gyp from downloading headers
    # taken from https://nixos.org/manual/nixpkgs/stable/#javascript-tool-specific
    mkdir -p $HOME/.node-gyp/${nodejs.version}
    echo 9 > $HOME/.node-gyp/${nodejs.version}/installVersion
    ln -sfv ${nodejs}/include $HOME/.node-gyp/${nodejs.version}
    export npm_config_nodedir=${nodejs}

    # use updated node-gyp. fixes the following error on Darwin:
    # PermissionError: [Errno 1] Operation not permitted: '/usr/sbin/pkgutil'
    export npm_config_node_gyp=${node-gyp}/lib/node_modules/node-gyp/bin/node-gyp.js

    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild

    # Apply patches.
    quilt push -a

    export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
    export SKIP_SUBMODULE_DEPS=1
    export NODE_OPTIONS="--openssl-legacy-provider --max-old-space-size=4096"

    # Remove all built-in extensions, as these are 3rd party extensions that
    # get downloaded from the VS Code marketplace.
    jq --slurp '.[0] * .[1]' "./lib/vscode/product.json" <(
      cat << EOF
    {
      "builtInExtensions": []
    }
    EOF
    ) | sponge ./lib/vscode/product.json

    # Disable automatic updates.
    sed -i '/update.mode/,/\}/{s/default:.*/default: "none",/g}' \
      lib/vscode/src/vs/platform/update/common/update.config.contribution.ts

    # Patch out remote download of nodejs from build script.
    patch -p1 -i ${./remove-node-download.patch}

    # Install dependencies.
    patchShebangs .
    # Install yarn dependencies (lib/vscode and subdirectories)
    find . -name "yarn.lock" -printf "%h\n" | \
        xargs -I {} yarn --cwd {} \
          --offline --frozen-lockfile --ignore-scripts --ignore-engines
    # Install root npm dependencies (v4.105.1 uses npm for root, not yarn)
    export npm_config_cache="${finalAttrs.npmDeps}"
    npm ci --offline --ignore-scripts --cache "${finalAttrs.npmDeps}"
    patchShebangs .

    # Note: Kerberos removal step from v4.91.1 removed - not needed in v4.105.1

    # Put ripgrep binary into bin, so post-install does not try to download it.
    find -name ripgrep -type d \
      -execdir mkdir -p {}/bin \; \
      -execdir ln -s ${ripgrep}/bin/rg {}/bin/rg \;

    # Run post-install scripts after patching.
    find ./lib/vscode \( -path "*/node_modules/*" -or -path "*/extensions/*" \) \
      -and -type f -name "yarn.lock" -printf "%h\n" | \
        xargs -I {} sh -c 'jq -e ".scripts.postinstall" {}/package.json >/dev/null && yarn --cwd {} postinstall --frozen-lockfile --offline || true'
    patchShebangs .

    # Use esbuild from nixpkgs (must be after post-install scripts).
    # Only patch if esbuild directories exist (structure may have changed in v4.105.1)
    if [ -f "./lib/vscode/build/node_modules/esbuild/package.json" ]; then
      ${patchEsbuild "./lib/vscode/build" "0.12.6"}
    fi
    if [ -f "./lib/vscode/extensions/node_modules/esbuild/package.json" ]; then
      ${patchEsbuild "./lib/vscode/extensions" "0.11.23"}
    fi

  ''
  + lib.optionalString stdenv.hostPlatform.isDarwin ''
    # Use prebuilt binary for @parcel/watcher, which requires macOS SDK 10.13+
    # (see issue #101229).
    pushd ./lib/vscode/remote/node_modules/@parcel/watcher
    mkdir -p ./build/Release
    mv ./prebuilds/darwin-x64/node.napi.glibc.node ./build/Release/watcher.node
    jq "del(.scripts) | .gypfile = false" ./package.json | sponge ./package.json
    popd
  ''
  + ''

    # Build binary packages (argon2, node-pty, etc).
    # Use --ignore-scripts to prevent postinstall from fetching test dependencies
    npm rebuild --offline --ignore-scripts
    npm rebuild --offline --ignore-scripts --prefix lib/vscode/remote

    # Install lib/vscode dependencies (VS Code switched to npm in v4.105.1)
    # Copy npm cache to writable location since npm needs to write to it
    export npm_vscode_cache="$TMPDIR/npm-vscode-cache"
    cp -r "${finalAttrs.vscodeNpmDeps}" "$npm_vscode_cache"
    chmod -R +w "$npm_vscode_cache"
    npm ci --prefix lib/vscode --offline --ignore-scripts --cache "$npm_vscode_cache"

    # Install lib/vscode/build dependencies
    export npm_vscode_build_cache="$TMPDIR/npm-vscode-build-cache"
    cp -r "${finalAttrs.vscodeBuildNpmDeps}" "$npm_vscode_build_cache"
    chmod -R +w "$npm_vscode_build_cache"
    npm ci --prefix lib/vscode/build --offline --ignore-scripts --cache "$npm_vscode_build_cache"

    # Add node_modules/.bin to PATH for build tools like tsc and gulp
    export PATH="$PWD/node_modules/.bin:$PWD/lib/vscode/node_modules/.bin:$PATH"

    # Build code-server and VS Code.
    yarn build
    VERSION=${finalAttrs.version} yarn build:vscode

    # Inject version into package.json.
    jq --slurp '.[0] * .[1]' ./package.json <(
      cat << EOF
    {
      "version": "${finalAttrs.version}"
    }
    EOF
    ) | sponge ./package.json

    # Create release, keeping all dependencies.
    KEEP_MODULES=1 yarn release

    # Prune development dependencies.  We only need to do this for the root as
    # the VS Code build process already does this for VS Code.
    npm prune --omit=dev --prefix release

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/libexec/code-server $out/bin

    # copy release to libexec path
    cp -R -T release "$out/libexec/code-server"

    # create wrapper
    makeWrapper "${nodejs}/bin/node" "$out/bin/code-server" \
      --add-flags "$out/libexec/code-server/out/node/entry.js"

    runHook postInstall
  '';

  passthru = {
    prefetchYarnCache = lib.overrideDerivation finalAttrs.yarnCache (d: {
      outputHash = lib.fakeSha256;
    });
    tests = {
      inherit (nixosTests) code-server;
    };
    # vscode-with-extensions compatibility
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
      offline
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
