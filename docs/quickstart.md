# Guide de Démarrage Rapide (Quickstart)

Ce guide résume les étapes pour déployer et synchroniser votre base KeePass entre votre laptop NixOS et Google Cloud Storage en quelques minutes.

---

## 1. Charger l'environnement pré-requis

Grâce au Flake Nix, entrez directement dans le shell contenant tous les outils :

```bash
nix develop
```

## 2. Provisionner l'infrastructure Cloud (GCS & IAM)

Exécutez le script dédié au provisionnement Google Cloud :

```bash
./scripts/setup-gcp.sh
```

Ce script configure exclusivement le côté GCP :
- Création du bucket GCS avec **Object Versioning activé**.
- Création du Service Account restreint à `roles/storage.objectAdmin` sur le bucket.
- Export sécurisé de la clé privée JSON dans `~/.config/keepass-sync/gcp-service-account.json`.

## 3. Configuration automatique via Home Manager (Recommandé)

Si vous utilisez Home Manager, **toute la configuration locale est gérée automatiquement lors de l'activation**. Inutile de lancer `setup-config.sh`.

Ajoutez simplement le module dans vos dotfiles :

```nix
imports = [
  /chemin/vers/keepaas_sync/nix/home-manager-module.nix
];

services.keepass-sync = {
  enable = true;
  bucket = "qsw-main-keepass-vault"; # Nom de votre bucket GCS
  localPath = "${config.home.homeDirectory}/Documents/Passwords.kdbx";
  
  # Optionnel : gestion déclarative du secret (sops-nix / agenix)
  # passwordFile = "/run/secrets/keepass-master-password";
};
```

À l'activation (`home-manager switch`), le module prend tout en charge automatiquement :
1. Crée les dossiers locaux nécessaires.
2. Génère le fichier `~/.config/keepass-sync/config.env`.
3. Configure automatiquement le profil `gcs-keepass` dans Rclone via la clé Service Account.
4. Active `keepass-sync.path` (push immédiat sur sauvegarde) et `keepass-sync.timer` (pull/merge toutes les 5 min).

*(Alternative sans Home Manager : exécutez manuellement `./scripts/setup-config.sh`)*.

## 4. Configurer le trousseau Secret Service (Linux)

Si vous n'utilisez pas l'option `passwordFile` (avec sops-nix), enregistrez une fois le mot de passe maître dans le trousseau de session :

```bash
./scripts/setup-keyring.sh
```
Saisissez votre mot de passe maître KeePass. Il sera stocké de manière chiffrée dans votre trousseau de session de bureau (GNOME Keyring / KWallet).

## 5. Initialiser la base locale

- Si vous migrez depuis Bitwarden, suivez la [Procédure de Migration](file:///home/qsw/dev/keepaas_sync/docs/bitwarden-migration.md).
- Si vous avez déjà une base KeePass existante, placez-la dans le chemin choisi :
  ```bash
  cp /chemin/vers/ma_base.kdbx ~/Documents/Passwords.kdbx
  chmod 600 ~/Documents/Passwords.kdbx
  ```

## 6. Valider la première synchronisation

Testez manuellement le script de synchronisation :

```bash
./scripts/keepass-sync.sh
```
La base est vérifiée et téléversée immédiatement vers votre bucket GCS.

Pour configurer votre smartphone Android, consultez la [Configuration Android](file:///home/qsw/dev/keepaas_sync/docs/android-setup.md).
