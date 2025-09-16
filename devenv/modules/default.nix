{ ... }:

let
in
{
  imports = [
    ./android.nix
    ./base.nix
    ./electron.nix
    ./js.nix
    ./postgres.nix
    ./redis.nix
    ./tf.nix
  ];
}
