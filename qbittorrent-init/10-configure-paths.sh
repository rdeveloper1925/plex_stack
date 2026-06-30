#!/usr/bin/with-contenv bash
# Align linuxserver defaults (/downloads) with the shared /data volume layout.
# Runs on every container start so fresh and existing configs stay correct.

set -e

CONF="/config/qBittorrent/qBittorrent.conf"
SAVE_PATH="/data/torrents"
TEMP_PATH="/data/torrents/incomplete"

mkdir -p "${SAVE_PATH}/movies" "${SAVE_PATH}/tv" "${TEMP_PATH}"
chown -R "${PUID}:${PGID}" "${SAVE_PATH}/movies" "${SAVE_PATH}/tv" "${TEMP_PATH}" 2>/dev/null || true

if [ ! -f "${CONF}" ] && [ -f /defaults/qBittorrent.conf ]; then
    mkdir -p /config/qBittorrent
    cp /defaults/qBittorrent.conf "${CONF}"
fi

if [ -f "${CONF}" ]; then
    sed -i \
        -e "s|Downloads\\\\SavePath=/downloads/|Downloads\\\\SavePath=${SAVE_PATH}/|g" \
        -e "s|Downloads\\\\TempPath=/downloads/incomplete/|Downloads\\\\TempPath=${TEMP_PATH}/|g" \
        -e "s|Session\\\\DefaultSavePath=/downloads/|Session\\\\DefaultSavePath=${SAVE_PATH}/|g" \
        -e "s|Session\\\\TempPath=/downloads/incomplete/|Session\\\\TempPath=${TEMP_PATH}/|g" \
        "${CONF}"

  # Required for Gluetun to push the forwarded port via the Web API.
  if ! grep -q '^WebUI\\LocalHostAuth=' "${CONF}"; then
      printf '\nWebUI\\LocalHostAuth=false\n' >> "${CONF}"
  else
      sed -i 's|^WebUI\\LocalHostAuth=.*|WebUI\\LocalHostAuth=false|' "${CONF}"
  fi
fi
