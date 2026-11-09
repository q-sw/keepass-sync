# Procédure de Migration : Bitwarden vers KeePassXC

Ce document détaille la démarche pour exporter votre coffre-fort Bitwarden et l'importer dans KeePassXC tout en préservant l'intégrité de vos identifiants, notes sécurisées, champs personnalisés et graines TOTP/2FA.

---

## 1. Exportation depuis Bitwarden

1. Connectez-vous à votre coffre Bitwarden via l'application de bureau ou l'interface web ([vault.bitwarden.com](https://vault.bitwarden.com)).
2. Rendez-vous dans **Paramètres** -> **Exporter le coffre**.
3. Sélectionnez les options :
   - **Format de fichier** : `JSON (non chiffré)` *(Important : le format CSV perd les graines TOTP et les champs personnalisés ; le format JSON les conserve intégralement)*.
   - Saisissez votre mot de passe maître Bitwarden pour valider l'export.
4. **Précautions de sécurité** :
   Enregistrez le fichier directement sur un système de fichiers en mémoire vive (`tmpfs`) pour éviter toute écriture rémanente sur SSD/NVMe :
   ```bash
   # Emplacement temporaire sécurisé en RAM
   DEST_JSON="/run/user/$(id -u)/bitwarden_export.json"
   ```

---

## 2. Importation dans KeePassXC

1. Ouvrez KeePassXC :
   ```bash
   keepassxc &
   ```
2. Dans la barre de menu, cliquez sur :
   **Base de données** -> **Importer** -> **Bitwarden (JSON)**.
3. Sélectionnez le fichier `/run/user/<UID>/bitwarden_export.json`.
4. Définissez votre **mot de passe maître KeePass** :
   - Choisissez une phrase de passe à haute entropie (4 à 6 mots aléatoires ou 20+ caractères).
   - *(Optionnel)* Vous pouvez ajuster les paramètres de chiffrement (KDF : Argon2d/Argon2id recommandé).
5. Enregistrez la base de données créée dans le chemin standard :
   ```bash
   mkdir -p ~/.local/share/keepass
   # Enregistrez le fichier sous :
   ~/.local/share/keepass/passwords.kdbx
   ```
   Réglez les permissions strictes :
   ```bash
   chmod 600 ~/.local/share/keepass/passwords.kdbx
   ```

---

## 3. Contrôle & Validation

1. **Arborescence & Entrées** :
   Vérifiez que vos dossiers, identifiants, URLs et notes sont bien organisés.
2. **Codes TOTP / 2FA** :
   Faites un clic droit sur une entrée contenant une double authentification -> **TOTP** -> **Afficher le TOTP** (ou raccourci `Ctrl+T`). Vérifiez que le code à 6 chiffres concorde avec l'application Bitwarden ou votre authentificateur habituel.
3. **Champs personnalisés** :
   Vérifiez les entrées spécifiques (ex: questions secrètes, clés d'API) dans l'onglet *Attributs avancés*.

---

## 4. Nettoyage sécurisé du fichier d'export

Le fichier d'export JSON contenant l'intégralité de vos secrets en clair doit être détruit immédiatement par écrasement cryptographique :

```bash
shred -u -z -n 3 "/run/user/$(id -u)/bitwarden_export.json"
```

Votre base KeePassXC locale est prête à être synchronisée avec GCS.
