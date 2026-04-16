#!/usr/bin/env bash
# freshfork-skill login — device-code auth for Freshfork CRM.
# Opens the browser, user clicks Approve on /settings/connect-cli,
# then we save the Personal Access Token to ~/.freshfork/config.
#
# Usage:
#   login.sh                       # uses existing FRESHFORK_URL, or prompts
#   login.sh https://crm.host      # set URL and login
set -euo pipefail

CONFIG_DIR="${HOME}/.freshfork"
CONFIG_FILE="${CONFIG_DIR}/config"

url_from_arg="${1:-}"
url_from_env="${FRESHFORK_URL:-}"
url_from_config=""
if [[ -f "$CONFIG_FILE" ]]; then
  url_from_config="$(grep -E '^FRESHFORK_URL=' "$CONFIG_FILE" | tail -n1 | cut -d= -f2- || true)"
fi

DEFAULT_URL="https://crm.similar.group"
FRESHFORK_URL="${url_from_arg:-${url_from_env:-$url_from_config}}"

if [[ -z "${FRESHFORK_URL}" ]]; then
  echo -n "Freshfork CRM URL [$DEFAULT_URL]: "
  read -r FRESHFORK_URL
  FRESHFORK_URL="${FRESHFORK_URL:-$DEFAULT_URL}"
fi
FRESHFORK_URL="${FRESHFORK_URL%/}"

DEVICE_NAME="${FRESHFORK_DEVICE_NAME:-$(hostname -s 2>/dev/null || hostname)}"

echo "→ Starting device-code flow at ${FRESHFORK_URL}..."

START_RESPONSE="$(curl -sSf -X POST \
  -H 'Content-Type: application/json' \
  -d "{\"deviceName\":\"${DEVICE_NAME}\"}" \
  "${FRESHFORK_URL}/api/v1/auth/cli/start")"

CODE="$(echo "$START_RESPONSE" | sed -n 's/.*"code":"\([^"]*\)".*/\1/p')"
EXPIRES_IN="$(echo "$START_RESPONSE" | sed -n 's/.*"expiresIn":\([0-9]*\).*/\1/p')"

if [[ -z "$CODE" ]]; then
  echo "ERROR: failed to parse start response:" >&2
  echo "$START_RESPONSE" >&2
  exit 1
fi

APPROVE_URL="${FRESHFORK_URL}/settings/connect-cli?code=${CODE}"

echo ""
echo "  Code:         ${CODE}"
echo "  Device:       ${DEVICE_NAME}"
echo "  Approve URL:  ${APPROVE_URL}"
echo "  Expires:      ${EXPIRES_IN:-600}s"
echo ""

# Try to open browser automatically.
open_browser() {
  if command -v open >/dev/null 2>&1; then open "$1" >/dev/null 2>&1 || true
  elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$1" >/dev/null 2>&1 || true
  elif command -v cygstart >/dev/null 2>&1; then cygstart "$1" >/dev/null 2>&1 || true
  else return 1
  fi
}
if open_browser "$APPROVE_URL"; then
  echo "→ Opened browser. Complete the approval there."
else
  echo "→ Could not open browser automatically. Open the Approve URL manually."
fi

echo "→ Polling every 2s..."

DEADLINE=$(( $(date +%s) + ${EXPIRES_IN:-600} ))
TOKEN=""
while :; do
  if (( $(date +%s) > DEADLINE )); then
    echo "ERROR: timed out waiting for approval" >&2
    exit 1
  fi
  STATUS_RESPONSE="$(curl -sSf "${FRESHFORK_URL}/api/v1/auth/cli/status?code=${CODE}" || echo '')"
  STATUS="$(echo "$STATUS_RESPONSE" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')"

  case "$STATUS" in
    pending)
      sleep 2
      continue
      ;;
    approved)
      TOKEN="$(echo "$STATUS_RESPONSE" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
      if [[ -z "$TOKEN" ]]; then
        echo "ERROR: approved but no token field in response:" >&2
        echo "$STATUS_RESPONSE" >&2
        exit 1
      fi
      break
      ;;
    expired)
      echo "ERROR: request expired — run login again" >&2
      exit 1
      ;;
    consumed)
      echo "ERROR: token was already consumed by another run — start login again" >&2
      exit 1
      ;;
    not_found)
      echo "ERROR: request not found on server" >&2
      exit 1
      ;;
    *)
      echo "Unexpected status: $STATUS (response: $STATUS_RESPONSE)" >&2
      sleep 2
      ;;
  esac
done

mkdir -p "$CONFIG_DIR"
umask 077
cat > "$CONFIG_FILE" <<EOF
FRESHFORK_URL=${FRESHFORK_URL}
FRESHFORK_TOKEN=${TOKEN}
EOF
chmod 600 "$CONFIG_FILE"

echo ""
echo "✓ Token saved to ${CONFIG_FILE}"
echo "✓ You can now run: bash ~/.claude/skills/freshfork-crm/scripts/api.sh GET /clients?perPage=1"
