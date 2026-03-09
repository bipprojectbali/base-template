#!/bin/bash

# Sync environment secrets ke semua repo milik user/org.
# Membuat environment "portainer" jika belum ada, lalu set/update semua secrets.
#
# Usage: bash sync-secrets.sh <owner> <env-file>
# Example: bash sync-secrets.sh bipprojectbali .env.example.deploy

set -e

OWNER="${1:?Usage: bash sync-secrets.sh <owner> <env-file>}"
ENV_FILE="${2:-.env.example.deploy}"
ENV_NAME="portainer"

if [ ! -f "$ENV_FILE" ]; then
  echo "❌ File $ENV_FILE tidak ditemukan!"
  exit 1
fi

# Baca keys dan values dari env file ke arrays
KEYS=()
VALUES=()
while IFS='=' read -r key value || [ -n "$key" ]; do
  [[ -z "$key" || "$key" =~ ^# ]] && continue
  KEYS+=("$key")
  VALUES+=("$value")
done < "$ENV_FILE"

echo "📋 Secrets yang akan di-sync:"
for key in "${KEYS[@]}"; do
  echo "   → $key"
done
echo ""

# Ambil semua repo milik owner
echo "🔍 Mengambil daftar repo untuk $OWNER..."
REPOS=$(gh repo list "$OWNER" --limit 100 --json nameWithOwner -q '.[].nameWithOwner')

if [ -z "$REPOS" ]; then
  echo "❌ Tidak ada repo ditemukan untuk $OWNER"
  exit 1
fi

REPO_COUNT=$(echo "$REPOS" | wc -l | tr -d ' ')
echo "📦 Ditemukan $REPO_COUNT repo"
echo ""

for REPO in $REPOS; do
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📂 $REPO"

  # Cek apakah environment sudah ada
  ENV_EXISTS=$(gh api "repos/${REPO}/environments" --jq ".environments[]?.name // empty" 2>/dev/null | grep -c "^${ENV_NAME}$" || true)

  if [ "$ENV_EXISTS" -eq 0 ]; then
    echo "   🆕 Membuat environment '$ENV_NAME'..."
    gh api --method PUT "repos/${REPO}/environments/${ENV_NAME}" --silent 2>/dev/null || {
      echo "   ⚠️  Gagal membuat environment (mungkin tidak punya akses), skip."
      echo ""
      continue
    }
  else
    echo "   ✅ Environment '$ENV_NAME' sudah ada"
  fi

  for i in "${!KEYS[@]}"; do
    echo "   → Set ${KEYS[$i]}"
    gh secret set "${KEYS[$i]}" --repo "$REPO" --env "$ENV_NAME" --body "${VALUES[$i]}" 2>/dev/null || {
      echo "   ⚠️  Gagal set ${KEYS[$i]}"
    }
  done

  echo "   ✅ Done"
  echo ""
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 Sync selesai untuk $REPO_COUNT repo!"
