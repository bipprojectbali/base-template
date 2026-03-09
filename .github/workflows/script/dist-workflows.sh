#!/bin/bash

# Distribute workflow files dari base-template ke semua repo.
# Hanya copy file yang diperlukan, tidak merusak code lain.
#
# Required env vars:
#   GH_TOKEN       - PAT dengan scope repo
#   TARGET_OWNER   - GitHub owner/org name
#   SOURCE_REPO    - Repo sumber (default: base-template)

set -e

: "${GH_TOKEN:?GH_TOKEN (PAT) tidak di-set}"
: "${TARGET_OWNER:?TARGET_OWNER tidak di-set}"
: "${SOURCE_REPO:=base-template}"

# Files yang akan di-distribute (tanpa sync-secrets)
DIST_FILES=(
  ".github/workflows/publish.yml"
  ".github/workflows/re-pull.yml"
  ".github/workflows/script/notify.sh"
  ".github/workflows/script/re-pull.sh"
)

echo "📋 Files yang akan di-distribute:"
for f in "${DIST_FILES[@]}"; do
  echo "   → $f"
done
echo ""

# Ambil semua repo
echo "🔍 Mengambil daftar repo untuk $TARGET_OWNER..."
REPOS=$(gh repo list "$TARGET_OWNER" --limit 100 --json nameWithOwner,defaultBranchRef -q '.[] | "\(.nameWithOwner) \(.defaultBranchRef.name)"')

if [ -z "$REPOS" ]; then
  echo "❌ Tidak ada repo ditemukan untuk $TARGET_OWNER"
  exit 1
fi

REPO_COUNT=$(echo "$REPOS" | wc -l | tr -d ' ')
echo "📦 Ditemukan $REPO_COUNT repo"
echo ""

WORK_DIR=$(mktemp -d)
SUCCESS=0
SKIPPED=0
FAILED=0

while read -r REPO DEFAULT_BRANCH; do
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📂 $REPO (branch: $DEFAULT_BRANCH)"

  # Skip source repo
  if [ "$REPO" = "${TARGET_OWNER}/${SOURCE_REPO}" ]; then
    echo "   ⏭️  Skip (source repo)"
    SKIPPED=$((SKIPPED + 1))
    echo ""
    continue
  fi

  REPO_DIR="${WORK_DIR}/${REPO##*/}"

  # Clone repo (shallow, hanya default branch)
  echo "   📥 Cloning..."
  git clone --depth 1 --branch "$DEFAULT_BRANCH" "https://x-access-token:${GH_TOKEN}@github.com/${REPO}.git" "$REPO_DIR" 2>/dev/null || {
    echo "   ⚠️  Gagal clone, skip."
    FAILED=$((FAILED + 1))
    echo ""
    continue
  }

  # Copy files
  CHANGED=false
  for f in "${DIST_FILES[@]}"; do
    SRC_FILE="$f"
    DEST_FILE="${REPO_DIR}/${f}"
    DEST_DIR=$(dirname "$DEST_FILE")

    if [ ! -f "$SRC_FILE" ]; then
      echo "   ⚠️  Source tidak ditemukan: $SRC_FILE"
      continue
    fi

    mkdir -p "$DEST_DIR"

    # Cek apakah file berbeda
    if [ -f "$DEST_FILE" ] && diff -q "$SRC_FILE" "$DEST_FILE" >/dev/null 2>&1; then
      continue
    fi

    cp "$SRC_FILE" "$DEST_FILE"
    CHANGED=true
  done

  if [ "$CHANGED" = false ]; then
    echo "   ✅ Sudah up to date"
    SKIPPED=$((SKIPPED + 1))
    rm -rf "$REPO_DIR"
    echo ""
    continue
  fi

  # Commit dan push
  cd "$REPO_DIR"
  git add .github/workflows/ 2>/dev/null

  if git diff --cached --quiet; then
    echo "   ✅ Sudah up to date"
    SKIPPED=$((SKIPPED + 1))
  else
    git config user.name "github-actions[bot]"
    git config user.email "github-actions[bot]@users.noreply.github.com"
    git commit -m "chore: sync workflows from ${SOURCE_REPO}" >/dev/null 2>&1

    echo "   📤 Pushing..."
    git push origin "$DEFAULT_BRANCH" 2>/dev/null || {
      echo "   ⚠️  Gagal push, skip."
      FAILED=$((FAILED + 1))
      cd - >/dev/null
      rm -rf "$REPO_DIR"
      echo ""
      continue
    }

    echo "   ✅ Done"
    SUCCESS=$((SUCCESS + 1))
  fi

  cd - >/dev/null
  rm -rf "$REPO_DIR"
  echo ""
done <<< "$REPOS"

# Cleanup
rm -rf "$WORK_DIR"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 Distribute selesai! Updated: $SUCCESS | Skipped: $SKIPPED | Failed: $FAILED | Total: $REPO_COUNT"
