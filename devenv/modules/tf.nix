{ pkgs, lib, config, inputs, ... }:
let
  cfg = config.custom.tf;
in
{
  options.custom.tf = {
    enabled = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''Whether to enable the module, defaults to false.'';
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.opentofu;
      description = ''opentofu package to use.'';
    };
  };
  config = lib.mkIf cfg.enabled {
    custom.base.moduleInstructions = ''
      OPENTOFU MODULE:
          DEFINES: nothing
    '';
    scripts =
      let
        secretsFound = ''sops --decrypt --output-type json .secrets/secrets.tf.enc.yaml | jq -r 'to_entries | map("\t\(.key)") | join("\n")' '';
        deploySecretsLoader = ''sops --decrypt --output-type json .secrets/secrets.tf.enc.yaml | jq -r 'with_entries(select(.key | startswith("backend") | not)) | to_entries | map("--var=\"\(.key)=\(.value)\"") | join(" ")' '';
        deploySecretsLoaderWithBackend = ''sops --decrypt --output-type json .secrets/secrets.tf.enc.yaml | jq -r 'del(.backend) | to_entries | map(if (.key | startswith("backend")) then "--backend-config=\"\(.key | ltrimstr("backend_"))=\(.value)\"" else "--var=\"\(.key)=\(.value)\"" end) | join(" ")' '';
      in
      {
        tofuListSecrets =
          {
            description = "Lists the secrets that would be loaded when running the wrapped tofu.";
            exec = ''
              echo "Would load secrets:"
              echo $(${secretsFound})
              echo "Done loading."
            '';
          };
        tofu = {
          exec = ''
            ${deploySecretsLoader} | xargs ${pkgs.opentofu}/bin/tofu "$@"
          '';
          description = "Wrapper around tofu that auto loads secrets in .secrets/secrets.prod.deploy.enc.yaml as vars, nested vars are not supported. Anything starting with backend is ignored, see tofuWithBackend";
        };
        tofuWithBackend = {
          exec = ''
            ${deploySecretsLoaderWithBackend} | xargs ${pkgs.opentofu}/bin/tofu "$@"
          '';
          description = "Wrapper around tofu that also loads any keys starting with backend_ as --backend-config=rest_of_key_name=value. This is useful for the tofu init command.";
        };
        rawTofu = {
          description = "Unwrapped tofu executable. The wrapped one can't handle commands that require input. and also has some issues with certain commands like outputs.";
          exec = ''${pkgs.opentofu}/bin/tofu "$@"'';
        };
      };
  };
}
