{
  stdenv,
  lib,
  fetchurl,
}: let
  caddyArch =
    if stdenv.hostPlatform.system == "x86_64-linux"
    then {
      name = "linux_amd64";
      hash = "sha256-nMModB1VsQ1CovDC//SGFExb6cobSVWIWwzH009H7YM=";
    }
    else if stdenv.hostPlatform.system == "aarch64-linux"
    then {
      name = "linux_arm64";
      hash = "sha256-gbwLmwGrG5UndDLpVQXf6Ve1n4KJKstMDN4br+631Es=";
    }
    else if stdenv.hostPlatform.system == "x86_64-darwin"
    then {
      name = "darwin_amd64";
      hash = "sha256-UgGqTdQtCWNrXuJrA6bVBvAJR8rgY7agdSftcX/YPuY=";
    }
    else if stdenv.hostPlatform.system == "aarch64-darwin"
    then {
      name = "darwin_arm64";
      hash = "sha256-zpcrGTHsC3qqzBBCYQJh+hCIP9YLOyHBG25gofsvJws=";
    }
    else throw "Unsupported platform: ${stdenv.hostPlatform.system}";
in
  stdenv.mkDerivation rec {
    pname = "caddy";
    version = "2.8.4";

    src = fetchurl {
      url = "https://github.com/gsmlg-dev/Foundation/releases/download/caddy-v${version}/caddy_${caddyArch.name}";
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
      homepage = "https://github.com/gsmlg-dev/Foundation/tree/main/docker/caddy";
      description = "GSMLG.dev custom caddy build";
      platforms = [
        "aarch64-linux"
        "x86_64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
    };
  }
