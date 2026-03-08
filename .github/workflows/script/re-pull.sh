#!/bin/bash

: "${PORTAINER_URL:?PORTAINER_URL tidak di-set}"
: "${PORTAINER_USERNAME:?PORTAINER_USERNAME tidak di-set}"
: "${PORTAINER_PASSWORD:?PORTAINER_PASSWORD tidak di-set}"
: "${STACK_NAME:?STACK_NAME tidak di-set}"

echo "🔐 Autentikasi ke Portainer..."
TOKEN=$(curl -s -X POST https://${PORTAINER_URL}/api/auth \
  -H "Content-Type: application/json" \
  -d "{\"username\": \"${PORTAINER_USERNAME}\", \"password\": \"${PORTAINER_PASSWORD}\"}" \
  | jq -r .jwt)

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "❌ Autentikasi gagal! Cek PORTAINER_URL, USERNAME, dan PASSWORD."
  exit 1
fi

echo "🔍 Mencari stack: $STACK_NAME..."
STACK=$(curl -s -X GET https://${PORTAINER_URL}/api/stacks \
  -H "Authorization: Bearer ${TOKEN}" \
  | jq ".[] | select(.Name == \"$STACK_NAME\")")

if [ -z "$STACK" ]; then
  echo "❌ Stack '$STACK_NAME' tidak ditemukan di Portainer!"
  echo "   Pastikan nama stack sudah benar."
  exit 1
fi

STACK_ID=$(echo "$STACK" | jq -r .Id)
ENDPOINT_ID=$(echo "$STACK" | jq -r .EndpointId)
ENV=$(echo "$STACK" | jq '.Env // []')

echo "📄 Mengambil compose file..."
STACK_FILE=$(curl -s -X GET "https://${PORTAINER_URL}/api/stacks/${STACK_ID}/file" \
  -H "Authorization: Bearer ${TOKEN}" \
  | jq -r .StackFileContent)

PAYLOAD=$(jq -n \
  --arg content "$STACK_FILE" \
  --argjson env "$ENV" \
  '{stackFileContent: $content, env: $env, pullImage: true}')

echo "🚀 Redeploying $STACK_NAME (pull latest image)..."
HTTP_STATUS=$(curl -s -o /tmp/portainer_response.json -w "%{http_code}" \
  -X PUT "https://${PORTAINER_URL}/api/stacks/${STACK_ID}?endpointId=${ENDPOINT_ID}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

if [ "$HTTP_STATUS" != "200" ]; then
  echo "❌ Redeploy gagal! HTTP Status: $HTTP_STATUS"
  cat /tmp/portainer_response.json | jq .
  exit 1
fi

echo "⏳ Menunggu container running..."

MAX_RETRY=15
COUNT=0

while [ $COUNT -lt $MAX_RETRY ]; do
  sleep 5
  COUNT=$((COUNT + 1))

  CONTAINERS=$(curl -s -X GET \
    "https://${PORTAINER_URL}/api/endpoints/${ENDPOINT_ID}/docker/containers/json?all=true&filters=%7B%22label%22%3A%5B%22com.docker.compose.project%3D${STACK_NAME}%22%5D%7D" \
    -H "Authorization: Bearer ${TOKEN}")

  TOTAL=$(echo "$CONTAINERS" | jq 'length')
  RUNNING=$(echo "$CONTAINERS" | jq '[.[] | select(.State == "running")] | length')
  FAILED=$(echo "$CONTAINERS" | jq '[.[] | select(.State == "exited" and (.Status | test("Exited \\(0\\)") | not))] | length')

  echo "🔄 [${COUNT}/${MAX_RETRY}] Running: ${RUNNING} | Failed: ${FAILED} | Total: ${TOTAL}"
  echo "$CONTAINERS" | jq -r '.[] | "   → \(.Names[0]) | \(.State) | \(.Status)"'

  if [ "$FAILED" -gt "0" ]; then
    echo ""
    echo "❌ Ada container yang crash!"
    echo "$CONTAINERS" | jq -r '.[] | select(.State == "exited" and (.Status | test("Exited \\(0\\)") | not)) | "   → \(.Names[0]) | \(.Status)"'
    exit 1
  fi

  if [ "$RUNNING" -gt "0" ]; then
    echo ""
    echo "✅ Stack $STACK_NAME berhasil di-redeploy dan running!"
    exit 0
  fi
done

echo ""
echo "❌ Timeout! Stack tidak kunjung running setelah $((MAX_RETRY * 5)) detik."
exit 1