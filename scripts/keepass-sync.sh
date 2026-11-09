#!/usr/bin/env bash
# ==============================================================================
# keepass-sync.sh
# Synchronisation bidirectionnelle intelligente pour KeePass (.kdbx)
# avec Google Cloud Storage (GCS) et fusion au niveau entrée via keepassxc-cli.
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# 1. Configuration & Valeurs par défaut
# ------------------------------------------------------------------------------
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/keepass-sync"
CONFIG_FILE="${CONFIG_DIR}/config.env"

if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

LOCAL_KDBX="${KEEPASS_LOCAL_PATH:-$HOME/.local/share/keepass/passwords.kdbx}"
RCLONE_REMOTE="${KEEPASS_RCLONE_REMOTE:-gcs-keepass}"
GCS_BUCKET="${KEEPASS_GCS_BUCKET:-}"
GCS_OBJECT="${KEEPASS_GCS_OBJECT:-passwords.kdbx}"
KEYRING_SERVICE="${KEEPASS_KEYRING_SERVICE:-keepass-sync}"
KEYRING_USER="${KEEPASS_KEYRING_USER:-master}"
NOTIFY_ENABLED="${KEEPASS_NOTIFY_ENABLED:-1}"

# Si le nom complet de la cible distante n'est pas spécifié, on le dérive
REMOTE_URI="${KEEPASS_REMOTE_URI:-${RCLONE_REMOTE}:${GCS_BUCKET}/${GCS_OBJECT}}"

# Répertoire d'exécution temporaire sécurisé en RAM (tmpfs)
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
LOCK_FILE="${RUNTIME_DIR}/keepass-sync.lock"
WORK_DIR="${RUNTIME_DIR}/keepass-sync-$$"
HASH_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/keepass-sync"
LAST_SYNC_HASH_FILE="${HASH_CACHE_DIR}/last_synced_sha256"

# ------------------------------------------------------------------------------
# 2. Fonctions utilitaires
# ------------------------------------------------------------------------------
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERREUR] $*" >&2
}

notify() {
    local urgency="$1"
    local title="$2"
    local message="$3"
    if [[ "$NOTIFY_ENABLED" == "1" ]] && command -v notify-send >/dev/null 2>&1; then
        notify-send -u "$urgency" -a "KeePass Sync" "$title" "$message" || true
    fi
}

cleanup() {
    local exit_code=$?
    if [[ -d "${WORK_DIR:-}" ]]; then
        # Écrasement mémoire avant suppression du répertoire temporaire
        find "$WORK_DIR" -type f -name "*.kdbx" -exec shred -u -n 1 {} + 2>/dev/null || true
        rm -rf "$WORK_DIR" 2>/dev/null || true
    fi
    exit "$exit_code"
}
trap cleanup EXIT INT TERM

# ------------------------------------------------------------------------------
# 3. Contrôle de verrouillage (Mutex)
# ------------------------------------------------------------------------------
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    log "Une autre instance de synchronisation est déjà en cours. Fin."
    exit 0
fi

# ------------------------------------------------------------------------------
# 4. Vérification de la connectivité réseau
# ------------------------------------------------------------------------------
is_online() {
    # Test de connectivité rapide vers Google Cloud Storage avec timeout
    timeout 3 bash -c 'cat < /dev/null > /dev/tcp/storage.googleapis.com/443' 2>/dev/null
}

if ! is_online; then
    log "Mode hors-ligne détecté. Synchronisation réseau ignorée."
    exit 0
fi

# ------------------------------------------------------------------------------
# 5. Validation des pré-requis
# ------------------------------------------------------------------------------
for cmd in rclone keepassxc-cli sha256sum; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "Commande requise absente du PATH : $cmd"
        notify "critical" "KeePass Sync - Dépendance manquante" "La commande '$cmd' est introuvable."
        exit 1
    fi
done

if [[ -z "$GCS_BUCKET" && -z "${KEEPASS_REMOTE_URI:-}" ]]; then
    log_error "KEEPASS_GCS_BUCKET ou KEEPASS_REMOTE_URI n'est pas défini dans $CONFIG_FILE"
    notify "critical" "KeePass Sync - Configuration manquante" "Veuillez définir KEEPASS_GCS_BUCKET dans $CONFIG_FILE"
    exit 1
fi

mkdir -p "$WORK_DIR" "$HASH_CACHE_DIR" "$(dirname "$LOCAL_KDBX")"
chmod 700 "$WORK_DIR" "$HASH_CACHE_DIR"

REMOTE_TMP="${WORK_DIR}/remote.kdbx"

# ------------------------------------------------------------------------------
# 6. Cas initial : La base locale n'existe pas encore
# ------------------------------------------------------------------------------
if [[ ! -f "$LOCAL_KDBX" ]]; then
    log "La base locale n'existe pas encore ($LOCAL_KDBX). Tentative de téléchargement depuis GCS..."
    if rclone copyto "$REMOTE_URI" "$LOCAL_KDBX" 2>/dev/null; then
        chmod 600 "$LOCAL_KDBX"
        sha256sum "$LOCAL_KDBX" | awk '{print $1}' > "$LAST_SYNC_HASH_FILE"
        log "Base locale initialisée avec succès depuis GCS."
        notify "normal" "KeePass Sync" "Base téléchargée avec succès depuis GCS."
        exit 0
    else
        log "Aucune base trouvée sur GCS ($REMOTE_URI). En attente de création locale."
        exit 0
    fi
