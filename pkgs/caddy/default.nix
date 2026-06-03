{
  stdenv,
  lib,
  fetchurl,
}: let
  caddyArch =
    if stdenv.hostPlatform.system == "x86_64-linux"
    then {
      name = "linux_amd64";
      hash = "sha256-ym4zeRWwX9X3qluIBtQHjm7VVtOQvE8UGtJrEzVOPOo=";
    }
    else if stdenv.hostPlatform.system == "aarch64-linux"
    then {
      name = "linux_arm64";
      hash = "sha256-1tpbfROWPTrODIC48a12X94RzumvbUPVBhQxYhlibvA=";
    }
    else if stdenv.hostPlatform.system == "x86_64-darwin"
    then {
      name = "darwin_amd64";
      hash = "sha256-Y0lPqlFzNPsdR7CmM/r9eCA+AYt+2YSH6/Gw4yBDZnA=";
    }
    else if stdenv.hostPlatform.system == "aarch64-darwin"
    then {
      name = "darwin_arm64";
      hash = "sha256-8adRmNFLE6wAs8Ha18k+xmqgn8gnOlFZO3nZL8cdVE4=";
    }
    else throw "Unsupported platform: ${stdenv.hostPlatform.system}";
in
  stdenv.mkDerivation rec {
    pname = "caddy";
    version = "2.11.2";

    src = fetchurl {
      url = "https://github.com/gsmlg-ci/caddy/releases/download/v${version}/caddy_${caddyArch.name}";
      hash = caddyArch.hash;
    };
    dontUnpack = true;

    sourceRoot = ".";

    installPhase = ''
      runHook preInstall
      install -m755 -D ${src} $out/bin/caddy
      runHook postInstall
    '';

    meta = with lib; {
      mainProgram = "caddy";
      homepage = "https://github.com/gsmlg-ci/caddy";
      description = "GSMLG CI custom caddy build";
      platforms = [
        "aarch64-linux"
        "x86_64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
    };
  }
