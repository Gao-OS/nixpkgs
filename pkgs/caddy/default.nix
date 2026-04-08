{
  stdenv,
  lib,
  fetchurl,
}: let
  caddyArch =
    if stdenv.hostPlatform.system == "x86_64-linux"
    then {
      name = "linux_amd64";
      hash = "sha256-8e/Xhj+fKSCm+Nvuh85t/+NUqWSqTIDm5YIV3hY4V3c=";
    }
    else if stdenv.hostPlatform.system == "aarch64-linux"
    then {
      name = "linux_arm64";
      hash = "sha256-m6RggyzqSWZboTsSLKlDkk+KXS/2D4fMgpJ3iake41c=";
    }
    else if stdenv.hostPlatform.system == "x86_64-darwin"
    then {
      name = "darwin_amd64";
      hash = "sha256-cu+CrsuNpcxeZJCgOtCEpIuEg5t8Zb+R1gu3fstdITU=";
    }
    else if stdenv.hostPlatform.system == "aarch64-darwin"
    then {
      name = "darwin_arm64";
      hash = "sha256-/MjMeJFXPq6zv2aCeMcYFY62oZ9y6HpcY5uzdoW1FUY=";
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
