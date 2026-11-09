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

## 3. Configurer le client local & Rclone

Exécutez le script de configuration client :

```bash
./scripts/setup-config.sh
```

Ce script interactif configure :
- Le chemin local de votre base `.kdbx` (modifiable à l'invite).
- Le nom de l'objet sur GCS.
- La génération du fichier de configuration `~/.config/keepass-sync/config.env`.
- La configuration du remote Rclone `gcs-keepass` avec la clé JSON.

## 4. Configurer le trousseau Secret Service (Linux)

Pour autoriser les fusions en tâche de fond sans invite interactive :

```bash
./scripts/setup-keyring.sh
```
Saisissez votre mot de passe maître KeePass. Il sera stocké de manière chiffrée dans votre trousseau de session de bureau (GNOME Keyring / KWallet).

## 5. Initialiser la base locale

- Si vous migrez depuis Bitwarden, suivez la [Procédure de Migration](file:///home/qsw/dev/keepaas_sync/docs/bitwarden-migration.md).
- Si vous avez déjà une base KeePass existante, placez-la dans le chemin choisi :
  ```bash
  cp /chemin/vers/ma_base.kdbx ~/.local/share/keepass/passwords.kdbx
  chmod 600 ~/.local/share/keepass/passwords.kdbx
  ```

## 6. Valider la première synchronisation

Testez manuellement le script de synchronisation :

```bash
./scripts/keepass-sync.sh
```
La base est vérifiée et téléversée immédiatement vers votre bucket GCS.

## 7. Déclarer le service dans Home Manager

Ajoutez le module dans vos dotfiles Home Manager :

```nix
imports = [
  /chemin/vers/keepaas_sync/nix/home-manager-module.nix
];

services.keepass-sync = {
  enable = true;
  localPath = "${config.home.homeDirectory}/.local/share/keepass/passwords.kdbx";
  interval = "5m"; # Pull régulier toutes les 5 minutes
};
```

Appliquez votre configuration :
```bash
home-manager switch # ou nixos-rebuild switch
```

Home Manager active immédiatement :
- `keepass-sync.path` : Déclenche un push instantané dès modification du fichier `.kdbx` dans KeePassXC.
- `keepass-sync.timer` : Interroge et fusionne les modifications distantes toutes les 5 minutes.

Pour configurer votre smartphone Android, consultez la [Configuration Android](file:///home/qsw/dev/keepaas_sync/docs/android-setup.md).
