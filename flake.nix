{
  description = "GaoOS nixpkgs - Custom package collection for GaoOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      # Systems to support
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      # Helper function to generate an attrset for each system
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Helper to get nixpkgs for a system
      nixpkgsFor = forAllSystems (system: import nixpkgs {
        inherit system;
        overlays = [ self.overlays.default ];
        config.allowUnfree = true;
      });
    in
    {
      # Overlay that can be used by other flakes or configurations
      overlays.default = final: prev:
        let
          packages = import ./pkgs/default.nix final;
          spockPackages = (import ./overlays/postgresql-spock.nix) final prev;
        in
        packages // spockPackages // {
          # Re-export ollama variants from upstream nixpkgs (prev avoids infinite recursion)
          inherit (prev) ollama ollama-rocm ollama-cuda ollama-vulkan;
        };

      overlays.postgresql-spock = import ./overlays/postgresql-spock.nix;

      # Package outputs for each system
      packages = forAllSystems (system:
        let
          pkgs = nixpkgsFor.${system};
          isLinux = builtins.elem system [ "x86_64-linux" "aarch64-linux" ];
        in
        {
          # Export all packages
          caddy-with-plugins = pkgs.caddy-with-plugins;
          code-server-latest = pkgs.code-server-latest;
          pmbootstrap-new = pkgs.pmbootstrap-new;
          openclaw = pkgs.openclaw;
          ollama = pkgs.ollama;
          ollama-rocm = pkgs.ollama-rocm;
          ollama-cuda = pkgs.ollama-cuda;
          ollama-vulkan = pkgs.ollama-vulkan;

          # Default package
          default = pkgs.caddy-with-plugins;
        }
        // nixpkgs.lib.optionalAttrs isLinux {
          inherit (pkgs) postgresql_16_spock postgresql_17_spock postgresql_18_spock;
          inherit (pkgs.postgresqlPackages_spock) spock_16 spock_17 spock_18;
        }
      );

      # NixOS modules
      nixosModules.openclaw = import ./modules/nixos/openclaw.nix;
      nixosModules.ollama-docker = import ./modules/nixos/ollama-docker.nix;
      nixosModules.postgresql-spock = import ./modules/nixos/postgresql-spock.nix;

      # Legacy package output (for nix-build support)
      legacyPackages = forAllSystems (system: nixpkgsFor.${system});
    };
}
