# GaoOS custom packages
# You can build them using 'nix build .#caddy-with-plugins'
pkgs: {
  caddy-with-plugins = pkgs.callPackage ./caddy {};
  pmbootstrap-new = pkgs.callPackage ./pmbootstrap {};
  code-server-latest = pkgs.callPackage ./code-server {};
}
