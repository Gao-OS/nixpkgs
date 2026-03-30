{ config, lib, pkgs, ... }:

let
  cfg = config.services.openclaw;
in
{
  options.services.openclaw = {
    enable = lib.mkEnableOption "OpenClaw AI gateway";

    package = lib.mkPackageOption pkgs "openclaw" { };

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
      type = lib.types.path;
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
        This file is loaded by systemd and should not be in the Nix store.
      '';
    };

    documents = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = lib.literalExpression ''
        {
          "AGENTS.md" = "# Agents\n...";
          "SOUL.md" = "# Soul\n...";
          "TOOLS.md" = "# Tools\n...";
        }
      '';
      description = ''
        Workspace documents to materialize into the state directory.
        Each attribute name is a filename, and the value is the file content.
        Files are written on every service start so they reflect the current
        NixOS configuration.
      '';
    };

    extraEnvironment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        OPENCLAW_LOG_LEVEL = "debug";
      };
      description = "Extra environment variables for the OpenClaw process.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to open the configured port in the firewall.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = lib.mkIf (cfg.user == "openclaw") {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.stateDir;
      description = "OpenClaw service user";
    };

    users.groups.${cfg.group} = lib.mkIf (cfg.group == "openclaw") { };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];

    systemd.services.openclaw = {
      description = "OpenClaw AI Gateway";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        HOME = cfg.stateDir;
        OPENCLAW_PORT = toString cfg.port;
        OPENCLAW_HOST = cfg.bindAddress;
        # Disable any self-update logic
        OPENCLAW_NO_UPDATE = "1";
      } // cfg.extraEnvironment;

      preStart = lib.concatStringsSep "\n" (
        lib.mapAttrsToList
          (name: content:
            let
              docFile = pkgs.writeText "openclaw-${name}" content;
            in
            "install -m 0640 -o ${cfg.user} -g ${cfg.group} ${docFile} ${cfg.stateDir}/${name}"
          )
          cfg.documents
      );

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        StateDirectory = baseNameOf cfg.stateDir;
        StateDirectoryMode = "0750";
        WorkingDirectory = cfg.stateDir;

        ExecStart = "${lib.getExe cfg.package} gateway --port ${toString cfg.port}";

        Restart = "on-failure";
        RestartSec = 5;

        # Secrets
        EnvironmentFile = lib.optional (cfg.environmentFile != null) cfg.environmentFile;

        # Hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        ReadWritePaths = [ cfg.stateDir ];
      };
    };
  };
}
