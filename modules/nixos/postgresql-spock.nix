# NixOS module for PostgreSQL with pgEdge Spock multi-master replication.
# Requires the postgresql-spock overlay (overlays/postgresql-spock.nix) to be applied
# so that pkgs.postgresql_{16,17,18}_spock and pkgs.postgresqlPackages_spock.spock_{16,17,18}
# are available.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.postgresqlSpock;

  nodeType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Node name (e.g. node1)";
      };
      ip = lib.mkOption {
        type = lib.types.str;
        description = "Node IP address";
      };
    };
  };

  peerNodes = builtins.filter (n: n.ip != cfg.thisNode.ip) cfg.clusterNodes;

  clusterAuthLines = lib.concatMapStringsSep "\n" (
    node: "host    all             all             ${node.ip}/32            md5"
  ) peerNodes;

  replicationAuthLines = lib.concatMapStringsSep "\n" (
    node: "host    replication     all             ${node.ip}/32            md5"
  ) peerNodes;
in {
  options.services.postgresqlSpock = {
    enable = lib.mkEnableOption "PostgreSQL with pgEdge Spock multi-master replication";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.postgresql_17_spock;
      defaultText = lib.literalExpression "pkgs.postgresql_17_spock";
      description = "Spock-patched PostgreSQL package (postgresql_{16,17,18}_spock).";
    };

    extensions = lib.mkOption {
      type = lib.types.functionTo (lib.types.listOf lib.types.package);
      default = ps: with pkgs.postgresqlPackages_spock; [spock_17];
      defaultText = lib.literalExpression "ps: with pkgs.postgresqlPackages_spock; [ spock_17 ]";
      description = ''
        Function from the PostgreSQL package set to a list of extensions.
        Use the matching spock_<major> from pkgs.postgresqlPackages_spock.
        Example: ps: with pkgs.postgresqlPackages_spock; [ spock_17 ] ++ (with ps; [ ip4r pgvector ])
      '';
    };

    extraSettings = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Extra PostgreSQL settings merged on top of the Spock-required defaults.";
    };

    thisNode = lib.mkOption {
      type = nodeType;
      description = "This node's identity in the Spock cluster.";
    };

    clusterNodes = lib.mkOption {
      type = lib.types.listOf nodeType;
      default = [];
      description = "All nodes in the Spock replication cluster (including this node).";
    };
  };

  config = lib.mkIf cfg.enable {
    services.postgresql = {
      enable = true;
      package = cfg.package;
      extensions = cfg.extensions;
      enableTCPIP = true;

      authentication = lib.mkAfter ''
        # Spock cluster peer authentication
        ${clusterAuthLines}
        ${replicationAuthLines}
      '';

      settings = lib.mkMerge [
        {
          listen_addresses = "*";
          max_connections = 200;
          shared_buffers = "512MB";
          log_min_duration_statement = 500;
          shared_preload_libraries = "spock";
          track_commit_timestamp = true;
          wal_level = "logical";
          max_worker_processes = 10;
          max_replication_slots = 10;
          max_wal_senders = 10;
        }
        cfg.extraSettings
      ];
    };
  };
}
