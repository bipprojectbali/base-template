#!/bin/bash

# Usage: bash set-secrets.sh <owner/repo>
# Example: bash set-secrets.sh bipprojectbali/base-template
#
# Reads secrets from .env.example.deploy and sets them as GitHub repo secrets.

: "${1:?Usage: bash set-secrets.sh <owner/repo>}"

REPO="$1"
ENV_FILE=".env.example.deploy"

if [ ! -f "$ENV_FILE" ]; then
  echo "❌ File $ENV_FILE tidak ditemukan!"
  exit 1
fi

echo "🔐 Setting secrets for $REPO..."

while IFS='=' read -r key value; do
  # skip empty lines and comments
  [[ -z "$key" || "$key" =~ ^# ]] && continue

  echo "   → $key"
  gh secret set "$key" --repo "$REPO" --body "$value"
done < "$ENV_FILE"

echo "✅ Semua secrets berhasil di-set untuk $REPO"
