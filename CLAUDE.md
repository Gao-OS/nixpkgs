# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

GaoOS nixpkgs is a custom Nix package collection providing packages not available in upstream nixpkgs. This is implemented as a Nix flake with overlay support.

## Repository Structure

```
nixpkgs/
├── flake.nix              # Flake definition with package outputs and overlay
├── flake.lock             # Locked dependency versions
├── README.md              # User-facing documentation
├── CLAUDE.md              # This file
├── pkgs/
│   ├── default.nix        # Package set aggregator (callPackage for all packages)
│   ├── caddy/             # Caddy web server with custom plugins
│   │   └── default.nix
│   ├── code-server/       # VS Code server (browser-based IDE)
│   │   ├── default.nix
│   │   ├── build-vscode-nogit.patch
│   │   └── remove-node-download.patch
│   └── pmbootstrap/       # PostmarketOS development tool
│       └── default.nix
└── overlays/
    └── default.nix        # Overlay for integrating with nixpkgs
```

## Architecture

### Flake Structure

- **Inputs**: Uses nixpkgs unstable as the base
- **Outputs**:
  - `packages.<system>.*`: Individual packages for each supported system
  - `overlays.default`: Overlay to add packages to nixpkgs
  - `legacyPackages.<system>`: Full nixpkgs with overlay applied (for nix-build)

### Package Organization

Each package follows the nixpkgs convention:
- Located in `pkgs/<package-name>/default.nix`
- Called via `pkgs.callPackage` in `pkgs/default.nix`
- Exported in `flake.nix` outputs

### Current Packages

1. **caddy-with-plugins** (pkgs/caddy/default.nix:1)
   - Binary distribution package from gsmlg-dev Foundation
   - Multi-platform support with platform-specific hashes
   - Uses `fetchurl` and `autoPatchelfHook`

2. **code-server-latest** (pkgs/code-server/default.nix:1)
   - Complex Node.js/TypeScript build
   - Two-stage build with yarn cache derivation
   - Includes patches to remove git dependencies from build
   - Version: 4.105.1

3. **pmbootstrap-new** (pkgs/pmbootstrap/default.nix:1)
   - Python application using buildPythonApplication
   - Includes comprehensive test suite (mostly disabled as impure)
   - Version: 3.3.2

## Development Commands

### Building Packages

```bash
# Build a specific package
nix build .#caddy-with-plugins
nix build .#code-server-latest
nix build .#pmbootstrap-new

# Build default package
nix build

# Build in legacy mode (without flakes)
nix-build -A caddy-with-plugins
```

### Testing and Validation

```bash
# Check flake for errors
nix flake check

# Show all outputs
nix flake show

# Evaluate a package without building
nix eval .#packages.x86_64-linux.caddy-with-plugins

# Check package metadata
nix eval .#packages.x86_64-linux.caddy-with-plugins.meta --json | jq

# Test run a package
nix run .#caddy-with-plugins -- --version
```

### Development Workflow

```bash
# Update flake inputs (nixpkgs)
nix flake update

# Update specific input
nix flake lock --update-input nixpkgs

# Enter development shell with package dependencies
nix develop .#code-server-latest

# Format Nix files
nixpkgs-fmt pkgs/**/*.nix flake.nix

# Check Nix syntax
nix-instantiate --parse flake.nix
```

### Adding a New Package

1. Create package directory: `mkdir pkgs/new-package`
2. Write `pkgs/new-package/default.nix` with package definition
3. Add to `pkgs/default.nix`:
   ```nix
   new-package = pkgs.callPackage ./new-package {};
   ```
4. Export in `flake.nix` under `packages`:
   ```nix
   new-package = pkgs.new-package;
   ```
5. Test build: `nix build .#new-package`
6. Verify metadata: `nix eval .#packages.x86_64-linux.new-package.meta --json | jq`

### Modifying Existing Packages

When updating package versions or dependencies:

1. Edit the package's `default.nix`
2. Update version number
3. Update hashes (set to empty string first, nix will report correct hash)
4. Test build: `nix build .#package-name`
5. If patches fail, update or remove them
6. Verify on all platforms if possible

## Package Conventions

### Naming

- Directory names: lowercase with hyphens (`code-server`)
- Package attribute names: descriptive and unique (`code-server-latest`, `caddy-with-plugins`)
- Binary names: match upstream (`caddy`, `code-server`)

### Metadata Requirements

All packages must include:
- `pname` and `version`
- `src` with hash
- `meta.description`
- `meta.homepage`
- `meta.license`
- `meta.platforms` (or inherit from stdenv)
- `meta.mainProgram` for executables

### Patch Management

- Store patches in package directory
- Use descriptive names (`build-vscode-nogit.patch`)
- Document what each patch does in package definition
- Prefer upstream patches or pull requests when possible

## Integration with Other Projects

### As a Flake Input

```nix
inputs.gaoos-nixpkgs.url = "path:/path/to/gaoos-nixpkgs";
# or
inputs.gaoos-nixpkgs.url = "github:username/gaoos-nixpkgs";
```

### As an Overlay

```nix
nixpkgs.overlays = [ gaoos-nixpkgs.overlays.default ];
```

### Direct Import (Non-Flake)

```nix
nixpkgs.overlays = [
  (import /path/to/gaoos-nixpkgs/overlays/default.nix)
];
```

## Supported Systems

- x86_64-linux (primary)
- aarch64-linux
- x86_64-darwin
- aarch64-darwin

Note: Some packages may have platform restrictions. Check `meta.platforms` in each package.

## Build Patterns

### Binary Packages (caddy)

- Use `fetchurl` for prebuilt binaries
- Set `dontUnpack = true` for single binary files
- Use `autoPatchelfHook` for dynamic linking on Linux
- Platform-specific sources with different hashes

### Source Packages (code-server, pmbootstrap)

- Use appropriate fetcher (`fetchFromGitHub`, `fetchFromGitLab`)
- Include all submodules if needed
- Apply patches early in build process
- For complex builds, consider multi-stage derivations

### Node.js Packages (code-server)

- Separate yarn cache derivation for reproducibility
- Pin specific tool versions (like esbuild) when needed
- Disable automatic updates and telemetry
- Use `makeWrapper` to set runtime environment

### Python Packages (pmbootstrap)

- Use `buildPythonApplication` from python3Packages
- Set `pyproject = true` for modern Python packaging
- Disable impure tests
- Include update scripts in `passthru` if available
