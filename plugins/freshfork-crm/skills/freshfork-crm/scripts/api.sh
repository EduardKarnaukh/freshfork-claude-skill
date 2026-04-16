#!/usr/bin/env bash
# Freshfork CRM API wrapper.
# Reads ~/.freshfork/config (FRESHFORK_URL, FRESHFORK_TOKEN), adds Bearer auth
# and /api/v1 prefix, forwards everything else to curl.
#
# Usage:
#   api.sh <METHOD> <PATH> [curl args...]
#
# Examples:
#   api.sh GET /clients?perPage=5
#   api.sh GET "/clients/search?q=8993025824"
#   api.sh POST /clients -d '{"companyName":"Firma ABC Sp. z o.o.","nip":"8993025824"}'
#   api.sh PUT /clients/<uuid> -d '{"paymentTermDays":21}'
#   api.sh DELETE /clients/<uuid>
set -euo pipefail

CONFIG="${HOME}/.freshfork/config"
if [[ ! -f "$CONFIG" ]]; then
  echo "ERROR: $CONFIG not found" >&2
  echo "Run login.sh to create it, or write it manually with:" >&2
  echo "  FRESHFORK_URL=https://crm.similar.group" >&2
  echo "  FRESHFORK_TOKEN=ffcrm_pat_xxxxxxxx" >&2
  exit 2
fi
# shellcheck disable=SC1090
source "$CONFIG"

: "${FRESHFORK_URL:?FRESHFORK_URL missing in $CONFIG}"
: "${FRESHFORK_TOKEN:?FRESHFORK_TOKEN missing in $CONFIG}"

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <METHOD> <PATH> [curl args...]" >&2
  exit 2
fi

METHOD="$1"; shift
REQ_PATH="$1"; shift

# Strip leading slash duplicates, prefix /api/v1
REQ_PATH="/${REQ_PATH#/}"
URL="${FRESHFORK_URL%/}/api/v1${REQ_PATH}"

# -sS = silent but show errors, -w adds \n + http status on its own line
exec curl -sS \
  -X "$METHOD" \
  -H "Authorization: Bearer ${FRESHFORK_TOKEN}" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  "$@" \
  "$URL"
