#!/usr/bin/env bash
set -euo pipefail

# backup-saveconfig.sh
# Backup /etc/target/saveconfig.json into /etc/target/backups every hour.
# Intended to be installed on the storage host (run as root).


BACKUP_DIR=/etc/target/backups
SAVEFILE=/etc/target/saveconfig.json
TIMESTAMP=$(date -u +%Y%m%d-%H%M%SZ)
MAX_KEEP=20

mkdir -p "$BACKUP_DIR"

# Backup only: do not restore in this script
if [ ! -f "$SAVEFILE" ]; then
  echo "[backup-saveconfig] $SAVEFILE not found, skipping backup"
  exit 0
fi

content=$(tr -d '[:space:]' < "$SAVEFILE" 2>/dev/null || true)
if [ -z "$content" ] || [ "$content" = "{}" ]; then
  echo "[backup-saveconfig] $SAVEFILE is empty/{}; skipping backup"
  exit 0
fi

cp -p "$SAVEFILE" "$BACKUP_DIR/saveconfig.${TIMESTAMP}.json"
echo "[backup-saveconfig] saved $SAVEFILE -> $BACKUP_DIR/saveconfig.${TIMESTAMP}.json"

# Keep last $MAX_KEEP backups
if ls -1t "$BACKUP_DIR"/saveconfig.*.json >/dev/null 2>&1; then
  ls -1t "$BACKUP_DIR"/saveconfig.*.json | tail -n +$((MAX_KEEP+1)) | xargs -r rm -f
fi

exit 0
