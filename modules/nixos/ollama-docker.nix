# Containerized Ollama with NVIDIA GPU passthrough
#
# Runs the official ollama/ollama OCI image via NixOS's oci-containers
# abstraction (Docker or Podman). GPU isolation keeps driver dependencies
# out of the host.
{
  config,
  lib,
  ...
}: let
  cfg = config.services.ollama-docker;
in {
  options.services.ollama-docker = {
    enable = lib.mkEnableOption "containerized Ollama with GPU passthrough";

    image = lib.mkOption {
      type = lib.types.str;
      default = "ollama/ollama:latest";
      description = "OCI image to use for the Ollama container.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 11434;
      description = "Host port mapped to the container's Ollama API (11434).";
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address to bind on the host side.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/ollama-docker";
      description = "Host path mounted into the container for model storage.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to an environment file containing secrets.
        Loaded by the container runtime; must not be in the Nix store.
      '';
    };

    extraEnvironment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      example = {
        OLLAMA_NUM_PARALLEL = "4";
      };
      description = "Extra environment variables passed to the Ollama container.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the Ollama port in the firewall.";
    };

    backend = lib.mkOption {
      type = lib.types.enum ["docker" "podman"];
      default = "docker";
      description = "Container runtime for oci-containers.";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers.backend = cfg.backend;

    virtualisation.oci-containers.containers.ollama = {
      image = cfg.image;
      ports = ["${cfg.bindAddress}:${toString cfg.port}:11434"];
      volumes = ["${cfg.dataDir}:/root/.ollama"];
      environment = cfg.extraEnvironment;
      environmentFiles = lib.optional (cfg.environmentFile != null) cfg.environmentFile;
      extraOptions = ["--gpus" "all"];
    };

    systemd.tmpfiles.rules = [
      "d '${cfg.dataDir}' 0750 root root - -"
    ];

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [cfg.port];
  };
}
