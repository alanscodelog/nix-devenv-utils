{ pkgs
, lib
, config
, inputs
, ...
}:
let
  hbaConfEntry = (e: builtins.concatStringsSep " " e);
  cfg = config.custom.postgres;
  utils = import ../utils.nix { };
  c = utils.colors;
in
{
  options.custom.postgres = {
    enabled = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''Whether to enable the module, defaults to false.'';
    };
    runDrizzle = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''Whether to run drizzle-kit studio.'';
    };
    superuser = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''The postgres superuser. Defaults to $USER.'';
    };
    user = lib.mkOption {
      type = lib.types.str;
      description = ''The postgres user (the one the server uses to connect. Defaults to "app". This must be different than superuser'';
      default = "app";
    };
    previousVersion = lib.mkOption {
      type = lib.types.str;
      default = "16";
      description = ''The previous postgres version to use for the upgrade script. '';
    };
    database_name = lib.mkOption {
      type = lib.types.str;
      default = "main";
      description = ''The name of the database to create. Defaults to "main".'';
    };
    debug_all = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''Whether to enable debug settings so postgress will log to stdout (collector is disabled). Defaults to false.'';
    };
  };
  config =
    let
      superuser =
        if (cfg.superuser != "") then cfg.superuser else builtins.getEnv "USER";
    in
    lib.mkIf cfg.enabled
      {
        custom.base.moduleInstructions = ''
          POSTGRES MODULE:
            REQUIRES:
                - $POSTGRES_PASSWORD
                - $POSTGRES_SUPERUSER_PASSWORD 
                - $USER
            DEFINES:
                - $POSTGRES_SUPERUSER * = $USER (unless custom.postgres.superuser is set)
                - $POSTGRES_USER = custom.postgres.user
                - $POSTGRES_NAME = custom.postgres.database_name
                - $POSTGRES_HOST (localhost)
                - $POSTGRES_PORT
        '';
        env.POSTGRES_SUPERUSER = superuser;
        env.POSTGRES_NAME = cfg.database_name;
        env.POSTGRES_USER = cfg.user;
        env.POSTGRES_HOST = if (config.services.postgres.listen_addresses != "") then "${builtins.toString config.services.postgres.listen_addresses}" else "localhost";
        # devenv changed how this works, breaking scripts
        env.PGHOST = "${config.env.DEVENV_RUNTIME}/postgres";
        env.POSTGRES_PORT = if (config.services.postgres.port != null) then "${builtins.toString config.services.postgres.port}" else "5432";
        custom.base.beforeEnterShell = lib.optionalString (cfg.superuser != "") ''
          export POSTGRES_SUPERUSER=${superuser}
        '';

        custom.base.info = ''
          echo ${c.green} "POSTGRES_MODULE:" ${c.reset}
          echo "   " POSTGRES_USER: $POSTGRES_USER
          echo "   " POSTGRES_SUPERUSER: $POSTGRES_SUPERUSER
          echo "   " POSTGRES_NAME: $POSTGRES_NAME
          echo "   " POSTGRES_HOST: $POSTGRES_HOST
          echo "   " POSTGRES_PORT: $POSTGRES_PORT
        ''
        + (if (cfg.user == cfg.superuser) then ''
          echo ${c.red} "ERROR: Superuser and user cannot be the same." ${c.reset}
        '' else "")
        ;

        custom.base.usedPorts = [ (lib.strings.toInt config.env.POSTGRES_PORT) ];
        # processes.drizzle-studio = lib.mkIf cfg.runDrizzle {
        #   exec = "pnpm drizzle-kit studio";
        #   process-compose.availability.max_restarts = 5;
        # };
        packages = [
          # beekeeper-studio is nicer but awaiting https://github.com/beekeeper-studio/beekeeper-studio/issues/361
          pkgs.dbeaver-bin
        ];
        services.postgres = {
          enable = true;
          listen_addresses = "localhost";
          initialDatabases = [{
            user = cfg.user;
            name = cfg.database_name;

            # user is created by us because it doesn't get created if pass isn't defined *
            # and if user isn't set, then devenv's psql won't use that user and some permission grants fail to stick (idk why though since we can definately connect and they temporarily work and don;t error)
            # * - this is because it would get stored in the derivation if we did it that way
            #     we load the env vars into postgres instead
            initialSQL = ''
              \getenv user_password POSTGRES_PASSWORD

              CREATE USER "${cfg.user}" WITH PASSWORD :'user_password';

              GRANT ALL PRIVILEGES ON DATABASE "${cfg.database_name}" TO "${cfg.user}";
              GRANT ALL PRIVILEGES ON SCHEMA public TO "${cfg.user}";
              CREATE EXTENSION IF NOT EXISTS pg_uuidv7;
            '';
          }];
          extensions = extensions: [ extensions.pg_uuidv7 ];

          initialScript = ''
            \getenv superuser_password POSTGRES_SUPERUSER_PASSWORD
            ALTER USER "${superuser}" WITH PASSWORD :'superuser_password' SUPERUSER;
          '';
          # note that the first matching rule is used
          # so order is important and the match does NOT fallback to the next line
          hbaConf = builtins.concatStringsSep "\n" [
            # \"local\" is for Unix domain socket connections only"
            # specifically allow superuser to connect to the socket without password
            (hbaConfEntry [ "local" "all" "${superuser}" "peer" ])
            # we must still allow  postgres user or the initial config of the db fails"
            (hbaConfEntry [ "local" "all" "postgres" "peer" ])
            # IPv4 local connections:"
            (hbaConfEntry [ "host" "all" "all" "127.0.0.1/32" "scram-sha-256" ])
            # IPv6 local connections:"
            (hbaConfEntry [ "host" "all" "all" "::1/128" "scram-sha-256" ])
            # allow replication from localhost, app user w/ password
            (hbaConfEntry [ "local" "replication" cfg.user "scram-sha-256" ])
            # ...or user with the replication privilege."
            (hbaConfEntry [ "local" "replication" "all" "peer" ])
            (hbaConfEntry [ "host" "replication" "all" "127.0.0.1/32" "scram-sha-256" ])
            (hbaConfEntry [ "host" "replication" "all" "::1/128" "scram-sha-256" ])
          ];
          settings = lib.mkIf cfg.debug_all {
            log_connections = true;
            log_statement = "all";
            logging_collector = false;
            log_disconnections = true;
          };
        };
        process.managers.process-compose.settings.processes = {
          # the default readiness probe won't work because it doesn't used an authed connection
          postgres.readiness_probe.exec.command = lib.mkForce ''
            if [[ -f "$PGDATA/.devenv_initialized" ]]; then
              ${pkgs.postgresql}/bin/pg_isready -d template1 && \
              devPgConnect -c "SELECT 1" template1 > /dev/null 2>&1
            else
              echo "Waiting for PostgreSQL initialization to complete..." 2>&1
              exit 1
            fi
          '';
        };
        scripts.devPgConnect = {
          description = "Opens a psql shell as the configured user.";
          exec = "PGPASSWORD=$POSTGRES_PASSWORD ${pkgs.postgresql}/bin/psql -h $POSTGRES_HOST -d $POSTGRES_NAME -U $POSTGRES_USER";
        };
        scripts.devPgConnectLocal = {
          description = "Opens a \"local\" psql shell via the PGHOST linux socket as the configured superuser.";
          exec = "PGPASSWORD=$POSTGRES_SUPERUSER_PASSWORD ${pkgs.postgresql}/bin/psql -h $PGHOST -d $POSTGRES_NAME -U $POSTGRES_SUPERUSER";
        };
        scripts.devPgPing = {
          description = "Pings the postgres server to check if it's up.";
          exec = "${pkgs.postgresql}/bin/pg_isready --dbname=$POSTGRES_NAME --host=$POSTGRES_HOST --port=${builtins.toString config.services.postgres.port}";
        };
        scripts.devPgUpgrade = {
          exec =
            let
              dataDir = "${config.env.DEVENV_STATE}/postgres";
              movedDataDir = "${config.env.DEVENV_STATE}/upgrade";
              oldBinDir = "${pkgs."postgresql_${cfg.previousVersion}"}/bin";
              newBinDir = "${pkgs.postgresql}/bin";
            in
            ''
              set -e
              echo "Current Postgres Version: $(${pkgs.postgresql}/bin/psql --version)"
              echo "Previous Postgres Version (custom.postgres.previousVersion): ${cfg.previousVersion}"
              echo "CAREFUL: Be sure the above is correct. Starting in 10s:"
              sleep 10
              echo "Moving data to ${movedDataDir}"
              if [ -d "${movedDataDir}" ]; then
                echo "Directory '${movedDataDir}' already exists. Skipping move. "
                echo "Checking postgres..."
                ${pkgs.postgresql}/bin/pg_upgrade \
                  --old-bindir=${oldBinDir} \
                  --old-datadir=${config.env.DEVENV_STATE}/upgrade/ \
                  --new-bindir=${newBinDir} \
                  --new-datadir=${dataDir} \
                  --clone \
                  --check
                echo "Checked postgres"
                echo "You can now safely run:"
                echo ${pkgs.postgresql}/bin/pg_upgrade \
                  --old-bindir=${oldBinDir} \
                  --old-datadir=${config.env.DEVENV_STATE}/upgrade/ \
                  --new-bindir=${newBinDir} \
                  --new-datadir=${dataDir} \
                  --clone
              else
                mv "${dataDir}" "${movedDataDir}"
                mv "${dataDir}" "${movedDataDir}"
                echo "Moved old data to ${movedDataDir}"
                echo "Double backed up to ${movedDataDir}-backup"
                rm -rf ${dataDir}
                echo "Deteled data directory ${dataDir}"
                echo "You must now start postgres, let it init, then quit."
              fi
            '';
        };

      };
}
