#!/usr/bin/env bash
# Check that Gluetun has a PIA forwarded port. Log only — do not restart containers.
# A wrong FIREWALL_OUTBOUND_SUBNETS (e.g. 10.0.0.0/8) used to make this loop-restart
# gluetun + qBittorrent + Prowlarr + FlareSolverr. Compose now hardcodes safe Docker CIDRs.

set -euo pipefail

GLUETUN_CONTAINER="${GLUETUN_CONTAINER:-plex-stack-yfy5op-gluetun-1}"

if ! docker exec "${GLUETUN_CONTAINER}" test -s /tmp/gluetun/forwarded_port 2>/dev/null; then
    logger -t pia-portforward "No forwarded port file on ${GLUETUN_CONTAINER}"
    exit 1
fi

port=$(docker exec "${GLUETUN_CONTAINER}" cat /tmp/gluetun/forwarded_port 2>/dev/null | tr -d '[:space:]')
if [ -z "${port}" ] || [ "${port}" = "0" ]; then
    logger -t pia-portforward "Forwarded port unset on ${GLUETUN_CONTAINER}"
    exit 1
fi

exit 0