fi

# ------------------------------------------------------------------------------
# 7. Téléchargement de la base distante pour comparaison
# ------------------------------------------------------------------------------
LOCAL_HASH=$(sha256sum "$LOCAL_KDBX" | awk '{print $1}')

log "Vérification de la base distante sur GCS ($REMOTE_URI)..."
REMOTE_EXISTS=1
if ! rclone copyto "$REMOTE_URI" "$REMOTE_TMP" 2>/dev/null; then
    REMOTE_EXISTS=0
    log "La base distante n'existe pas encore sur GCS. Première synchronisation requise."
fi

if [[ "$REMOTE_EXISTS" -eq 0 ]]; then
    log "Envoi initial de la base locale vers GCS..."
    if rclone copyto "$LOCAL_KDBX" "$REMOTE_URI"; then
        echo "$LOCAL_HASH" > "$LAST_SYNC_HASH_FILE"
        log "Upload initial réussi."
    else
        log_error "Échec de l'upload initial vers GCS."
        notify "critical" "KeePass Sync - Erreur" "Impossible d'uploader la base vers GCS."
        exit 1
    fi
    exit 0
fi

REMOTE_HASH=$(sha256sum "$REMOTE_TMP" | awk '{print $1}')

# Si la base distante et la base locale sont strictement identiques
if [[ "$LOCAL_HASH" == "$REMOTE_HASH" ]]; then
    echo "$LOCAL_HASH" > "$LAST_SYNC_HASH_FILE"
    log "Base locale et base distante synchronisées (aucun changement détecté)."
    exit 0
fi

# ------------------------------------------------------------------------------
# 8. Récupération du mot de passe maître depuis Secret Service
# ------------------------------------------------------------------------------
get_master_password() {
    if command -v secret-tool >/dev/null 2>&1; then
        secret-tool lookup service "$KEYRING_SERVICE" user "$KEYRING_USER" 2>/dev/null || true
    else
        echo ""
    fi
}

MASTER_PASSWORD=$(get_master_password)

if [[ -z "$MASTER_PASSWORD" ]]; then
    log_error "Impossible de récupérer le mot de passe maître depuis Secret Service (service: $KEYRING_SERVICE, user: $KEYRING_USER)."
    notify "critical" "KeePass Sync - Clé manquante" "Mot de passe maître introuvable dans le trousseau de clés (secret-tool)."
    exit 1
fi

# ------------------------------------------------------------------------------
# 9. Fusion bidirectionnelle intelligente (keepassxc-cli merge)
# ------------------------------------------------------------------------------
log "Différence détectée entre la base locale et distante. Démarrage de la fusion..."

# Sauvegarde locale préventive avant toute opération de fusion
BACKUP_KDBX="${HASH_CACHE_DIR}/backup_before_merge.kdbx"
cp -p "$LOCAL_KDBX" "$BACKUP_KDBX"

# Fusion de la base distante dans la base locale
MERGE_OUTPUT=""
if ! MERGE_OUTPUT=$(echo "$MASTER_PASSWORD" | keepassxc-cli merge -s -q "$LOCAL_KDBX" "$REMOTE_TMP" 2>&1); then
    log_error "Échec critique lors de la fusion KeePass : $MERGE_OUTPUT"
    # Restauration de la sauvegarde en cas de corruption
    cp -p "$BACKUP_KDBX" "$LOCAL_KDBX"
    notify "critical" "KeePass Sync - Erreur de fusion" "Échec de la fusion kdbx. Base locale restaurée."
    exit 1
fi

NEW_LOCAL_HASH=$(sha256sum "$LOCAL_KDBX" | awk '{print $1}')

# Vérifier si la base locale a intégré de nouvelles données issues du distant
MERGED_NEW_ENTRIES=0
if [[ "$NEW_LOCAL_HASH" != "$LOCAL_HASH" ]]; then
    MERGED_NEW_ENTRIES=1
    log "De nouvelles entrées distantes ont été fusionnées dans la base locale."
fi

# Si après la fusion la base locale diffère de la version distante sur GCS, on pousse la version fusionnée
if [[ "$NEW_LOCAL_HASH" != "$REMOTE_HASH" ]]; then
    log "Envoi de la base fusionnée vers GCS ($REMOTE_URI)..."
    if rclone copyto "$LOCAL_KDBX" "$REMOTE_URI"; then
        echo "$NEW_LOCAL_HASH" > "$LAST_SYNC_HASH_FILE"
        log "Synchronisation vers GCS terminée avec succès."
        
        if [[ "$MERGED_NEW_ENTRIES" -eq 1 ]]; then
            notify "normal" "KeePass Synchronisation" "Base mise à jour : modifications distantes intégrées et synchronisées."
        fi
    else
        log_error "Échec du renvoi de la base fusionnée vers GCS."
        notify "critical" "KeePass Sync - Erreur Upload" "Base locale fusionnée mais impossible de la pousser vers GCS."
        exit 1
    fi
else
    # Si la base distante contenait déjà toutes les modifications
    echo "$NEW_LOCAL_HASH" > "$LAST_SYNC_HASH_FILE"
    if [[ "$MERGED_NEW_ENTRIES" -eq 1 ]]; then
        notify "normal" "KeePass Synchronisation" "Modifications distantes intégrées dans la base locale."
    fi
    log "Synchronisation terminée (base locale alignée sur la base distante)."
fi

exit 0
