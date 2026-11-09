{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.keepass-sync;
in
{
  options.services.keepass-sync = {
    enable = lib.mkEnableOption "KeePass multi-device sync system prerequisites";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      keepassxc
      rclone
      libsecret
      libnotify
      google-cloud-sdk
    ];

    # Active le support Secret Service / Gnome Keyring pour le stockage du mot de passe
    services.gnome.gnome-keyring.enable = lib.mkDefault true;
    security.pam.services.login.enableGnomeKeyring = lib.mkDefault true;
  };
}
