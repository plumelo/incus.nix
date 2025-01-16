{ modulesPath, config, pkgs, lib, ... }:
let
  cfg = config.virtualisation.incus;
  group = "incus-admin";
  containers = cfg.containers;
  package = cfg.package;
  configFormat = pkgs.formats.yaml { };
  mkService = { name, enable, auto, image, config, devices, profiles, ... }@cfg:
    let
      sys = (image.extendModules {
        modules = [
          "${modulesPath}/virtualisation/lxc-container.nix"
        ];
      });
      root = sys.config.system.build.tarball.override {
        compressCommand = "pixz -0 -t";
      };
      metadata = sys.config.system.build.metadata.override {
        compressCommand = "pixz -0 -t";
      };
      instanceConf = {
        inherit config;
      }
      // (if devices == null then { } else { inherit devices; })
      // (if profiles == null then { } else { inherit profiles; });
    in
    rec {
      inherit enable;
      wantedBy = lib.optional cfg.auto "multi-user.target";
      after = [ "incus.service" ];
      path = [ package ] ++ (with pkgs; [ yq-go gnutar util-linux xz ]);
      script = ''
        root=$(find ${root} -name "*.tar.xz" -xtype f -print -quit)
        metadata=$(find ${metadata} -name "*.tar.xz" -xtype f -print -quit)
        fg=$(incus image info ${name}-image | yq '.Fingerprint')
        if incus image import $metadata $root --alias ${name}-image; then
          incus image delete $fg || true
          if incus info ${name}; then
            incus delete -f ${name}
          fi
          incus launch ${name}-image ${name}
        fi
        incus config show ${name} | yq '. *= load("${configFormat.generate "inc-${name}-config.yaml" instanceConf}")' | incus config edit ${name}
        incus restart ${name} || true
      '';
      serviceConfig = {
        Type = "oneshot";
        Group = group;
        RemainAfterExit = true;
      };
    };
in
{
  systemd.services = lib.concatMapAttrs
    (name: cfg: {
      "incs@${name}" = mkService (cfg // { inherit name; });
    })
    containers;

  #systemd.tmpfiles.rules = lib.flatten (lib.mapAttrsToList
  #  (n: v:
  #    (lib.mapAttrsToList
  #      (n: v: "d ${v.source} 0770 root ${group}")
  #      (lib.filterAttrs (n: v: v.type == "disk" && lib.hasPrefix "/var/lib/incus/state" v.source) v.devices)
  #    )
  #  )
  #  containers
  #);
}
