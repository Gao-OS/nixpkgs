# Overlay providing Spock-patched PostgreSQL 16, 17, and 18, plus the pgEdge Spock extension.
# Spock requires patches to the PostgreSQL source for its logical replication hooks.
final: prev: let
  spockVersion = "5.0.8";

  spockSrc = prev.fetchFromGitHub {
    owner = "pgEdge";
    repo = "spock";
    rev = "v${spockVersion}";
    hash = "sha256-BefmSJ8//36tbYAs/PJq+PiJvrs3b6pJwU5oQ5NrvI0=";
  };

  # Per-version patch lists from ${spockSrc}/patches/<major>/
  spockPatches = {
    "16" = [
      "${spockSrc}/patches/16/pg16-015-attoptions.diff"
      "${spockSrc}/patches/16/pg16-025-logical_commit_clock.diff"
      "${spockSrc}/patches/16/pg16-030-per-subtrans-commit-ts.diff"
    ];
    "17" = [
      "${spockSrc}/patches/17/pg17-015-attoptions.diff"
      "${spockSrc}/patches/17/pg17-025-logical_commit_clock.diff"
      "${spockSrc}/patches/17/pg17-030-per-subtrans-commit-ts.diff"
      "${spockSrc}/patches/17/pg17-090-init_template_fix.diff"
    ];
    "18" = [
      "${spockSrc}/patches/18/pg18-015-attoptions.diff"
      "${spockSrc}/patches/18/pg18-025-logical_commit_clock.diff"
      "${spockSrc}/patches/18/pg18-030-per-subtrans-commit-ts.diff"
      "${spockSrc}/patches/18/pg18-035-row-filter-check.diff"
      "${spockSrc}/patches/18/pg18-090-init_template_fix.diff"
    ];
  };

  # Build a Spock-patched PostgreSQL for a given upstream package.
  # NOTE: We intentionally do NOT change pname — doing so breaks the multi-output
  # install hooks (pgxs, headers, etc.) in nixpkgs' postgresql derivation.
  #
  # IMPORTANT: overrideAttrs does NOT update passthru.withPackages, so it still
  # wraps the UNPATCHED postgresql binary. We manually rebuild the passthru so
  # that withPackages uses our patched binary.
  mkPostgresqlSpock = pgPkg: majorVersion: let
    patches = spockPatches.${majorVersion};
    patched = pgPkg.overrideAttrs (old: {
      patches = (old.patches or []) ++ patches;
    });
    mkWithPackages = f: let
      installedExtensions = f patched.pkgs;
      args = prev.lib.concatMap (ext: ext.wrapperArgs or []) installedExtensions;
    in
      prev.buildEnv {
        name = "postgresql-and-plugins-${patched.version}";
        paths = installedExtensions ++ [patched patched.man];
        pathsToLink = [
          "/"
          "/bin"
          "/share/postgresql/extension"
          "/share/postgresql/timezonesets"
          "/share/postgresql/tsearch_data"
        ];
        nativeBuildInputs = [prev.makeBinaryWrapper];
        postBuild = ''
          wrapProgram "$out/bin/postgres" ${prev.lib.concatStringsSep " " args}
        '';
        passthru = {
          inherit installedExtensions;
          inherit (patched) pkgs psqlSchema version;
          postgresql = patched;
          withJIT = mkWithPackages (_: installedExtensions ++ [patched.jit]);
          withoutJIT = mkWithPackages (_: prev.lib.remove patched.jit installedExtensions);
          withPackages = f': mkWithPackages (ps: installedExtensions ++ f' ps);
        };
      };
  in
    patched.overrideAttrs (old: {
      passthru =
        (old.passthru or {})
        // {
          withPackages = mkWithPackages;
          withJIT = mkWithPackages (_: [patched.jit]);
          withoutJIT = mkWithPackages (_: []);
        };
    });

  postgresql_16_spock = mkPostgresqlSpock prev.postgresql_16 "16";
  postgresql_17_spock = mkPostgresqlSpock prev.postgresql_17 "17";
  postgresql_18_spock = mkPostgresqlSpock prev.postgresql_18 "18";

  # Current nixpkgs PostgreSQL exposes pg_config data through pg_config.expected.
  # We create a shell wrapper that PGXS-based extensions can call during the build.
  mkPgConfigWrapper = pgSpock:
    prev.writeShellScriptBin "pg_config" ''
      FILE="${pgSpock.dev}/nix-support/pg_config.expected"
      case "$1" in
        --help)
          echo "pg_config provides information about the installed version of PostgreSQL."
          echo "Usage: pg_config [OPTION]"
          ;;
        "")
          cat "$FILE"
          ;;
        *)
          key=$(echo "$1" | sed 's/^--//' | tr '[:lower:]' '[:upper:]' | tr '-' '_')
          grep "^$key = " "$FILE" | sed "s/^$key = //"
          ;;
      esac
    '';

  # Build the Spock extension against a given Spock-patched PostgreSQL.
  mkSpock = pgSpock: let
    pgConfigWrapper = mkPgConfigWrapper pgSpock;
  in
    prev.stdenv.mkDerivation {
      pname = "spock";
      version = spockVersion;

      src = spockSrc;

      buildInputs = [
        pgSpock
        pgSpock.dev
        prev.jansson
        prev.libpq
        prev.openssl.dev
        prev.krb5.dev
        prev.libxml2.dev
        prev.lz4.dev
        prev.zstd.dev
        prev.icu.dev
      ];
      nativeBuildInputs = [pgConfigWrapper pgSpock.dev prev.clang prev.pkg-config];

      makeFlags = ["USE_PGXS=1"];
      installFlags = ["DESTDIR=$(out)"];

      postInstall = ''
        cp -r $out${pgSpock}/* $out/
        rm -rf $out/nix
      '';

      meta = {
        description = "pgEdge Spock ${spockVersion} - multi-master logical PostgreSQL replication";
        homepage = "https://github.com/pgEdge/spock";
        platforms = pgSpock.meta.platforms;
      };
    };

  spock_16 = mkSpock postgresql_16_spock;
  spock_17 = mkSpock postgresql_17_spock;
  spock_18 = mkSpock postgresql_18_spock;
in {
  inherit postgresql_16_spock postgresql_17_spock postgresql_18_spock;
  postgresqlPackages_spock = {
    inherit spock_16 spock_17 spock_18;
  };
}
