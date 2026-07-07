#!/usr/bin/with-contenv bash
# Align linuxserver defaults (/downloads) with the shared /data volume layout.
# Runs on every container start so fresh and existing configs stay correct.

set -e

CONF="/config/qBittorrent/qBittorrent.conf"
CATEGORIES="/config/qBittorrent/categories.json"
SAVE_PATH="/data/torrents"
TEMP_PATH="/data/torrents/incomplete"
TV_PATH="/data/torrents/tv"
MOVIES_PATH="/data/torrents/movies"

mkdir -p "${MOVIES_PATH}" "${TV_PATH}" "${TEMP_PATH}"
chown -R "${PUID}:${PGID}" "${SAVE_PATH}/movies" "${SAVE_PATH}/tv" "${TEMP_PATH}" 2>/dev/null || true

if [ ! -f "${CONF}" ] && [ -f /defaults/qBittorrent.conf ]; then
    mkdir -p /config/qBittorrent
    cp /defaults/qBittorrent.conf "${CONF}"
fi

if [ -f "${CONF}" ]; then
    python3 - "${CONF}" "${SAVE_PATH}" "${TEMP_PATH}" <<'PY'
import sys

conf_path, save_path, temp_path = sys.argv[1:4]
updates = {
    "Downloads\\SavePath": f"{save_path}/",
    "Downloads\\TempPath": f"{temp_path}/",
    "Session\\DefaultSavePath": save_path,
    "Session\\TempPath": temp_path,
}

lines = []
seen = set()
with open(conf_path, encoding="utf-8") as handle:
    for line in handle.read().splitlines():
        key = line.split("=", 1)[0] if "=" in line else None
        if key in updates:
            lines.append(f"{key}={updates[key]}")
            seen.add(key)
        else:
            lines.append(line)

for key, value in updates.items():
    if key not in seen:
        lines.append(f"{key}={value}")

with open(conf_path, "w", encoding="utf-8") as handle:
    handle.write("\n".join(lines) + "\n")
PY

    if ! grep -q '^WebUI\\LocalHostAuth=' "${CONF}"; then
        printf '\nWebUI\\LocalHostAuth=false\n' >> "${CONF}"
    else
        sed -i 's|^WebUI\\LocalHostAuth=.*|WebUI\\LocalHostAuth=false|' "${CONF}"
    fi
fi

python3 - "${CATEGORIES}" "${TV_PATH}" "${MOVIES_PATH}" <<'PY'
import json
import sys
from pathlib import Path

categories_path = Path(sys.argv[1])
tv_path = sys.argv[2]
movies_path = sys.argv[3]

defaults = {
    "download_path": None,
    "inactive_seeding_time_limit": -2,
    "ratio_limit": -2,
    "seeding_time_limit": -2,
    "share_limit_action": "Default",
}

data = {}
if categories_path.exists():
    data = json.loads(categories_path.read_text(encoding="utf-8"))

for name, path in (("tv", tv_path), ("movies", movies_path)):
    entry = {**defaults, **data.get(name, {})}
    entry["save_path"] = path
    data[name] = entry

categories_path.parent.mkdir(parents=True, exist_ok=True)
categories_path.write_text(json.dumps(data, indent=4) + "\n", encoding="utf-8")
PY

chown "${PUID}:${PGID}" "${CONF}" "${CATEGORIES}" 2>/dev/null || true
