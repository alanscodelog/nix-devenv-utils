# Creates the base web dev environment.
{ pkgs, config, lib, ... }:

let
  cfg = config.webDevConfig;
  secretHttpsCerts =
    if builtins.getEnv "SECRETS_DIR" != "" && cfg.secretHttpsCerts == true then ''
      export LOCALHOST_PEM="$SECRETS_DIR/localhost.pem"
      export LOCALHOST_KEY_PEM="$SECRETS_DIR/localhost-key.pem"
    '' else "";
  secretTokens =
    if builtins.getEnv "SECRETS_DIR" == ""
      && cfg.secretTokens == true then ''
      export NPM_TOKEN=$(cat $SECRETS_DIR/NPM_TOKEN)
      export GH_TOKEN=$(cat $SECRETS_DIR/GH_TOKEN)
    '' else "";
in
{
  options.webDevConfig = {
    enable = lib.mkEnableOption "Enable base dev env.";
    terminal = lib.mkOption {
      type = lib.types.str;
      default = "wezterm";
    };
    useNuxt = lib.mkEnableOption "Use Nuxt";
    secretTokens = lib.mkEnableOption "Use secret tokens.";
    secretHttpsCerts = lib.mkEnableOption "Use secret https certs.";
    enterShell = lib.mkOption {
      type = lib.types.str;
      default = ''
						${if secretHttpsCerts != "" then secretHttpsCerts else ""}
						${if secretTokens != "" then secretTokens else ""}
						devHelp
						devPrepare
						devInfo
      '';
    };
  };
  config = lib.mkIf cfg.enable {
    enterShell = lib.mkAfter cfg.enterShell;
    env.TERM = cfg.terminal;
    packages = [
      # am tired of the ts-node issues, just want to run a script damn it
      pkgs.bun
    ];
    languages = {
      javascript = {
        enable = true;
        package = pkgs.nodejs_23;
        pnpm.enable = true;
      };
    };
    processes.nuxt = lib.mkIf cfg.useNuxt {
      exec = "pnpm dev";
      process-compose.availability.max_restarts = 1000;
    };
    process-managers.process-compose.settings.theme = "One Dark";

    scripts.devHelp = {
      description = "List available scripts.";
      exec = ''
        echo "Scripts:"
        ${pkgs.gnused}/bin/sed -e 's| |••|g' -e 's|=| |' <<EOF | ${pkgs.util-linuxMinimal}/bin/column -t | ${pkgs.gnused}/bin/sed -e 's|^|- |' -e 's|••| |g'
        ${lib.generators.toKeyValue {} (lib.mapAttrs (name: value: if value.description != "" then value.description else "(no description)") config.scripts)}
      '';
    };
    # note that scripts cant export env vars ???
    scripts.devPrepare = {
      description = "Prepares the project for development.";
      exec = ''
        echo "Preparing Env..."
        if [ ! -d node_modules ]; then pnpm i; else printf "Found node_modules, Skipping Pnpm Install\n"; fi
        ${if cfg.useNuxt then ''
        if [ ! -d .nuxt ]; then pnpm dev:prepare; else printf "Found .nuxt, Skipping Nuxt Prepare\n"; fi
        '' else ""}
      '';
    };
    scripts.devInfo = {
      description = "Prints out some information about the environment.";
      exec = ''
        echo "Environment Package Versions:"
        echo "node `${pkgs.nodejs_23}/bin/node --version`"
        echo "pnpm `${pkgs.nodePackages.pnpm}/bin/pnpm --version`"
      '';
    };
  };
}
