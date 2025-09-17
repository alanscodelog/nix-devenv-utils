{ pkgs, lib, config, inputs, ... }:

let
  cfg = config.custom.base;
  indent = "    ";
  utils = {
    printAndIndent = text: ''
      cat <<'EOF' | sed 's/^/${indent}/' 
      ${text}
      EOF
    '';
  };
in
{
  options.custom.base = {
    distDir = lib.mkOption {
      type = lib.types.str;
      default = ".dist";
      description = ''Directory to use for dist.'';
    };
    terminal = lib.mkOption {
      type = lib.types.str;
      default = "wezterm";
      description = ''Terminal to use.'';
    };
    rootDir = lib.mkOption {
      type = lib.types.str;
      default = config.env.DEVENV_ROOT + "/";
      description = ''Root directory of the project.'';
    };

    moduleInstructions = lib.mkOption {
      type = lib.types.lines;
      description = ''Additional info to print in the devEnvHelp script. For other modules to document the env variables they require. No shell commands allowed and there's no need to escape any characters'';
    };
    info = lib.mkOption {
      type = lib.types.lines;
      default = '''';
      description = ''Additional shell commands to run in the devInfo script. Mostly for other modules so they can register additional information. Note that ALL scripts are printed by default, other modules don't have to specify their's.'';
    };
    beforeEnterShell = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''Shell commands to run at the start of enter shell. Mostly for other modules to export env vars based on impure info. CANNOT use config.env variables'';
    };
    prepare = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''Shell commands to run before the devPrepare script. For other modules to run additional preparations.'';
    };
    usedPorts = lib.mkOption {
      type = lib.types.listOf lib.types.int;
      default = [ ];
      description = ''Ports used by the project. Used by the killAllPorts script.'';
    };
    loadSelfSignedCerts = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to load the self signed certs in $SECRETS_DIR/localhost.pem and $SECRETS_DIR/localhost-key.pem $LOCALHOST_PEM and $LOCALHOST_KEY_PEM.
        Js module will also set $NODE_EXTRA_CA_CERTS to the value of $LOCALHOST_PEM.
        Note that using the certs can cause issues with the loading of other non-https localhost pages. You might need to ocassionally `Delete domain security policies` for localhost in chrome's `chrome://net-internals/#hsts` to get it to forget how it loaded localhost...'';
    };
    loadGithubToken = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to load the GH_TOKEN (from the $SECRETS_DIR/GH_TOKEN ).
      '';
    };
    enabled = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''Whether to enable the module, defaults to true.'';
    };
  };
  config = lib.mkIf cfg.enabled {
    env.TERM = cfg.terminal;
    env.DIST_DIR = cfg.distDir;
    env.ROOT_DIR = cfg.rootDir;

    process.managers.process-compose.settings.theme = "One Dark";
    # not working?
    process.managers.process-compose.settings.availability.max_restarts = 6;

    enterShell =
      lib.optionalString (cfg.loadSelfSignedCerts && builtins.getEnv "SECRETS_DIR" != "") ''
        export LOCALHOST_PEM="$SECRETS_DIR/localhost.pem"
        export LOCALHOST_KEY_PEM="$SECRETS_DIR/localhost-key.pem"
      
      '' + lib.optionalString (cfg.loadGithubToken && builtins.getEnv "SECRETS_DIR" != "") ''
        export GH_TOKEN=$(cat $SECRETS_DIR/GH_TOKEN)
      ''
      + ''
        ${cfg.beforeEnterShell}
        devHelp
        devInstructions
        devInfo
        devPrepare
      '';

    scripts.devHelp = {
      description = "List available scripts.";
      # note that last line is required for the command to work
      exec = ''
        echo "SCRIPTS:"
        ${pkgs.gnused}/bin/sed -e 's| |••|g' -e 's|=| |' <<EOF | ${pkgs.util-linuxMinimal}/bin/column -t | ${pkgs.gnused}/bin/sed -e 's|^|${indent} |' -e 's|••| |g'
        ${lib.generators.toKeyValue {} (lib.mapAttrs (name: value: if value.description != "" then value.description else "(no description)") config.scripts)}
        EOF
      '';
    };

    scripts.devInstructions =
      let
        base = ''
          Modules require the following env variables and files:
          Required env variables should be loaded manually or via direnv (dotenv is disabled as it's insecure).
          Some modules also require certain files exist.
          * - Means the module set the variable via a script and it cannot be accessed via config.env

          BASE MODULE:
             REQUIRES:
                - $SECRETS_DIR (required if using options that use impure secrets, these are all off by default)
                - File: $SECRETS_DIR/localhost.pem (if loadSelfSignedCerts = true)
                - File: $SECRETS_DIR/localhost-key.pem (if loadSelfSignedCerts = true)
          
             DEFINES:
                - $TERM (custom.base.terminal)
                - $DIST_DIR (custom.base.distDir)
                - $ROOT_DIR (DEVENV_ROOT + /)
                - $LOCALHOST_PEM * (if custom.base.loadSelfSignedCerts)
                - $LOCALHOST_KEY_PEM * (if custom.base.loadSelfSignedCerts)
                - $GH_TOKEN * (if custom.base.loadGithubToken)
        '';
      in
      {
        description = "Prints out some information about the env variables and files needed.";
        exec = ''
          echo MODULE INSTRUCTIONS:
          ${utils.printAndIndent base}
          ${utils.printAndIndent cfg.moduleInstructions}
        '';
      };

    # !!! note that scripts cant export config.env vars ???
    scripts.devPrepare = {
      description = "Prepares the project for development.";
      exec = ''
        echo "Preparing Env..."
        ${cfg.prepare}
      '';
    };
    scripts.devInfo =
      let
        base = ''
          echo "   " ROOT_DIR: ${cfg.rootDir}
          echo "   " DIST_DIR: ${cfg.distDir}
          echo "   " TERM: ${cfg.terminal}
        '';
      in
      {
        description = "Prints out some information about the environment.";
        exec = ''
          echo "ENVIRONMENT INFO:"
          ${base}
          ${cfg.info}
        '';
      };
    scripts.killAllPorts = {
      description = "Kills all ports used by the services in the project.";
      exec = ''
        echo "Killing all ports..."
        ${lib.concatStringsSep "\n" (lib.forEach cfg.usedPorts (port: "fuser -k ${builtins.toString port}/tcp"))}
      '';
    };
    scripts.devModuleHelp = {
      description = "Provides info on module creation.";
      exec = ''
        ${utils.printAndIndent ''
          A basic module looks like this:

          {pkgs, lib, config, ...}:
          let
            cfg = config.custom.MODULE_NAME;
          in
          {
            options = {
              custom.MODULE_NAME.SOME_OPTION = lib.mkOption { ... };
            };
            config = {
              custom.base.moduleInstructions = ''\'''\'
                MODULE_NAME MODULE:
                  REQUIRES:
                  - $SOME_ENV_VAR
                  - $IMPURE_VAR
                  - File: $SECRETS_DIR/SOME_FILE
                  - File: not_so_secret.txt (stored)
                  DEFINES:
                    - $SOME_ENV_VAR 
                    - $SOME_OTHER_VAR *
              ''\'''\';
              custom.base.info = ''\'''\'
                echo MODULE_NAME MODULE:
                echo "   " SOME_ENV_VAR: $SOME_ENV_VAR
              ''\'''\';
              env.SOME_ENV_VAR = cfg.SOME_OPTION;
              # THIS CANNOT USE config.env variables, they will be blank
              custom.base.beforeEnterShell = ''\'''\'
                export SOME_OTHER_VAR=$IMPURE_VAR
              ''\'''\';
              # ... devenv options
            };
          }
        
          NOTES:
              dotenv support is disabled because it's dangerousa
              Do NOT use builtins.readFile on secrets

              Always mark if a file will get stored in the nix store
              config.env should only be used for non-secret variables
        ''}
      '';
    };
    packages = [
      pkgs.jq
        pkgs.sops
    ];
  };
}
