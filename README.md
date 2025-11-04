# GaoOS nixpkgs

Custom package collection for GaoOS, providing additional packages and tools not available in upstream nixpkgs.

## Available Packages

- **caddy-with-plugins**: Caddy web server with custom plugins from gsmlg-dev Foundation
- **code-server-latest**: VS Code running on a remote server (v4.105.1)
- **pmbootstrap-new**: Tool to develop and install postmarketOS (v3.3.2)

## Usage

### Using as a Flake

#### Build a package

```bash
# Build a specific package
nix build .#caddy-with-plugins
nix build .#code-server-latest
nix build .#pmbootstrap-new

# Build the default package (caddy-with-plugins)
nix build
```

#### Run a package without installing

```bash
nix run .#caddy-with-plugins -- --version
nix run .#code-server-latest -- --help
```

#### Add to your flake inputs

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    gaoos-nixpkgs.url = "path:/path/to/gaoos-nixpkgs";
    # Or if hosted on GitHub:
    # gaoos-nixpkgs.url = "github:yourusername/gaoos-nixpkgs";
  };

  outputs = { self, nixpkgs, gaoos-nixpkgs }: {
    # Use in your system configuration
    nixosConfigurations.yourhostname = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        {
          nixpkgs.overlays = [ gaoos-nixpkgs.overlays.default ];
        }
        # Now you can use the packages in your configuration
        # e.g., environment.systemPackages = [ pkgs.caddy-with-plugins ];
      ];
    };
  };
}
```

### Using the Overlay

#### In configuration.nix

```nix
{ config, pkgs, ... }:

{
  nixpkgs.overlays = [
    (import /path/to/gaoos-nixpkgs/overlays/default.nix)
  ];

  environment.systemPackages = with pkgs; [
    caddy-with-plugins
    code-server-latest
    pmbootstrap-new
  ];
}
```

#### In your own flake

```nix
{
  outputs = { self, nixpkgs, gaoos-nixpkgs }: {
    packages.x86_64-linux.default =
      let
        pkgs = import nixpkgs {
          system = "x86_64-linux";
          overlays = [ gaoos-nixpkgs.overlays.default ];
        };
      in
      pkgs.caddy-with-plugins;
  };
}
```

## Development

### Adding a New Package

1. Create a directory under `pkgs/` with your package name
2. Add a `default.nix` file with the package definition
3. Add the package to `pkgs/default.nix`:
   ```nix
   {
     # ... existing packages
     my-new-package = pkgs.callPackage ./my-new-package {};
   }
   ```
4. Export it in `flake.nix` under the `packages` output
5. Test the build: `nix build .#my-new-package`

### Testing Changes

```bash
# Check if flake evaluates correctly
nix flake check

# Show package outputs
nix flake show

# Build all packages
nix build .#caddy-with-plugins .#code-server-latest .#pmbootstrap-new
```

## Supported Systems

- x86_64-linux
- aarch64-linux
- x86_64-darwin
- aarch64-darwin

Note: Individual packages may have platform restrictions. Check each package's `meta.platforms` attribute.
