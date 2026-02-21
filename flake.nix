{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = { self, ... }@inputs: {
    devenvModule = {
      imports = [ ./devenv/modules ];
    };
    utils = import ./devenv/utils.nix;
  };
}

