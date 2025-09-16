{ pkgs, lib, config, inputs, ... }:
let
  cfg = config.custom.android;
in
{
  options.custom.android = {
    keystoreAlias = lib.mkOption {
      type = lib.types.str;
      description = ''The keystore alias to use for signing. Determines what $ANDROID_KS_ALIAS and $ANDROID_KS_ALIAS_PASSWORD_PATH are set to. The module assumes you will be using a keystore per app and naming them android.[ALIAS].keystore'';
    };
    apkLocation = lib.mkOption {
      type = lib.types.str;
      default = "android/app/build/outputs/apk/release/app-release-unsigned.apk";
      description = ''The location of the unsigned apk to sign. Defaults to android/app/build/outputs/apk/release/app-release-unsigned.apk.'';
    };
    signedApkLocation = lib.mkOption {
      type = lib.types.str;
      default = "android/app/build/outputs/apk/release/app-release-signed.apk";
      description = ''The output location of the signed apk for the devAndroidSign command. Defaults to android/app/build/outputs/apk/release/app-release-signed.apk.'';
    };
    enabled = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''Whether to enable the module, defaults to true.'';
    };
  };
  config = lib.mkIf cfg.enabled {
    custom.base.moduleInstructions = ''
      ANDROID MODULE:
          DEFINES: (as paths, does not read the files)
          The naming is for compatibility with the nuxt android module.

              - $ANDROID_KS_ALIAS *
                  = custom.android.keystoreAlias
              - $ANDROID_KS_PATH *
                  = $SECRETS_DIR/android.$ANDROID_KS_ALIAS.keystore
              - $ANDROID_KS_PASSWORD_PATH  *
                  = $SECRETS_DIR/android.$ANDROID_KS_ALIAS.keystore.password
                  - This will also be used as the alias password by the nuxt module.

              - $ANDROID_SDK_ROOT
              - $ANDROID_API
              - $ANDROID_BUILD_TOOLS_VERSION
              - $CAPACITOR_ANDROID_STUDIO_PATH
              - $ANDROID_BUILD_DIR
    '';

    custom.base.beforeEnterShell = 
    lib.optionalString (builtins.getEnv "SECRETS_DIR" != "") ''
      export ANDROID_KS_PATH="$SECRETS_DIR/android.${cfg.keystoreAlias}.keystore"
      export ANDROID_KS_PASSWORD_PATH="$SECRETS_DIR/android.${cfg.keystoreAlias}.keystore.password"
      export ANDROID_KS_ALIAS_PASSWORD_PATH="$SECRETS_DIR/android.${cfg.keystoreAlias}.keystore.password"
    '';
    # note this and ANDROID_HOME must be changed manually in android studio :/
    env.ANDROID_SDK_ROOT = "${builtins.getEnv "ANDROID_HOME"}/share/android-sdk";
    env.ANDROID_API = "${lib.lists.last config.android.platforms.version}";
    env.ANDROID_BUILD_TOOLS_VERSION = "${builtins.elemAt config.android.buildTools.version 0}";
    env.CAPACITOR_ANDROID_STUDIO_PATH = "${pkgs.android-studio}/bin/android-studio";
    # https://github.com/tadfisher/android-nixpkgs/issues/46#issuecomment-1809872521
    # https://github.com/NixOS/nixpkgs/issues/72220
    env.ANDROID_BUILD_DIR = "${config.custom.base.distDir}/capacitor/build";
    env.ANDROID_KS_ALIAS = cfg.keystoreAlias;

    custom.base.info = ''
      echo ANDROID_MODULE:
      echo "   " ANDROID_KS_ALIAS: $ANDROID_KS_ALIAS
      echo "   " ANDROID_KS_PATH: $ANDROID_KS_PATH
      echo "   " ANDROID_KS_PASSWORD_PATH: $ANDROID_KS_PASSWORD_PATH
      echo "   " ANDROID_SDK_ROOT: $ANDROID_SDK_ROOT  
      echo "   " ANDROID_API: $ANDROID_API
      echo "   " ANDROID_BUILD_TOOLS_VERSION: $ANDROID_BUILD_TOOLS_VERSION
      echo "   " CAPACITOR_ANDROID_STUDIO_PATH: $CAPACITOR_ANDROID_STUDIO_PATH
      echo "   " ANDROID_BUILD_DIR: $ANDROID_BUILD_DIR
    '';
    android = {
      enable = true;
      buildTools.version = [ "34.0.0" ];
      # the last elemenent is used as the main configured version for gradle
      platforms.version = [ "33" "34" ];
    };
    languages.java = {
      enable = true;
    };
    packages = [
      pkgs.openjdk
      pkgs.apksigner
    ];
    scripts.devAndroidKeystoreList = {
      description = "Lists the android keystore.";
      exec = ''
        ${pkgs.openjdk}/bin/keytool -list -v -keystore $ANDROID_KS_PATH -storepass $ANDROID_KS_PASSWORD
      '';
    };
    scripts.devAndroidSign = {
      description = "Signs the configured apk (custom.android.apkLocation/signedApkLocation) with the keystore.";
      exec = ''
        ${pkgs.apksigner}/bin/apksigner sign \
        --ks $ANDROID_KS_PATH \
        --ks-pass file:$ANDROID_KS_PASSWORD_PATH \
        --in ${cfg.apkLocation} \
        --out ${cfg.signedApkLocation} \
        --ks-key-alias $ANDROID_KS_ALIAS \
        --key-pass file: $ANDROID_KS_PASSWORD_PATH
      '';
    };
  };
}
