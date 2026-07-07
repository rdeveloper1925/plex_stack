#!/usr/bin/env bash
# Retry PIA port forwarding by restarting Gluetun when no forwarded port is assigned.
# Install via cron on the deploy host (see README).

set -euo pipefail

COMPOSE_DIR="${COMPOSE_DIR:-/etc/dokploy/compose/plex-stack-yfy5op/code}"
COMPOSE_PROJECT="${COMPOSE_PROJECT:-plex-stack-yfy5op}"
GLUETUN_CONTAINER="${GLUETUN_CONTAINER:-plex-stack-yfy5op-gluetun-1}"
LOCK_FILE="/tmp/pia-portforward-retry.lock"
MIN_RESTART_INTERVAL=900 # 15 minutes

if [ -f "${LOCK_FILE}" ]; then
    last=$(stat -c %Y "${LOCK_FILE}" 2>/dev/null || echo 0)
    now=$(date +%s)
    if [ $((now - last)) -lt "${MIN_RESTART_INTERVAL}" ]; then
        exit 0
    fi
fi

if docker exec "${GLUETUN_CONTAINER}" test -s /tmp/gluetun/forwarded_port 2>/dev/null; then
    port=$(docker exec "${GLUETUN_CONTAINER}" cat /tmp/gluetun/forwarded_port 2>/dev/null | tr -d '[:space:]')
    if [ -n "${port}" ] && [ "${port}" != "0" ]; then
        exit 0
    fi
fi

if ! docker logs "${GLUETUN_CONTAINER}" 2>&1 | tail -30 | grep -q "port forwarding"; then
    exit 0
fi

touch "${LOCK_FILE}"
logger -t pia-portforward "No forwarded port on ${GLUETUN_CONTAINER}; restarting Gluetun sidecars"
cd "${COMPOSE_DIR}"
docker compose -p "${COMPOSE_PROJECT}" restart gluetun
sleep 35
docker compose -p "${COMPOSE_PROJECT}" restart qbittorrent prowlarr flaresolverr
