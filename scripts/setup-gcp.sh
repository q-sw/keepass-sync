#!/usr/bin/env bash
# ==============================================================================
# setup-gcp.sh
# Création du bucket GCS avec versioning et du compte de service (Service Account)
# avec privilèges minimaux (roles/storage.objectAdmin) pour KeePass.
# ==============================================================================

set -euo pipefail

if ! command -v gcloud >/dev/null 2>&1; then
    echo "❌ Erreur : 'gcloud' (Google Cloud SDK) est introuvable."
    echo "Lancez 'nix develop' pour charger l'environnement pré-requis."
    exit 1
fi

echo "☁️ Configuration GCP pour KeePass Sync"
echo "---------------------------------------"

# Récupération ou demande du projet GCP
CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null || true)
read -r -p "Identifiant du projet GCP [${CURRENT_PROJECT:-mon-projet-gcp}]: " GCP_PROJECT
GCP_PROJECT="${GCP_PROJECT:-$CURRENT_PROJECT}"

if [[ -z "$GCP_PROJECT" ]]; then
    echo "❌ Projet GCP obligatoire."
    exit 1
fi

gcloud config set project "$GCP_PROJECT"

DEFAULT_BUCKET="${GCP_PROJECT}-keepass-vault"
read -r -p "Nom du bucket GCS à créer [${DEFAULT_BUCKET}]: " BUCKET_NAME
BUCKET_NAME="${BUCKET_NAME:-$DEFAULT_BUCKET}"

DEFAULT_REGION="europe-west9" # Paris
read -r -p "Région de stockage GCS [${DEFAULT_REGION}]: " REGION
REGION="${REGION:-$DEFAULT_REGION}"

SA_NAME="keepass-sync-sa"
SA_EMAIL="${SA_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com"
KEY_OUTPUT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/keepass-sync"
KEY_FILE="${KEY_OUTPUT_DIR}/gcp-service-account.json"

mkdir -p "$KEY_OUTPUT_DIR"
chmod 700 "$KEY_OUTPUT_DIR"

echo ""
echo "1. Création du bucket gs://${BUCKET_NAME}..."
if gcloud storage buckets describe "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
    echo "ℹ️ Le bucket existe déjà."
else
    gcloud storage buckets create "gs://${BUCKET_NAME}" \
        --location="$REGION" \
        --uniform-bucket-level-access
    echo "✅ Bucket créé."
fi

echo ""
echo "2. Activation du versioning d'objets (protection contre la perte de données)..."
gcloud storage buckets update "gs://${BUCKET_NAME}" --versioning
echo "✅ Versioning activé sur gs://${BUCKET_NAME}."

echo ""
echo "3. Création du compte de service '${SA_NAME}'..."
if gcloud iam service-accounts describe "$SA_EMAIL" >/dev/null 2>&1; then
    echo "ℹ️ Le compte de service existe déjà."
else
    gcloud iam service-accounts create "$SA_NAME" \
        --display-name="KeePass Sync Service Account"
    echo "✅ Compte de service créé."
fi

echo ""
echo "4. Attribution des permissions restreintes (roles/storage.objectAdmin sur le bucket uniquement)..."
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/storage.objectAdmin"
echo "✅ Rôle appliqué."

echo ""
echo "5. Génération de la clé de compte de service JSON..."
gcloud iam service-accounts keys create "$KEY_FILE" \
    --iam-account="$SA_EMAIL"
chmod 600 "$KEY_FILE"
echo "✅ Clé exportée vers : $KEY_FILE"

echo ""
echo "6. Génération de la configuration locale (~/.config/keepass-sync/config.env)..."
CONFIG_ENV_FILE="${KEY_OUTPUT_DIR}/config.env"
cat <<EOF > "$CONFIG_ENV_FILE"
# Configuration KeePass Sync
KEEPASS_LOCAL_PATH="\$HOME/.local/share/keepass/passwords.kdbx"
KEEPASS_RCLONE_REMOTE="gcs-keepass"
KEEPASS_GCS_BUCKET="${BUCKET_NAME}"
KEEPASS_GCS_OBJECT="passwords.kdbx"
KEEPASS_KEYRING_SERVICE="keepass-sync"
KEEPASS_KEYRING_USER="master"
KEEPASS_NOTIFY_ENABLED="1"
EOF
chmod 600 "$CONFIG_ENV_FILE"
echo "✅ Fichier de configuration écrit dans : $CONFIG_ENV_FILE"

echo ""
echo "7. Configuration de Rclone..."
echo "Ajout automatique du remote 'gcs-keepass' dans ~/.config/rclone/rclone.conf :"
rclone config create gcs-keepass google cloud storage \
    service_account_file "$KEY_FILE" \
    bucket_policy_only true \
    location "$REGION"

echo ""
echo "🎉 Configuration GCP terminée avec succès !"
echo "Pour transférer cette clé sur votre smartphone Android (pour Round-sync / FolderSync) :"
echo "Fichier à copier sur le téléphone : $KEY_FILE"
