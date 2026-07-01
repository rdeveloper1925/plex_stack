#!/usr/bin/env bash
# Reset Seerr to the Jellyfin setup wizard (preserves database + Sonarr/Radarr backup).
#
# Usage on deploy host:
#   ./scripts/reset-seerr-for-jellyfin-wizard.sh
#
# After completing the wizard in the browser, run:
#   ./scripts/restore-seerr-arr-after-jellyfin.sh

set -euo pipefail

CONFIG_ROOT="${CONFIG_ROOT:-/home/matt/PLEX/config}"
SEERR_DIR="${CONFIG_ROOT}/seerr"
COMPOSE_DIR="${COMPOSE_DIR:-/etc/dokploy/compose/plex-stack-yfy5op/code}"
BACKUP="${SEERR_DIR}/settings.json.plex-backup-$(date +%Y%m%d-%H%M%S)"

if [[ ! -f "${SEERR_DIR}/settings.json" ]]; then
  echo "ERROR: ${SEERR_DIR}/settings.json not found" >&2
  exit 1
fi

echo "Backing up settings to ${BACKUP}"
cp -a "${SEERR_DIR}/settings.json" "${BACKUP}"

echo "Stopping Seerr..."
if [[ -f "${COMPOSE_DIR}/docker-compose.yml" ]]; then
  docker compose -f "${COMPOSE_DIR}/docker-compose.yml" stop seerr
else
  docker stop "$(docker ps -q --filter name=seerr)" 2>/dev/null || true
fi

echo "Removing settings.json (database preserved)..."
rm -f "${SEERR_DIR}/settings.json" "${SEERR_DIR}/settings.old.json"

echo "Starting Seerr..."
if [[ -f "${COMPOSE_DIR}/docker-compose.yml" ]]; then
  docker compose -f "${COMPOSE_DIR}/docker-compose.yml" start seerr
else
  docker start "$(docker ps -aq --filter name=seerr | head -1)"
fi

echo ""
echo "Seerr reset complete."
echo "1. Open http://<BIND_IP>:5055 and complete the Jellyfin setup wizard"
echo "2. Jellyfin internal URL: http://jellyfin:8096"
echo "3. Jellyfin external URL: https://movies.mattapps.org"
echo "4. Sign in with your Jellyfin admin account (e.g. matt)"
echo "5. Select Movies and TV Shows libraries, then finish setup"
echo "6. Run: ./scripts/restore-seerr-arr-after-jellyfin.sh ${BACKUP}"
echo "7. Restart Seerr: docker compose restart seerr"
