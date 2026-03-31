{
  stdenv,
  lib,
  fetchurl,
}: let
  caddyArch =
    if stdenv.hostPlatform.system == "x86_64-linux"
    then {
      name = "linux_amd64";
      hash = "sha256-4ip4SmG+0PmubRtuJaI61ltbMrwP+QB1Ci8BsWH5M7A=";
    }
    else if stdenv.hostPlatform.system == "aarch64-linux"
    then {
      name = "linux_arm64";
      hash = "sha256-miuwZoanzGpO3nh/fIPUV/GL/JI1/l8yhPy85xiMTrI=";
    }
    else if stdenv.hostPlatform.system == "x86_64-darwin"
    then {
      name = "darwin_amd64";
      hash = "sha256-eaDv04NZBReWXltLYn/p71l8XvOBRj31kqR19luYwaw=";
    }
    else if stdenv.hostPlatform.system == "aarch64-darwin"
    then {
      name = "darwin_arm64";
      hash = "sha256-fLfb8I73VrWoRCmiIsxK2+T0XcugH8qF1NkY+HNCzLo=";
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
