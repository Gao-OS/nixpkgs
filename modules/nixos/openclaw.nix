# OpenClaw NixOS module — system (root) service
#
# Design notes vs. upstream openclaw/nix-openclaw:
#
#   - Upstream's nixosModules.openclaw-gateway uses the `services.openclaw-gateway`
#     namespace and is oriented toward their full pnpm-built package (with native
#     extensions, vips, node-gyp). It does not include the `documents` materialization
#     concept and pulls in home-manager / flake-utils as transitive flake inputs.
#
#   - This module uses `services.openclaw` and targets our npm-tarball package
#     (pkgs/openclaw), which is simpler, reproducible, and avoids heavy native deps.
#
#   - The `documents` option lets operators declare AGENTS.md / SOUL.md / TOOLS.md
#     inline in NixOS configuration; files are materialized into the state directory
#     on every service start so they always match the deployed config.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.openclaw;
in {
  options.services.openclaw = {
    enable = lib.mkEnableOption "OpenClaw AI gateway";

    package = lib.mkPackageOption pkgs "openclaw" {};

    user = lib.mkOption {
      type = lib.types.str;
      default = "openclaw";
      description = "User account under which OpenClaw runs.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "openclaw";
      description = "Group under which OpenClaw runs.";
    };

    stateDir = lib.mkOption {
      # Use str rather than path to avoid the Nix store copying the path.
      type = lib.types.str;
      default = "/var/lib/openclaw";
      description = "Directory for OpenClaw mutable state and workspace files.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 18789;
      description = "TCP port for the OpenClaw gateway.";
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address to bind the gateway listener to.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to an environment file containing secrets (API keys, etc.).
        This file is loaded by systemd and must not be in the Nix store.
        Example contents:
          ANTHROPIC_API_KEY=sk-ant-…
      '';
    };

    documents = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      example = lib.literalExpression ''
        {
          "AGENTS.md" = "# Agents\n…";
          "SOUL.md"   = "# Soul\n…";
          "TOOLS.md"  = "# Tools\n…";
        }
      '';
      description = ''
        Workspace documents to materialize into the state directory on every
        service start.  Each attribute name is a filename relative to
        <option>stateDir</option>, and the value is the file content.
        Files always reflect the current NixOS configuration — no manual
        editing inside the container is needed.
      '';
    };

    extraEnvironment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      example = {
        OPENCLAW_LOG_LEVEL = "debug";
      };
      description = "Extra environment variables passed to the OpenClaw process.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open <option>port</option> in the firewall.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Create a dedicated system user/group when using the defaults.
    # If the operator sets a custom user/group they are responsible for creating it.
    users.users.${cfg.user} = lib.mkIf (cfg.user == "openclaw") {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.stateDir;
      description = "OpenClaw service user";
    };

    users.groups.${cfg.group} = lib.mkIf (cfg.group == "openclaw") {};

    # Create the state directory via tmpfiles so it works regardless of whether
    # stateDir is under /var/lib or another path, and survives service restarts.
    systemd.tmpfiles.rules = [
      "d '${cfg.stateDir}' 0750 ${cfg.user} ${cfg.group} - -"
    ];

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [cfg.port];

    systemd.services.openclaw = {
      description = "OpenClaw AI Gateway";
      after = ["network.target" "systemd-tmpfiles-setup.service"];
      wantedBy = ["multi-user.target"];

      environment =
        {
          HOME = cfg.stateDir;
          OPENCLAW_PORT = toString cfg.port;
          OPENCLAW_HOST = cfg.bindAddress;
          OPENCLAW_STATE_DIR = cfg.stateDir;
          # Disable any built-in self-update logic.
          OPENCLAW_NO_UPDATE = "1";
          # Plug is publish in ts source
          NODE_OPTIONS = "--experimental-transform-types";
        }
        // cfg.extraEnvironment;

      # Materialize declared documents into the state directory before startup.
      # preStart runs as the service user (cfg.user), which owns stateDir, so
      # plain `install` without -o/-g is correct — no root required.
      preStart = lib.concatStringsSep "\n" (
        lib.mapAttrsToList
        (
          name: content: let
            docFile = pkgs.writeText "openclaw-doc-${name}" content;
          in "install -m 0640 ${docFile} '${cfg.stateDir}/${name}'"
        )
        cfg.documents
      );

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.stateDir;

        ExecStart = "${lib.getExe cfg.package} gateway --port ${toString cfg.port}";

        Restart = "on-failure";
        RestartSec = 5;

        EnvironmentFile = lib.optional (cfg.environmentFile != null) cfg.environmentFile;

        # Hardening — keep stateDir writable, everything else read-only.
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        ReadWritePaths = [cfg.stateDir];
      };
    };
  };
}
