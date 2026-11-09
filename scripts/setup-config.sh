#!/usr/bin/env bash
# ==============================================================================
# setup-config.sh
# Configuration de l'environnement client local pour KeePass Sync :
# 1. Sélection des chemins de la base locale (.kdbx) et de l'objet GCS.
# 2. Génération du fichier de configuration ~/.config/keepass-sync/config.env.
# 3. Enregistrement du remote GCS dans Rclone.
# ==============================================================================

set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/keepass-sync"
CONFIG_FILE="${CONFIG_DIR}/config.env"
KEY_FILE="${CONFIG_DIR}/gcp-service-account.json"

mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"

echo "⚙️ Configuration du client local KeePass Sync"
echo "---------------------------------------------"

# Chemin de la base locale
DEFAULT_LOCAL_PATH="${KEEPASS_LOCAL_PATH:-$HOME/.local/share/keepass/passwords.kdbx}"
read -r -p "Chemin local de votre base (.kdbx) [${DEFAULT_LOCAL_PATH}]: " USER_LOCAL_PATH
USER_LOCAL_PATH="${USER_LOCAL_PATH:-$DEFAULT_LOCAL_PATH}"
USER_LOCAL_PATH="${USER_LOCAL_PATH/#\~/$HOME}"

# Nom du bucket GCS
DEFAULT_BUCKET=""
if [[ -f "$CONFIG_FILE" ]]; then
    DEFAULT_BUCKET=$(grep '^KEEPASS_GCS_BUCKET=' "$CONFIG_FILE" | cut -d'=' -f2 | tr -d '"' || true)
fi
read -r -p "Nom du bucket GCS cible [${DEFAULT_BUCKET}]: " USER_BUCKET
USER_BUCKET="${USER_BUCKET:-$DEFAULT_BUCKET}"

if [[ -z "$USER_BUCKET" ]]; then
    echo "❌ Le nom du bucket GCS est obligatoire."
    echo "Si vous ne l'avez pas encore créé, exécutez d'abord './scripts/setup-gcp.sh'."
    exit 1
fi

# Nom de l'objet distant sur GCS
DEFAULT_OBJECT_NAME="passwords.kdbx"
read -r -p "Nom du fichier stocké sur GCS [${DEFAULT_OBJECT_NAME}]: " USER_OBJECT_NAME
USER_OBJECT_NAME="${USER_OBJECT_NAME:-$DEFAULT_OBJECT_NAME}"

# Emplacement de la clé de compte de service GCP
read -r -p "Chemin de la clé Service Account JSON [${KEY_FILE}]: " USER_KEY_FILE
USER_KEY_FILE="${USER_KEY_FILE:-$KEY_FILE}"
USER_KEY_FILE="${USER_KEY_FILE/#\~/$HOME}"

if [[ ! -f "$USER_KEY_FILE" ]]; then
    echo "⚠️ Avertissement : Le fichier de clé '$USER_KEY_FILE' est introuvable."
    echo "Pensez à exécuter './scripts/setup-gcp.sh' ou à y déposer votre clé JSON."
fi

# 1. Écriture du fichier de configuration
cat <<EOF > "$CONFIG_FILE"
# Configuration KeePass Sync
KEEPASS_LOCAL_PATH="${USER_LOCAL_PATH}"
KEEPASS_RCLONE_REMOTE="gcs-keepass"
KEEPASS_GCS_BUCKET="${USER_BUCKET}"
KEEPASS_GCS_OBJECT="${USER_OBJECT_NAME}"
KEEPASS_KEYRING_SERVICE="keepass-sync"
KEEPASS_KEYRING_USER="master"
KEEPASS_NOTIFY_ENABLED="1"
EOF
chmod 600 "$CONFIG_FILE"
echo ""
echo "✅ Configuration enregistrée dans : $CONFIG_FILE"

# 2. Configuration Rclone
if command -v rclone >/dev/null 2>&1 && [[ -f "$USER_KEY_FILE" ]]; then
    echo ""
    echo "Configuration du profil Rclone 'gcs-keepass'..."
    rclone config create gcs-keepass gcs \
        service_account_file "$USER_KEY_FILE" \
        bucket_policy_only true
    echo "✅ Remote Rclone 'gcs-keepass' configuré avec succès."
else
    echo ""
    echo "ℹ️ Rclone non configuré immédiatement (rclone absent du PATH ou clé JSON absente)."
    echo "Il sera configuré dès disponibilité de la clé via le devShell 'nix develop'."
fi

echo ""
echo "🎉 Configuration client terminée !"
echo "Vous pouvez maintenant enregistrer votre mot de passe maître dans le trousseau :"
echo "  ./scripts/setup-keyring.sh"
