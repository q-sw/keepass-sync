# KeePass Sync : Architecture de Synchronisation Multi-Appareils (PC & Android) avec GCS

Solution de synchronisation **100% hors-ligne**, chiffrée de bout en bout et sans risque de perte de données entre un poste de travail Linux (**NixOS / KeePassXC**) et un smartphone (**Android / KeePassDX**), utilisant un bucket **Google Cloud Storage (GCS)** centralisé avec versioning d'objets et fusion intelligente (`keepassxc-cli merge`).

---

## 🏛️ Architecture & Fonctionnement

Contrairement à un montage direct (`gcsfuse`), cette architecture repose sur le principe **Local-First** : chaque appareil lit et écrit dans une copie locale de la base `.kdbx`. Aucun ralentissement ni blocage ne survient en cas de déconnexion réseau (avion, train, wifi défaillant).

```mermaid
flowchart TD
    subgraph Cloud[" Google Cloud Storage "]
        GCS[("Bucket GCS\n(Object Versioning activé)")]
    end

    subgraph Laptop[" PC Portable (NixOS) "]
        KPXC["KeePassXC (GUI)\nÉdition en direct"]
        LocalKDBX[("Base locale\n~/.local/share/keepass/passwords.kdbx")]
        SyncScript["Script de sync\n(rclone + keepassxc-cli merge)"]
        Keyring[("Secret Service / Keyring\nMot de passe maître")]
        SystemdUnits["Systemd User Units\n• Path unit (Push sur sauvegarde)\n• Timer unit (Pull toutes les 5 min)"]

        KPXC <-->|Lecture / Écriture immédiate| LocalKDBX
        SystemdUnits -->|Déclenche| SyncScript
        Keyring -.->|Fournit credentials| SyncScript
        SyncScript <-->|Fusion 3-voies & Sync| LocalKDBX
        SyncScript <-->|rclone copyto| GCS
    end

    subgraph Mobile[" Smartphone (Android) "]
        KPDX["KeePassDX\n(Autofill + Biométrie)"]
        MobileLocal[("Stockage local Android\nDocuments/KeePass/passwords.kdbx")]
        RoundSync["Round-sync ou FolderSync\n(Service Account GCS)"]

        KPDX <-->|SAF (Accès fichier local)| MobileLocal
        RoundSync <-->|Synchro périodique / Wi-Fi| MobileLocal
        RoundSync <-->|API GCS chiffrée| GCS
    end
```

---

## 📋 Pré-requis système

### 1. Environnement de développement Nix (Recommandé)

Ce dépôt fournit un environnement reproductible complet via `flake.nix`. Pour charger instantanément tous les binaires et outils requis :

```bash
nix develop
```

### 2. Liste détaillée des pré-requis système (Binaires & Services)

Si vous installez manuellement les dépendances ou les intégrez dans votre configuration système (`/etc/nixos/configuration.nix` ou `home-manager`) :

| Binaire / Paquet              | Rôle dans l'architecture                                                        | Paquet Nixpkgs          | Paquet Debian/Ubuntu      |
| :---------------------------- | :------------------------------------------------------------------------------ | :---------------------- | :------------------------ |
| `keepassxc` & `keepassxc-cli` | Gestionnaire de mots de passe & outil CLI de fusion au niveau entrée            | `pkgs.keepassxc`        | `keepassxc`               |
| `rclone`                      | Transport robuste et authentifié vers le bucket Google Cloud Storage            | `pkgs.rclone`           | `rclone`                  |
| `secret-tool`                 | Lecture/écriture sécurisée du mot de passe maître dans le trousseau de session  | `pkgs.libsecret`        | `libsecret-tools`         |
| `notify-send`                 | Émission de notifications de bureau lors des fusions et alertes d'erreurs       | `pkgs.libnotify`        | `libnotify-bin`           |
| `gcloud`                      | Provisionnement initial du bucket GCS et du compte de service (Service Account) | `pkgs.google-cloud-sdk` | `google-cloud-cli`        |
| `coreutils` & `util-linux`    | Commandes système standard (`sha256sum`, `flock`, `shred`)                      | Fourni par le système   | `coreutils`, `util-linux` |

