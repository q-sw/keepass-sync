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

    bucket = lib.mkOption {
      type = lib.types.str;
      example = "qsw-main-keepass-vault";
      description = "Nom du bucket Google Cloud Storage hébergeant la base KeePass.";
    };

    localPath = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/Documents/Passwords.kdbx";
      description = "Chemin absolu vers la base de données locale KeePass (.kdbx).";
    };

    object = lib.mkOption {
      type = lib.types.str;
      default = "Passwords.kdbx";
      description = "Nom du fichier KeePass stocké sur le bucket GCS.";
    };

    serviceAccountKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.config/keepass-sync/gcp-service-account.json";
      description = "Chemin vers la clé JSON du compte de service GCP.";
    };

    passwordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/keepass-master-password";
      description = "Chemin optionnel vers un fichier secret contenant le mot de passe maître (ex: via sops-nix). Si null, utilise Secret Service.";
    };

    passwordCommand = lib.mkOption {
      type = lib.types.str;
      default = "secret-tool lookup service keepass-sync user master";
      description = "Commande shell pour récupérer le mot de passe maître KeePass si passwordFile est null.";
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "5m";
      description = "Intervalle de répétition du timer de synchronisation périodique.";
    };

    notify = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Activer les notifications de bureau lors des fusions ou erreurs.";
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

    # Génération déclarative automatique du fichier de configuration ~/.config/keepass-sync/config.env
    xdg.configFile."keepass-sync/config.env".text = ''
      # Généré automatiquement par Home Manager - NE PAS MODIFIER MANUELLEMENT
      KEEPASS_LOCAL_PATH="${cfg.localPath}"
      KEEPASS_RCLONE_REMOTE="gcs-keepass"
      KEEPASS_GCS_BUCKET="${cfg.bucket}"
      KEEPASS_GCS_OBJECT="${cfg.object}"
      KEEPASS_SA_KEY_FILE="${cfg.serviceAccountKeyFile}"
      KEEPASS_PASSWORD_FILE="${if cfg.passwordFile != null then cfg.passwordFile else ""}"
      KEEPASS_PASSWORD_COMMAND="${cfg.passwordCommand}"
      KEEPASS_NOTIFY_ENABLED="${if cfg.notify then "1" else "0"}"
    '';

    # Hook d'activation Home Manager : prépare les répertoires et enregistre le profil Rclone
    home.activation.keepassSyncSetup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD mkdir -p "$(dirname "${cfg.localPath}")"
      $DRY_RUN_CMD mkdir -p "${config.home.homeDirectory}/.config/keepass-sync"

      if [ -f "${cfg.serviceAccountKeyFile}" ]; then
        if ! ${pkgs.rclone}/bin/rclone listremotes 2>/dev/null | grep -q "^gcs-keepass:"; then
          $DRY_RUN_CMD ${pkgs.rclone}/bin/rclone config create gcs-keepass gcs \
            service_account_file "${cfg.serviceAccountKeyFile}" \
            bucket_policy_only true >/dev/null 2>&1 || true
        fi
      fi
    '';

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
          "KEEPASS_GCS_BUCKET=${cfg.bucket}"
          "KEEPASS_GCS_OBJECT=${cfg.object}"
          "KEEPASS_NOTIFY_ENABLED=${if cfg.notify then "1" else "0"}"
          "RCLONE_CONFIG_GCS_KEEPASS_TYPE=gcs"
          "RCLONE_CONFIG_GCS_KEEPASS_SERVICE_ACCOUNT_FILE=${cfg.serviceAccountKeyFile}"
          "RCLONE_CONFIG_GCS_KEEPASS_BUCKET_POLICY_ONLY=true"
        ] ++ lib.optional (cfg.passwordFile != null) "KEEPASS_PASSWORD_FILE=${cfg.passwordFile}";
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
