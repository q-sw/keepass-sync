#!/usr/bin/env bash
# ==============================================================================
# setup-keyring.sh
# Enregistre de manière sécurisée le mot de passe maître KeePass dans le trousseau
# de session Linux (Secret Service API / GNOME Keyring / KWallet).
# ==============================================================================

set -euo pipefail

KEYRING_SERVICE="${KEEPASS_KEYRING_SERVICE:-keepass-sync}"
KEYRING_USER="${KEEPASS_KEYRING_USER:-master}"

if ! command -v secret-tool >/dev/null 2>&1; then
    echo "❌ Erreur : 'secret-tool' (paquet libsecret) n'est pas installé ou n'est pas dans le PATH."
    echo "Veuillez charger le devShell via 'nix develop' ou installer libsecret."
    exit 1
fi

echo "🔐 Configuration du mot de passe maître KeePass dans le trousseau Secret Service"
echo "Service : $KEYRING_SERVICE"
echo "Utilisateur : $KEYRING_USER"
echo ""
echo "Veuillez saisir votre mot de passe maître KeePass (saisie masquée) :"
read -r -s PASSWORD
echo ""

if [[ -z "$PASSWORD" ]]; then
    echo "❌ Mot de passe vide. Annulation."
    exit 1
fi

echo -n "$PASSWORD" | secret-tool store --label="KeePass Master Password ($KEYRING_SERVICE)" service "$KEYRING_SERVICE" user "$KEYRING_USER"

# Vérification immédiate
STORED=$(secret-tool lookup service "$KEYRING_SERVICE" user "$KEYRING_USER" 2>/dev/null || true)
if [[ "$STORED" == "$PASSWORD" ]]; then
    echo "✅ Mot de passe enregistré avec succès dans le trousseau de session."
    echo "Le script de synchronisation d'arrière-plan pourra désormais déchiffrer et fusionner sans saisie interactive."
else
    echo "❌ Échec de la vérification du mot de passe stocké."
    exit 1
fi