### 3. Pré-requis de session utilisateur (Secret Service / Keyring)

Pour autoriser le script en tâche de fond à déverrouiller la base de données et à fusionner les modifications distantes de manière transparente sans afficher d'invite de saisie interactive à chaque synchronisation, un trousseau Secret Service doit être actif sur votre session graphique (GNOME Keyring, KWallet ou KeePassXC Secret Service).

Sur **NixOS**, activez GNOME Keyring dans votre configuration :

```nix
services.gnome.gnome-keyring.enable = true;
security.pam.services.login.enableGnomeKeyring = true;
```

---

## 🚀 Guide de Déploiement Étape par Étape

### Étape 1 : Provisionnement du bucket GCS et du Service Account

Un script automatisé configure le bucket avec les meilleures pratiques de sécurité (moindre privilège IAM et versioning d'objets) :

```bash
nix develop
./scripts/setup-gcp.sh
```

Le script réalise automatiquement :

1. La création d'un bucket GCS sécurisé (ex: `gs://<projet>-keepass-vault`).
2. **L'activation de l'Object Versioning** sur le bucket (permettant d'annuler tout écrasement ou de récupérer un état antérieur à tout moment).
3. La création d'un Service Account dédié (`keepass-sync-sa@...`).
4. L'attribution du rôle strict `roles/storage.objectAdmin` uniquement sur ce bucket.
5. L'export de la clé privée JSON dans `~/.config/keepass-sync/gcp-service-account.json`.
6. La configuration du remote `gcs-keepass` dans `~/.config/rclone/rclone.conf`.

---

### Étape 2 : Migration de Bitwarden vers KeePassXC

1. **Exporter le coffre Bitwarden** :
   - Connectez-vous sur votre coffre Bitwarden (application Web ou Desktop).
   - Allez dans **Paramètres** -> **Exporter le coffre**.
   - Choisissez le format de fichier : **JSON (non chiffré)** _(le format JSON conserve l'arborescence des dossiers, les notes sécurisées, les champs personnalisés et les graines 2FA/TOTP)_.
   - Enregistrez le fichier temporairement dans un dossier en RAM (ex: `/run/user/$UID/bitwarden_export.json`).

2. **Importer dans KeePassXC** :
   - Lancez KeePassXC :
     ```bash
     keepassxc &
     ```
   - Cliquez sur **Base de données** -> **Importer** -> **Bitwarden (JSON)**.
   - Sélectionnez votre fichier exporté.
   - Définissez un mot de passe maître robuste.
   - Enregistrez la base de données dans son emplacement officiel :
     ```bash
     mkdir -p ~/.local/share/keepass
     # Sauvegardez sous : ~/.local/share/keepass/passwords.kdbx
     ```

3. **Vérification & Nettoyage sécurisé** :
   - Vérifiez dans KeePassXC la bonne présence de vos entrées et la génération de vos codes TOTP (`Ctrl+T` sur une entrée avec 2FA).
   - Supprimez définitivement le fichier JSON d'export Bitwarden sans laisser de traces résiduelles sur disque :
     ```bash
     shred -u -z -n 3 /run/user/$UID/bitwarden_export.json
     ```

---

### Étape 3 : Configuration du PC (Linux / NixOS)

1. **Enregistrer le mot de passe maître dans le trousseau de session** :

   ```bash
   ./scripts/setup-keyring.sh
   ```

   _Ce mot de passe reste chiffré par votre session de bureau et n'est jamais écrit en clair dans un fichier._

2. **Premier test de synchronisation** :

   ```bash
   ./scripts/keepass-sync.sh
   ```

   _La base locale est immédiatement vérifiée et téléversée sur votre bucket GCS._

3. **Activation déclarative via Home Manager (Recommandé)** :

   Importez directement le module Home Manager dans votre configuration utilisateur (ou flake dotfiles) :

   ```nix
   imports = [
     # Chemin vers le module du dépôt ou via inputs.keepass-sync.homeManagerModules.default
     /chemin/vers/keepaas_sync/nix/home-manager-module.nix
   ];

   services.keepass-sync = {
     enable = true;
     localPath = "${config.home.homeDirectory}/.local/share/keepass/passwords.kdbx";
     interval = "5m"; # Intervalle de pull/merge périodique
   };
   ```

   Après application (`home-manager switch` ou `nixos-rebuild switch`), Home Manager génère, configure et démarre automatiquement :
   - **`keepass-sync.path`** : Dès que vous enregistrez une modification dans KeePassXC (`Ctrl+S`), le path unit le détecte instantanément via `inotify` et pousse la mise à jour sur GCS en quelques secondes.
   - **`keepass-sync.timer`** : Récupère et fusionne automatiquement les entrées distantes (ex: mot de passe créé depuis votre smartphone) toutes les 5 minutes.
   - **`keepass-sync.service`** : Le service déclenché avec le bon `PATH` et les outils du store Nix hermétiquement liés.

---

### Étape 4 : Configuration du Smartphone Android

1. **Applications recommandées** :
   - **KeePassDX** (disponible sur [F-Droid](https://f-droid.org/packages/com.kunzisoft.keepass.libre/) ou Google Play) : client moderne, open-source, supportant l'Autofill Android et le déverrouillage biométrique (empreinte).
   - **Round-sync** (disponible sur [GitHub Releases](https://github.com/newh酥/round-sync) ou F-Droid) : portage Android open-source officiel de Rclone, supportant nativement Google Cloud Storage avec clé de service. _(Alternative : FolderSync)._

2. **Transfert sécurisé de la clé Service Account** :
   - Transférez le fichier `~/.config/keepass-sync/gcp-service-account.json` sur votre téléphone (via câble USB, KDE Connect, ou `adb push`).
   - Supprimez le fichier de clé sur le stockage partagé du téléphone une fois importé dans l'application.

3. **Configuration de Round-sync** :
   - Ajoutez un nouveau remote :
     - **Nom** : `gcs-keepass`
     - **Type** : `Google Cloud Storage`
     - **Service Account Credentials JSON** : sélectionnez votre fichier `gcp-service-account.json`.
   - Créez une tâche de synchronisation :
     - **Source** : `gcs-keepass:nom-de-votre-bucket/passwords.kdbx`
     - **Destination locale** : dossier `Documents/KeePass/passwords.kdbx` (accessible via Storage Access Framework).
     - **Mode** : Bi-directionnel ou Sync planifiée (au choix, par ex. toutes les 15 minutes ou sur connexion Wi-Fi).

4. **Ouverture dans KeePassDX** :
   - Lancez KeePassDX -> **Ouvrir une base de données existante**.
   - Parcourez votre stockage et sélectionnez le fichier `Documents/KeePass/passwords.kdbx`.
   - Entrez votre mot de passe maître et activez le déverrouillage biométrique.
   - Dans les paramètres d'Android, activez KeePassDX comme **Service de saisie automatique (AutoFill)**.

---

## 🛡️ Résolution des Conflits & Sécurité des Données

### Pourquoi aucune donnée ne peut être perdue ?

1. **Fusion intelligente au niveau des entrées (`keepassxc-cli merge`)** :
   Si vous créez une entrée `Site A` sur le PC hors-ligne et simultanément une entrée `Site B` sur votre smartphone, la prochaine synchronisation ne va pas écraser l'un des fichiers. KeePassXC ouvre les deux bases, compare l'horodatage de chaque entrée, importe `Site B` dans le PC, conserve `Site A`, et repousse la version enrichie sur GCS.
2. **Sauvegarde locale pré-fusion** :
   Avant chaque fusion, le script effectue une copie de sécurité de la base locale dans `~/.cache/keepass-sync/backup_before_merge.kdbx`.
3. **Object Versioning GCS** :
   Toutes les versions antérieures envoyées sur GCS sont historisées. Si une manipulation erronée survenait, vous pouvez lister et restaurer n'importe quelle version précédente :
   ```bash
   gcloud storage objects list --versions gs://nom-de-votre-bucket/
   ```

---

## 🔍 Surveillance et Logs

Pour consulter l'état des synchronisations en temps réel :

```bash
# Vérifier l'état du timer et du path unit
systemctl --user status keepass-sync.timer
systemctl --user status keepass-sync.path

# Consulter les logs détaillés
journalctl --user -u keepass-sync.service -e -f
```
