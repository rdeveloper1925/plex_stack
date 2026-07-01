#!/usr/bin/env bash
# Fix Cloudflare Tunnel origin for Jellyfin: must be HTTP, not HTTPS.
# Jellyfin on linuxserver serves plain HTTP on port 8096.
#
# Usage:
#   export CLOUDFLARE_API_TOKEN="your-token-with-cloudflare-tunnel-write"
#   ./scripts/fix-cloudflare-jellyfin-origin.sh
#
# Manual fix: Cloudflare Zero Trust → Networks → Tunnels → your tunnel →
# Public Hostname movies.mattapps.org → Service URL: http://127.0.0.1:8096
# (NOT https://localhost:8096)

set -euo pipefail

ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-dc8128887a393c62501d63cdb1873eb}"
TUNNEL_ID="${CLOUDFLARE_TUNNEL_ID:-60254089-b10f-48e0-8ee2-1e93bdff485}"
HOSTNAME="${JELLYFIN_HOSTNAME:-movies.mattapps.org}"
ORIGIN_URL="${JELLYFIN_ORIGIN_URL:-http://127.0.0.1:8096}"

if [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
  echo "ERROR: Set CLOUDFLARE_API_TOKEN (Account → Cloudflare Tunnel → Edit)." >&2
  echo "Or fix manually in Cloudflare Zero Trust:" >&2
  echo "  Hostname: ${HOSTNAME}" >&2
  echo "  Service URL: ${ORIGIN_URL}" >&2
  exit 1
fi

API="https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/configurations"
TMP=$(mktemp)
trap 'rm -f "${TMP}"' EXIT

echo "Fetching current tunnel configuration..."
HTTP_CODE=$(curl -s -o "${TMP}" -w "%{http_code}" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  -H "Content-Type: application/json" \
  "${API}")

if [[ "${HTTP_CODE}" != "200" ]]; then
  echo "ERROR: Failed to fetch tunnel config (HTTP ${HTTP_CODE}):" >&2
  cat "${TMP}" >&2
  exit 1
fi

echo "Updating ${HOSTNAME} origin to ${ORIGIN_URL}..."
HOSTNAME="${HOSTNAME}" ORIGIN_URL="${ORIGIN_URL}" python3 - "${TMP}" <<'PY' > "${TMP}.out"
import json, os, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
if not data.get("success"):
    raise SystemExit(json.dumps(data))
ingress = data["result"]["config"]["ingress"]
hostname = os.environ["HOSTNAME"]
origin = os.environ["ORIGIN_URL"]
for rule in ingress:
    if rule.get("hostname") == hostname:
        rule["service"] = origin
        rule.setdefault("originRequest", {})
        break
else:
    ingress.insert(-1, {
        "hostname": hostname,
        "service": origin,
        "originRequest": {},
    })
print(json.dumps({"config": {"ingress": ingress}}))
PY

RESULT_CODE=$(curl -s -o "${TMP}.result" -w "%{http_code}" \
  -X PUT \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  -H "Content-Type: application/json" \
  --data @"${TMP}.out" \
  "${API}")

if [[ "${RESULT_CODE}" == "200" ]] && grep -q '"success":true' "${TMP}.result"; then
  echo "OK: Tunnel configuration updated."
  echo "Wait ~30s, then test: curl -s -o /dev/null -w '%{http_code}' https://${HOSTNAME}/"
else
  echo "ERROR: Update failed (HTTP ${RESULT_CODE}):" >&2
  cat "${TMP}.result" >&2
  exit 1
fi
