# Architecture & Gestion des Conflits

Ce document détaille les mécanismes techniques mis en œuvre pour garantir l'absence totale de perte de données et la haute disponibilité de votre base de données KeePass multi-appareils.

---

## 1. Philosophie Local-First vs Montage FUSE

Pourquoi déconseillons-nous formellement un montage direct type `gcsfuse` ou `rclone mount` ?

1. **Tolérance aux pannes réseau** :
   Un montage FUSE sur un bucket d'objets distant bloque les appels système de lecture/écriture dès qu'une déconnexion survient (train, avion, hotspot instable). KeePassXC peut alors figer ou lever des erreurs d'I/O critiques lors de l'enregistrement.
2. **Sémantique POSIX & Verrouillage** :
   Les buckets d'objets (GCS, S3) ne sont pas des systèmes de fichiers POSIX. Les mécanismes de verrouillage (`flock`) et les remplacements atomiques de fichiers (`rename`) y sont imparfaits ou simulés, entraînant des risques de corruption de base KDBX.
3. **Principe Local-First** :
   Chaque client dispose d'une copie locale sur son stockage rapide NVMe/Flash. L'accès aux mots de passe est instantané et 100% garanti, même sans aucune connexion Internet.

---

## 2. Résolution des Conflits : Fusion Intelligente au Niveau Entrée

La plupart des outils de synchronisation génériques (Dropbox, Nextcloud, Rclone direct) synchronisent les fichiers en bloc : si deux appareils modifient le fichier en parallèle, l'un des deux est écrasé ou renommé en `.conflict`.

### Le mécanisme KeePass 3-voies (`keepassxc-cli merge`)

Lorsque le script `keepass-sync.sh` détecte que la base distante sur GCS diffère de la base locale :

1. La base distante est téléchargée en RAM (`/run/user/$UID/keepass-sync-$$/remote.kdbx`).
2. Une copie locale de sauvegarde est créée : `~/.cache/keepass-sync/backup_before_merge.kdbx`.
3. Le script appelle `keepassxc-cli merge -s -q <local.kdbx> <remote.kdbx>` :
   - KeePassXC déchiffre les deux bases à l'aide du mot de passe maître stocké dans Secret Service.
   - Chaque entrée est comparée via son UUID et son horodatage `LastModified`.
   - Si une nouvelle entrée a été créée sur le smartphone (distant), elle est injectée dans la base locale.
   - Si une entrée a été modifiée sur les deux appareils, les modifications les plus récentes sont conservées, et les anciennes versions sont préservées dans l'historique interne de l'entrée.
   - Les suppressions sont déplacées dans la corbeille (*Recycle Bin*) sans perte accidentelle.
4. Si la base résultante contient de nouveaux éléments, elle est renvoyée sur GCS.

---

## 3. Filet de Sécurité : Versioning d'Objets sur GCS

Le script d'initialisation GCP active explicitement le **Versioning d'objets** (`gcloud storage buckets update gs://... --versioning`).

Même dans le pire scénario (ex: corruption locale, mauvaise manipulation ou suppression involontaire) :
- Chaque écriture sur GCS crée une nouvelle génération de l'objet sans jamais supprimer la précédente.
- Pour inspecter l'historique complet des versions sur GCS :
  ```bash
  gcloud storage objects list --versions gs://nom-de-votre-bucket/
  ```
- Pour restaurer une génération antérieure :
  ```bash
  gcloud storage cp gs://nom-de-votre-bucket/passwords.kdbx#GENERATION_ID ~/.local/share/keepass/passwords.kdbx
  ```

---

## 4. Surveillance & Journalisation

Les événements de synchronisation sont automatiquement journalisés par systemd :

```bash
# Vérifier l'état du timer et du path unit
systemctl --user status keepass-sync.timer
systemctl --user status keepass-sync.path

# Suivre les journaux d'exécution en direct
journalctl --user -u keepass-sync.service -e -f
```

Des notifications graphiques discrètes (`notify-send`) sont émises uniquement lors de l'intégration effective de nouvelles entrées ou en cas d'erreur de fusion/réseau.
