#!/usr/bin/env bash
# Restore Sonarr/Radarr settings to Seerr after Jellyfin setup wizard.
# Run on the deploy host after completing the Seerr setup wizard.
#
# Usage:
#   ./scripts/restore-seerr-arr-after-jellyfin.sh [path-to-backup-settings.json]

set -euo pipefail

CONFIG_ROOT="${CONFIG_ROOT:-/home/matt/PLEX/config}"
SEERR_DIR="${CONFIG_ROOT}/seerr"
BACKUP="${1:-$(ls -t "${SEERR_DIR}"/settings.json.plex-backup-* 2>/dev/null | head -1)}"

if [[ -z "${BACKUP}" || ! -f "${BACKUP}" ]]; then
  echo "ERROR: No backup file found. Pass path to settings.json.plex-backup-*" >&2
  exit 1
fi

python3 - "${BACKUP}" "${SEERR_DIR}/settings.json" <<'PY'
import json, sys
backup_path, current_path = sys.argv[1], sys.argv[2]
with open(backup_path) as f:
    backup = json.load(f)
with open(current_path) as f:
    current = json.load(f)
for key in ("radarr", "sonarr", "notifications", "tautulli"):
    if key in backup and backup[key]:
        current[key] = backup[key]
        print(f"Restored: {key}")
with open(current_path, "w") as f:
    json.dump(current, f, indent=2)
    f.write("\n")
print("Done. Restart the Seerr container to apply.")
PY
