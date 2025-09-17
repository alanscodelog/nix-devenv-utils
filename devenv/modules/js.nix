{ pkgs, lib, config, inputs, ... }:

let
  cfg = config.custom.js;
in
{
  options.custom.js = {
    nodejs.package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.nodejs;
      description = '' nodejs package to use.'';
    };
    pnpm.package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.pnpm;
      description = '' pnpm package to use.'';
    };
    setupPlaywright = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''Whether to setup playwright. Use https://github.com/pietdevries94/playwright-web-flake to easily pin versions as they must be in sync with the version in package.json. Defaults to false.'';
    };
    loadNpmToken = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''Whether to load the NPM_TOKEN (from the $SECRETS_DIR dir).'';
    };
    enabled = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''Whether to enable the module, defaults to true.'';
    };
  };
  config = lib.mkIf cfg.enabled {
    custom.base.moduleInstructions = ''
      JS MODULE:
          REQUIRES:
              - File: $SECRETS_DIR/NPM_TOKEN (if loadNpmToken = true)
          DEFINES:
              - $NPM_TOKEN * (if loadNpmToken = true)
              - $NODE_EXTRA_CA_CERTS * (if loadSelfSignedCerts = true)
    '';
    custom.base.beforeEnterShell =
      lib.optionalString (cfg.loadNpmToken && builtins.getEnv "SECRETS_DIR" != "") ''
        export NPM_TOKEN=$(cat $SECRETS_DIR/NPM_TOKEN)
      '' + lib.optionalString config.custom.base.loadSelfSignedCerts ''
        export NODE_EXTRA_CA_CERTS="$LOCALHOST_PEM"
      '';
    env = lib.mkIf cfg.setupPlaywright {
      PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = lib.mkIf cfg.setupPlaywright 1;
      PLAYWRIGHT_BROWSERS_PATH = lib.mkIf cfg.setupPlaywright "${pkgs.playwright-driver.browsers}";
      PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = lib.mkIf cfg.setupPlaywright "true";
    };

    custom.base.info = ''
      echo JS MODULE:
      echo "   " "node `${cfg.nodejs.package}/bin/node --version`"
      echo "   " "pnpm `${cfg.pnpm.package}/bin/pnpm --version`"
      echo "   " NODE_EXTRA_CA_CERTS: $NODE_EXTRA_CA_CERTS
      echo "   " PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD: $PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD
      echo "   " PLAYWRIGHT_BROWSERS_PATH: $PLAYWRIGHT_BROWSERS_PATH
      echo "   " PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS: $PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS
      echo "   " Package.json playwright version: $(cat package.json | jq '.devDependencies."playwright-core"')
    '';

    languages = {
      javascript = {
        enable = true;
        package = cfg.nodejs.package;
        pnpm.enable = true;
        pnpm.package = cfg.pnpm.package;
      };
    };
  };
}
