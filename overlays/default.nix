# GaoOS overlay
# This overlay adds GaoOS custom packages to nixpkgs
# Usage in configuration.nix:
#   nixpkgs.overlays = [ (import /path/to/gaoos-nixpkgs/overlays/default.nix) ];

final: prev:
  let
    packages = import ../pkgs/default.nix final;
  in
  packages
