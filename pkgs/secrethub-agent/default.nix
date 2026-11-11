{
  stdenv,
  lib,
  fetchurl,
  autoPatchelfHook,
  openssl,
  ncurses,
  zlib,
  coreutils,
  gnused,
  gawk,
  gnugrep,
}: let
  agentArch =
    if stdenv.hostPlatform.system == "x86_64-linux"
    then {
      name = "linux-amd64";
      hash = "sha256-G/Nbh0tsKsqRhG6xSNlnnSZ/41zpV6ewc5x5YDBik2Y=";
    }
    else if stdenv.hostPlatform.system == "aarch64-linux"
    then {
      name = "linux-arm64";
      hash = "sha256-Nuu+gw7nF529SCFQGzqG9xbPDwWX6G3Ye6YHIfTTP2w=";
    }
    else throw "Unsupported platform: ${stdenv.hostPlatform.system}";
in
  stdenv.mkDerivation rec {
    pname = "secrethub-agent";
    version = "1.0.0-rc.32";

    # Upstream Elixir release tarball (bundled ERTS), patched for the Nix store.
    src = fetchurl {
      url = "https://github.com/gsmlg-dev/secrethub/releases/download/v${version}/secrethub_agent-v${version}-${agentArch.name}.tar.gz";
      hash = agentArch.hash;
    };

    sourceRoot = ".";

    nativeBuildInputs = [autoPatchelfHook];
    buildInputs = [openssl ncurses zlib stdenv.cc.cc.lib];

    dontConfigure = true;
    dontBuild = true;
    # Stripping corrupts BEAM NIFs and is unnecessary for a prebuilt release.
    dontStrip = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r bin erts-* lib releases $out/
      [ -d config ] && cp -r config $out/
      rm -f $out/bin/*.bat $out/releases/*/*.bat

      # The release launchers shell out to sed/awk/grep/od; pin them so the
      # service does not depend on the caller's PATH.
      sed -i '1a export PATH="${lib.makeBinPath [coreutils gnused gawk gnugrep]}''${PATH:+:$PATH}"' \
        $out/bin/secrethub_agent
      runHook postInstall
    '';

    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      $out/bin/secrethub_agent version | grep -F "${version}"
      runHook postInstallCheck
    '';

    meta = with lib; {
      mainProgram = "secrethub_agent";
      homepage = "https://github.com/gsmlg-dev/secrethub";
      description = "SecretHub Agent daemon (prebuilt upstream release)";
      sourceProvenance = with sourceTypes; [binaryNativeCode binaryBytecode];
      platforms = ["x86_64-linux" "aarch64-linux"];
    };
  }
