{ pkgs, lib, config, inputs, ... }:
let
  cfg = config.custom.electron;
in
{
  options.custom.electron = {
    enabled = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''Whether to enable the module, defaults to false.'';
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.electron_33-bin;
      description = ''Electron package to use.'';
    };
  };
  config = lib.mkIf cfg.enabled {
    custom.base.moduleInstructions = ''
      ELECTRON MODULE:
          DEFINES: 
              - $ELECTRON_SKIP_BINARY_DOWNLOAD = 1
              - $ELECTRON_OVERRIDE_DIST_PATH
    '';
    # prevent downloading electron and use nix's electron
    # in future might need something like node2nix instead (https://github.com/svanderburg/node2nix)
    env.ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
    env.ELECTRON_OVERRIDE_DIST_PATH = "${cfg.package}/bin/";
    custom.base.info = ''
      echo ELECTRON MODULE:
      echo "   " ELECTRON_SKIP_BINARY_DOWNLOAD: $ELECTRON_SKIP_BINARY_DOWNLOAD
      echo "   " ELECTRON_OVERRIDE_DIST_PATH: $ELECTRON_OVERRIDE_DIST_PATH
    '';
    packages = [
      cfg.package
    ];
  };
}
