#!/usr/bin/env bash
# ============================================================
# scripts/init_dev.sh
# Initializes the developer environment:
#   1. Detects or creates GPG keys in .docker-gnupg/
#   2. Prompts for GPG_KEY_ID if keys already exist
#   3. Captures UID/GID from the current host user
#   4. Writes/updates the .env file
# ============================================================
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GNUPG_DIR="${PROJECT_ROOT}/.docker-gnupg"
ENV_FILE="${PROJECT_ROOT}/.env"
ENV_EXAMPLE="${PROJECT_ROOT}/.env.example"

echo "🚀 ModestInventary — Developer Environment Initializer"
echo "--------------------------------------------------------"

# ---- Step 1: .env file ----
if [ ! -f "${ENV_FILE}" ]; then
  echo "  📄 Creating .env from .env.example..."
  cp "${ENV_EXAMPLE}" "${ENV_FILE}"
fi

# ---- Step 2: Capture UID/GID ----
HOST_UID=$(id -u)
HOST_GID=$(id -g)
echo "  👤 Host UID=${HOST_UID} GID=${HOST_GID}"
sed -i "s/^UID=.*/UID=${HOST_UID}/" "${ENV_FILE}"
sed -i "s/^GID=.*/GID=${HOST_GID}/" "${ENV_FILE}"

# ---- Step 3: GPG Setup ----
mkdir -p "${GNUPG_DIR}"
chmod 700 "${GNUPG_DIR}"
export GNUPGHOME="${GNUPG_DIR}"

EXISTING_KEYS=$(gpg --list-secret-keys --keyid-format LONG 2>/dev/null | grep "^sec" || true)

if [ -n "${EXISTING_KEYS}" ]; then
  echo ""
  echo "  🔑 Existing GPG keys found:"
  gpg --list-secret-keys --keyid-format LONG
  echo ""
  read -rp "  Enter the KEY_ID to use for signing (e.g. ABCDEF1234567890): " KEY_ID
else
  echo ""
  echo "  🔑 No GPG keys found. Generating a new key pair..."
  echo "     (A passphrase-less key will be created for automation)"
  echo ""
  cat > /tmp/gpg_gen_params <<GPGEOF
%no-protection
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: ModestInventary Dev
Name-Email: dev@modestinventary.local
Expire-Date: 1y
%commit
GPGEOF
  gpg --batch --gen-key /tmp/gpg_gen_params
  rm /tmp/gpg_gen_params
  KEY_ID=$(gpg --list-secret-keys --keyid-format LONG 2>/dev/null \
    | grep "^sec" | head -1 | awk '{print $2}' | cut -d'/' -f2)
  echo "  ✅ Key generated: ${KEY_ID}"
fi

# ---- Step 4: Update .env with key info ----
sed -i "s|^GPG_HOME=.*|GPG_HOME=${GNUPG_DIR}|" "${ENV_FILE}"
sed -i "s/^GPG_KEY_ID=.*/GPG_KEY_ID=${KEY_ID}/" "${ENV_FILE}"

echo ""
echo "✅ Environment configured successfully!"
echo "   .env has been updated."
echo "   GPG Key ID: ${KEY_ID}"
echo ""
echo "  Next steps:"
echo "    1. Run: docker compose --profile development up"
echo "    2. Install hooks: bash scripts/install_hooks.sh"
