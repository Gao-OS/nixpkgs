# GaoOS custom packages
# You can build them using 'nix build .#caddy-with-plugins'
pkgs: {
  caddy-with-plugins = pkgs.callPackage ./caddy {};
  pmbootstrap-new = pkgs.callPackage ./pmbootstrap {};
  code-server-latest = pkgs.callPackage ./code-server {};
  openclaw = pkgs.callPackage ./openclaw {};
  ollama = pkgs.callPackage ./ollama {};
  ollama-rocm = pkgs.callPackage ./ollama { acceleration = "rocm"; };
  ollama-cuda = pkgs.callPackage ./ollama { acceleration = "cuda"; };
  ollama-vulkan = pkgs.callPackage ./ollama { acceleration = "vulkan"; };
}
