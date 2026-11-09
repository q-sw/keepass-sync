#!/usr/bin/env bash
# ==============================================================================
# setup-gcp.sh
# Provisionnement de l'infrastructure Google Cloud Storage pour KeePass :
# 1. Création du bucket GCS avec Object Versioning activé.
# 2. Création du Service Account dédié avec moindres privilèges (objectAdmin).
# 3. Export de la clé privée JSON du Service Account.
# ==============================================================================

set -euo pipefail

if ! command -v gcloud >/dev/null 2>&1; then
    echo "❌ Erreur : 'gcloud' (Google Cloud SDK) est introuvable."
    echo "Lancez 'nix develop' pour charger l'environnement pré-requis."
    exit 1
fi

echo "☁️ Provisionnement de l'infrastructure GCP pour KeePass"
echo "------------------------------------------------------"

# Récupération ou saisie du projet GCP
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
    echo "ℹ️ Le bucket gs://${BUCKET_NAME} existe déjà."
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
echo "5. Export de la clé de compte de service JSON..."
gcloud iam service-accounts keys create "$KEY_FILE" \
    --iam-account="$SA_EMAIL"
chmod 600 "$KEY_FILE"
echo "✅ Clé exportée vers : $KEY_FILE"

echo ""
echo "🎉 Infrastructure GCP provisionnée avec succès !"
echo ""
echo "Prochaines étapes :"
echo "1. Exécutez './scripts/setup-config.sh' pour configurer vos chemins locaux et Rclone."
echo "2. Copiez '$KEY_FILE' sur votre smartphone Android pour Round-sync / FolderSync."
