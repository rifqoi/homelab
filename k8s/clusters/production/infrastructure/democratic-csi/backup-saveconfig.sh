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

cp "$SAVEFILE" "$BACKUP_DIR/saveconfig.${TIMESTAMP}.json"
echo "[backup-saveconfig] saved $SAVEFILE -> $BACKUP_DIR/saveconfig.${TIMESTAMP}.json"

# Filenames contain sortable UTC timestamps; do not depend on copied mtimes.
if compgen -G "$BACKUP_DIR/saveconfig.*.json" >/dev/null; then
  find "$BACKUP_DIR" -maxdepth 1 -type f -name 'saveconfig.*.json' -print \
    | sort -r \
    | tail -n +$((MAX_KEEP+1)) \
    | xargs -r rm -f
fi

exit 0
