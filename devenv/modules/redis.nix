{ pkgs, lib, config, inputs, ... }:
let
  cfg = config.custom.redis;
in
{
  options.custom.redis = {
    user = lib.mkOption {
      type = lib.types.str;
      default = "admin";
      description = ''The redis user (the one the server uses to connect and which will own the database. Defaults to "admin".'';
    };
    enabled = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''Whether to enable the module, defaults to true.'';
    };
  };
  config = lib.mkIf cfg.enabled {
    custom.base.moduleInstructions = ''
      REDIS MODULE:
        REQUIRES:
            - $REDIS_HASHED_PASSWORD 
                - can be generated with: printf $REDIS_PASSWORD | sha256sum | cut -c-64
        DEFINES:
            - $REDIS_HOST
            - $REDIS_PORT
            - $REDIS_USER 
    '';
    env.REDIS_HOST = if (config.services.redis.bind != null) then "${builtins.toString config.services.redis.bind}" else "localhost";
    env.REDIS_PORT = if (config.services.redis.port != null) then "${builtins.toString config.services.redis.port}" else "6379";
    env.REDIS_USER = cfg.user;
    custom.base.info = ''
      echo REDIS MODULE:
      echo "   " REDIS_HOST: $REDIS_HOST
      echo "   " REDIS_PORT: $REDIS_PORT
      echo "   " REDIS_USER: $REDIS_USER
    '';
    custom.base.usedPorts = [ (lib.strings.toInt config.env.REDIS_PORT) ];

    services.redis =
      {
        enable = true;
        extraConfig = ''
          user ${cfg.user} on #${builtins.getEnv "REDIS_HASHED_PASSWORD"} +@all ~*
          loglevel notice
        '';
      };
  };
}
