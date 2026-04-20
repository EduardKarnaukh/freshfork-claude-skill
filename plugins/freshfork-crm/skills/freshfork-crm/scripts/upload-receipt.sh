#!/usr/bin/env bash
# Upload a receipt / invoice file to Freshfork storage (no OCR).
# Uses multipart/form-data (api.sh only handles JSON — that's why this is a
# separate script).
#
# Use this when Claude has already parsed the document itself and just needs
# to attach the file to an expense. If you want the server to run OCR on the
# document, hit `/expenses/upload` directly instead.
#
# Usage:
#   upload-receipt.sh <path-to-file>
#
# Accepts: JPG, PNG, WEBP, PDF. Max 10 MB.
#
# Returns (stdout, JSON):
#   { "fileUrl": "https://.../expenses/2026/04/<uuid>-invoice.pdf" }
#
# Use that `fileUrl` as `receiptUrl` in the body of POST /expenses.
set -euo pipefail

CONFIG="${HOME}/.freshfork/config"
if [[ ! -f "$CONFIG" ]]; then
  echo "ERROR: $CONFIG not found. Run login.sh first." >&2
  exit 2
fi
# shellcheck disable=SC1090
source "$CONFIG"

: "${FRESHFORK_URL:?FRESHFORK_URL missing in $CONFIG}"
: "${FRESHFORK_TOKEN:?FRESHFORK_TOKEN missing in $CONFIG}"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <path-to-file>" >&2
  exit 2
fi

FILE="$1"
if [[ ! -f "$FILE" ]]; then
  echo "ERROR: file not found: $FILE" >&2
  exit 2
fi

SIZE=$(wc -c < "$FILE" | tr -d ' ')
if (( SIZE > 10 * 1024 * 1024 )); then
  echo "ERROR: file is larger than 10 MB (${SIZE} bytes)" >&2
  exit 2
fi

URL="${FRESHFORK_URL%/}/api/v1/expenses/receipt-upload"

exec curl -sS \
  -X POST \
  -H "Authorization: Bearer ${FRESHFORK_TOKEN}" \
  -H "Accept: application/json" \
  -F "file=@${FILE}" \
  "$URL"
