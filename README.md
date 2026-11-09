# KeePass Sync : Synchronisation Multi-Appareils (PC & Android) avec GCS

Solution de synchronisation **100% hors-ligne (Local-First)**, chiffrée de bout en bout et sans risque de conflit entre un poste Linux (**NixOS / KeePassXC**) et un smartphone (**Android / KeePassDX**), via un bucket **Google Cloud Storage (GCS)** avec versioning d'objets et fusion intelligente (`keepassxc-cli merge`).

---

## 🏛️ Vue d'Ensemble de l'Architecture

Chaque appareil lit et écrit instantanément dans sa copie locale (`passwords.kdbx`). Aucun blocage ne survient en cas de coupure réseau.

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

        KPXC <-->|Lecture / Écriture locale| LocalKDBX
        SystemdUnits -->|Déclenche| SyncScript
        Keyring -.->|Fournit credentials| SyncScript
        SyncScript <-->|Fusion 3-voies| LocalKDBX
        SyncScript <-->|rclone copyto| GCS
    end

    subgraph Mobile[" Smartphone (Android) "]
        KPDX["KeePassDX\n(Autofill + Biométrie)"]
        MobileLocal[("Stockage local Android\nDocuments/KeePass/passwords.kdbx")]
        RoundSync["Round-sync ou FolderSync\n(Service Account GCS)"]

        KPDX <-->|SAF (Accès fichier local)| MobileLocal
        RoundSync <-->|Synchro périodique| MobileLocal
        RoundSync <-->|API GCS chiffrée| GCS
    end
```

---

## 📋 Pré-requis système

### 1. Environnement Nix Flake (Recommandé)

Le dépôt intègre un environnement reproductible complet. Pour charger l'ensemble des outils sans polluer votre système :

```bash
nix develop
```

### 2. Liste détaillée des pré-requis système (Binaires & Services)

Si vous installez manuellement les dépendances ou les intégrez dans votre configuration globale :

| Binaire / Outil | Rôle dans l'architecture | Paquet Nixpkgs | Paquet Debian/Ubuntu |
| :--- | :--- | :--- | :--- |
| `keepassxc` & `keepassxc-cli` | Gestionnaire de mots de passe & moteur de fusion d'entrées | `pkgs.keepassxc` | `keepassxc` |
| `rclone` | Transport chiffré et authentifié vers Google Cloud Storage | `pkgs.rclone` | `rclone` |
| `secret-tool` | Lecture/écriture sécurisée du mot de passe maître dans le trousseau | `pkgs.libsecret` | `libsecret-tools` |
| `notify-send` | Notifications de bureau discrètes lors des fusions et erreurs | `pkgs.libnotify` | `libnotify-bin` |
| `gcloud` | Provisionnement du bucket GCS et du compte de service (Service Account) | `pkgs.google-cloud-sdk` | `google-cloud-cli` |
| `coreutils` & `util-linux` | Commandes système standard (`sha256sum`, `flock`, `shred`) | Fourni par le système | `coreutils`, `util-linux` |

### 3. Trousseau de session utilisateur (Secret Service / Keyring)

Pour autoriser les fusions silencieuses en tâche de fond (sans prompt interactif à chaque synchronisation), activez GNOME Keyring dans votre configuration **NixOS** :

```nix
services.gnome.gnome-keyring.enable = true;
security.pam.services.login.enableGnomeKeyring = true;
```

---

## 📚 Documentation détaillée

Pour naviguer pas-à-pas selon votre besoin, consultez les guides dédiés dans le dossier [`docs/`](file:///home/qsw/dev/keepaas_sync/docs/) :

| Guide | Description |
| :--- | :--- |
| 🚀 [**Guide de Démarrage Rapide (Quickstart)**](file:///home/qsw/dev/keepaas_sync/docs/quickstart.md) | Déploiement express de l'infrastructure GCS, trousseau et module Home Manager. |
| 🔄 [**Procédure de Migration Bitwarden**](file:///home/qsw/dev/keepaas_sync/docs/bitwarden-migration.md) | Export JSON propre, import KeePassXC, vérification TOTP/2FA et nettoyage sécurisé (`shred`). |
| 📱 [**Configuration Android**](file:///home/qsw/dev/keepaas_sync/docs/android-setup.md) | Configuration de KeePassDX, Round-sync / FolderSync, clé Service Account et AutoFill. |
| 🛡️ [**Architecture & Conflits**](file:///home/qsw/dev/keepaas_sync/docs/architecture-concurrency.md) | Détails de la fusion `keepassxc-cli merge`, Object Versioning sur GCS et logs systemd. |

---

## ⚡ Commandes utiles au quotidien

```bash
# Provisionner l'infrastructure GCP (bucket, IAM, clé)
./scripts/setup-gcp.sh

# Configurer les chemins locaux et Rclone
./scripts/setup-config.sh

# Enregistrer le mot de passe maître dans le trousseau
./scripts/setup-keyring.sh

# Déclencher manuellement une synchronisation
./scripts/keepass-sync.sh

# Consulter les logs de synchronisation automatique
journalctl --user -u keepass-sync.service -e -f
```
