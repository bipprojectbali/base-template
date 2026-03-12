#!/bin/bash
set -e
source .env.telegram
set +e

curl -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
  -H "Content-Type: application/json" \
  -d "{
    \"chat_id\": \"${TELEGRAM_CHAT_ID}\",
    \"text\": \"Halo dari bot!\"
  }"