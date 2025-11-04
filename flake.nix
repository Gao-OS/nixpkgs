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
      });
    in
    {
      # Overlay that can be used by other flakes or configurations
      overlays.default = final: prev:
        let
          packages = import ./pkgs/default.nix final;
        in
        packages;

      # Package outputs for each system
      packages = forAllSystems (system:
        let
          pkgs = nixpkgsFor.${system};
        in
        {
          # Export all packages
          caddy-with-plugins = pkgs.caddy-with-plugins;
          code-server-latest = pkgs.code-server-latest;
          pmbootstrap-new = pkgs.pmbootstrap-new;

          # Default package
          default = pkgs.caddy-with-plugins;
        }
      );

      # Legacy package output (for nix-build support)
      legacyPackages = forAllSystems (system: nixpkgsFor.${system});
    };
}
