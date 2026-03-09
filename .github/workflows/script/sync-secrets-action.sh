#!/bin/bash

# Sync environment secrets dari env vars (SECRET_*) ke semua repo milik owner.
# Dijalankan oleh GitHub Actions workflow sync-secrets.yml
#
# Required env vars:
#   GH_TOKEN       - PAT dengan scope 'repo' untuk akses ke repo lain
#   TARGET_OWNER   - GitHub owner/org name
#   ENV_NAME       - Nama environment (default: portainer)
#   SECRET_*       - Semua env var dengan prefix SECRET_ akan di-sync

set -e

: "${GH_TOKEN:?GH_TOKEN (PAT) tidak di-set}"
: "${TARGET_OWNER:?TARGET_OWNER tidak di-set}"
: "${ENV_NAME:=portainer}"

# Collect semua SECRET_* env vars
KEYS=()
VALUES=()
while IFS='=' read -r full_key value; do
  key="${full_key#SECRET_}"
  KEYS+=("$key")
  VALUES+=("$value")
done < <(env | grep "^SECRET_" | sort)

if [ ${#KEYS[@]} -eq 0 ]; then
  echo "❌ Tidak ada secrets ditemukan (env var SECRET_*)"
  exit 1
fi

echo "📋 Secrets yang akan di-sync:"
for key in "${KEYS[@]}"; do
  echo "   → $key"
done
echo ""

# Ambil semua repo
echo "🔍 Mengambil daftar repo untuk $TARGET_OWNER..."
REPOS=$(gh repo list "$TARGET_OWNER" --limit 100 --json nameWithOwner -q '.[].nameWithOwner')

if [ -z "$REPOS" ]; then
  echo "❌ Tidak ada repo ditemukan untuk $TARGET_OWNER"
  exit 1
fi

REPO_COUNT=$(echo "$REPOS" | wc -l | tr -d ' ')
echo "📦 Ditemukan $REPO_COUNT repo"
echo ""

SUCCESS=0
FAILED=0

for REPO in $REPOS; do
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📂 $REPO"

  # Cek/buat environment
  ENV_EXISTS=$(gh api "repos/${REPO}/environments" --jq ".environments[]?.name // empty" 2>/dev/null | grep -c "^${ENV_NAME}$" || true)

  if [ "$ENV_EXISTS" -eq 0 ]; then
    echo "   🆕 Membuat environment '$ENV_NAME'..."
    gh api --method PUT "repos/${REPO}/environments/${ENV_NAME}" --silent 2>/dev/null || {
      echo "   ⚠️  Gagal membuat environment, skip."
      FAILED=$((FAILED + 1))
      echo ""
      continue
    }
  else
    echo "   ✅ Environment '$ENV_NAME' sudah ada"
  fi

  # Set secrets
  REPO_OK=true
  for i in "${!KEYS[@]}"; do
    echo "   → Set ${KEYS[$i]}"
    gh secret set "${KEYS[$i]}" --repo "$REPO" --env "$ENV_NAME" --body "${VALUES[$i]}" 2>/dev/null || {
      echo "   ⚠️  Gagal set ${KEYS[$i]}"
      REPO_OK=false
    }
  done

  if [ "$REPO_OK" = true ]; then
    echo "   ✅ Done"
    SUCCESS=$((SUCCESS + 1))
  else
    FAILED=$((FAILED + 1))
  fi
  echo ""
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 Sync selesai! Sukses: $SUCCESS | Gagal: $FAILED | Total: $REPO_COUNT"
