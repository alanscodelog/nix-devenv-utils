{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    systems.url = "github:nix-systems/default";
    devenv = {
      url = "github:cachix/devenv";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # does not follow anything
    flake-utils.url = "github:numtide/flake-utils";
    utils = {
      url = "github:alanscodelog/nix-devenv-utils";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # IMPORTANT: this must be pinned to the same version in package.json
    # and no reading it directly is not supported (https://github.com/NixOS/nix/issues/4945)
    playwright.url = "github:pietdevries94/playwright-web-flake/1.54.0";
  };
  nixConfig = {
    extra-trusted-public-keys = "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=";
    extra-substituters = "https://devenv.cachix.org";
  };
  outputs =
    { self
    , nixpkgs
    , devenv
    , systems
    , playwright
    , utils
    , ...
    } @ inputs:
    let
      forEachSystem = nixpkgs.lib.genAttrs (import systems);
    in
    {
      packages = forEachSystem (system: {
        devenv-up = self.devShells.${system}.default.config.procfileScript;
        devenv-test = self.devShells.${system}.default.config.test;
      });

      devShells = forEachSystem
        (system:
          let
            overlay = final: prev: {
              inherit (playwright.packages.${system}) playwright-test playwright-driver;
            };
            pkgs = import nixpkgs {
              inherit system;
              overlays = [ overlay ];
            };
          in
          {
            default = devenv.lib.mkShell {
              inherit inputs pkgs;
              modules =
                let
                in
                [
                  utils.devenvModule
                  ({ pkgs, config, ... }: {
                    custom.js.nodejs.package = pkgs.nodejs_24;
                    # custom.js.setupPlaywright = true;
                    # custom.js.playwrightPackage = pkgs.playwright;

                    # custom.electron.enabled = true;
                    # custom.tf.enabled = true;
                    # custom.redis.enabled = true;
                    # custom.postgres.enabled = true;
                  })
                ];
            };
          });
    };
}
