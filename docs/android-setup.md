# Configuration du Smartphone Android

Ce guide détaille la mise en place de la synchronisation de votre base `.kdbx` sur Android via **KeePassDX** et un synchroniseur d'arrière-plan compatible Google Cloud Storage (**Round-sync** ou **FolderSync**).

---

## 1. Applications requises

Installez depuis F-Droid ou le Google Play Store :

1. **[KeePassDX](https://f-droid.org/packages/com.kunzisoft.keepass.libre/)** :
   - Client KeePass libre, open-source et sécurisé pour Android.
   - Supporte le déverrouillage biométrique (empreinte digitale), le service natif Android AutoFill et le clavier sécurisé Magikeyboard.
   - Fonctionne selon le principe de fichier local via le Storage Access Framework (SAF).

2. **[Round-sync](https://github.com/newh酥/round-sync)** *(Portage Android de Rclone)* ou **FolderSync** :
   - Permet de synchroniser un bucket Google Cloud Storage vers le stockage interne du téléphone à l'aide d'une clé Service Account JSON.

---

## 2. Transfert sécurisé de la clé Service Account

Le script `./scripts/setup-gcp.sh` a généré la clé :
`~/.config/keepass-sync/gcp-service-account.json`.

Pour l'importer sur votre smartphone :
```bash
# Exemple via ADB (câble USB) :
adb push ~/.config/keepass-sync/gcp-service-account.json /sdcard/Download/

# Ou via KDE Connect / transfert local sécurisé.
```

---

## 3. Configuration de la synchronisation avec Round-sync

1. Ouvrez **Round-sync**.
2. Créez un nouveau point d'accès distant (**Remote**) :
   - **Nom** : `gcs-keepass`
   - **Type de stockage** : `Google Cloud Storage`
   - **Service Account Credentials JSON** : appuyez sur le bouton pour sélectionner le fichier `gcp-service-account.json` importé.
   - Enregistrez le remote.
3. Supprimez le fichier JSON du dossier `Download` de votre smartphone une fois le profil créé :
   ```bash
   adb shell rm /sdcard/Download/gcp-service-account.json
   ```
4. Créez une **Tâche de Synchronisation** :
   - **Remote source** : `gcs-keepass:nom-de-votre-bucket/passwords.kdbx`
   - **Emplacement local cible** : `/sdcard/Documents/KeePass/passwords.kdbx`
   - **Direction** : Bi-directionnel (ou Sync planifiée)
   - **Planification** : ex. toutes les 15 minutes, ou déclenchée à la connexion Wi-Fi.
5. Lancez une première synchronisation pour télécharger la base.

---

## 4. Configuration de KeePassDX

1. Ouvrez **KeePassDX**.
2. Appuyez sur **Ouvrir une base de données existante**.
3. Naviguez dans le sélecteur de fichiers Android (SAF) et sélectionnez :
   `Documents > KeePass > passwords.kdbx`.
4. Déverrouillez avec votre mot de passe maître.
5. Activez les fonctionnalités recommandées dans les paramètres de KeePassDX :
   - **Déverrouillage biométrique** : Paramètres -> Sécurité -> Déverrouillage par empreinte digitale.
   - **Service de remplissage automatique (AutoFill)** : Paramètres Android -> Système -> Langues et saisie -> Service de saisie automatique -> Choisir **KeePassDX**.
   - **Magikeyboard** : Permet de saisir vos identifiants même dans les applications bloquant l'API AutoFill standard.

Désormais, toute modification apportée sur votre téléphone est synchronisée vers le bucket GCS, et intégrée automatiquement sur votre laptop par fusion intelligente.
