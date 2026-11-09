{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.keepass-sync;
  syncScript = pkgs.writeShellScriptBin "keepass-sync" (
    builtins.readFile ../scripts/keepass-sync.sh
  );
in
{
  options.services.keepass-sync = {
    enable = lib.mkEnableOption "KeePass GCS multi-device intelligent synchronisation service";

    localPath = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.local/share/keepass/passwords.kdbx";
      description = "Chemin absolu vers la base de données locale KeePass (.kdbx).";
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "5m";
      description = "Intervalle de répétition du timer de synchronisation périodique.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      keepassxc
      rclone
      libsecret
      libnotify
      syncScript
    ];

    systemd.user.services.keepass-sync = {
      Unit = {
        Description = "Synchronisation bidirectionnelle KeePass avec GCS";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${syncScript}/bin/keepass-sync";
        Environment = [
          "PATH=${
            lib.makeBinPath (
              with pkgs;
              [
                keepassxc
                rclone
                libsecret
                libnotify
                coreutils
                findutils
                util-linux
                gnugrep
                gawk
              ]
            )
          }"
          "KEEPASS_LOCAL_PATH=${cfg.localPath}"
        ];
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    systemd.user.timers.keepass-sync = {
      Unit = {
        Description = "Timer périodique de synchronisation KeePass";
        After = [ "network-online.target" ];
      };
      Timer = {
        OnBootSec = "1m";
        OnStartupSec = "1m";
        OnUnitActiveSec = cfg.interval;
        Persistent = true;
      };
      Install = {
        WantedBy = [ "timers.target" ];
      };
    };

    systemd.user.paths.keepass-sync = {
      Unit = {
        Description = "Détecteur d'écriture sur la base locale KeePass";
      };
      Path = {
        PathModified = cfg.localPath;
        Unit = "keepass-sync.service";
      };
      Install = {
        WantedBy = [ "paths.target" ];
      };
    };
  };
}
