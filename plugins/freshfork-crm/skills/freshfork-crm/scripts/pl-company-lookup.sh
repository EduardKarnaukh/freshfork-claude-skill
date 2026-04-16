#!/usr/bin/env bash
# Look up Polish company by NIP via the Ministry of Finance Whitelist API.
# https://wl-api.mf.gov.pl/  (free, no API key)
#
# Usage:
#   pl-company-lookup.sh <NIP>
#
# Output: JSON on stdout. The subject is under .result.subject (or null).
# Requires: curl. jq is optional (pretty-print).
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <NIP>" >&2
  exit 2
fi

NIP="${1//[^0-9]/}"  # strip non-digits
if [[ ${#NIP} -ne 10 ]]; then
  echo "ERROR: NIP must be 10 digits, got '${NIP}' (${#NIP} chars)" >&2
  exit 2
fi

# API accepts date=YYYY-MM-DD. Use today in server tz.
DATE="$(date +%F)"
URL="https://wl-api.mf.gov.pl/api/search/nip/${NIP}?date=${DATE}"

RESPONSE="$(curl -sS -H 'Accept: application/json' "$URL")"

if command -v jq >/dev/null 2>&1; then
  echo "$RESPONSE" | jq .
else
  echo "$RESPONSE"
fi
