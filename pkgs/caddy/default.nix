{
  stdenv,
  lib,
  fetchurl,
}: let
  caddyArch =
    if stdenv.hostPlatform.system == "x86_64-linux"
    then {
      name = "linux_amd64";
      hash = "sha256-RtckOjiRyG7KC4CpWl8Gib+GSu3YnGiwa0Cm5wNjeFk=";
    }
    else if stdenv.hostPlatform.system == "aarch64-linux"
    then {
      name = "linux_arm64";
      hash = "sha256-NUineKiEJov6lCU14WxSkTRrMXKAqh1A7B5Cw/eTVbU=";
    }
    else if stdenv.hostPlatform.system == "x86_64-darwin"
    then {
      name = "darwin_amd64";
      hash = "sha256-KbLsq+JRV0VNtUTtzni29W2s/NOfQbija6F5CaMSgoU=";
    }
    else if stdenv.hostPlatform.system == "aarch64-darwin"
    then {
      name = "darwin_arm64";
      hash = "sha256-PTTZVdOYgEqHXCJRTDo9jFzM/wSTe0KbtNwDu+4Nrpg=";
    }
    else throw "Unsupported platform: ${stdenv.hostPlatform.system}";
in
  stdenv.mkDerivation rec {
    pname = "caddy";
    version = "2.10.2";

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
