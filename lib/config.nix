{ config, lib, ... }@args:
let cfg = config.virtualisation.incus;
in lib.mkIf cfg.enable (lib.mkMerge [
  { }
  (import ./containers-config.nix args)
])
