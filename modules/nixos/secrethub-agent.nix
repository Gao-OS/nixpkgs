# SecretHub Agent NixOS module.
#
# Forwards the upstream module from the pinned `secrethub` flake input, so its
# options always match the release that `pkgs/secrethub-agent` packages. The
# "Update SecretHub Agent" workflow bumps both together.
#
# The default package is this repository's prebuilt release instead of
# upstream's source build. Consumers do not need the overlay; an explicit
# `services.secrethub-agent.package` still takes precedence.
{
  self,
  secrethub,
}: {
  lib,
  pkgs,
  ...
}: {
  imports = [secrethub.nixosModules.agent];

  services.secrethub-agent.package =
    lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.secrethub-agent;
}
