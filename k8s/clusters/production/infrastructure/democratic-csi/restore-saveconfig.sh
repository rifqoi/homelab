#!/usr/bin/env bash
set -euo pipefail

# restore-saveconfig.sh
# Restore /etc/target/saveconfig.json from the most recent backup when missing/empty/{}.

BACKUP_DIR=/etc/target/backups
SAVEFILE=/etc/target/saveconfig.json

mkdir -p "$BACKUP_DIR"

needs_restore=0
if [ ! -f "$SAVEFILE" ]; then
  needs_restore=1
else
  content=$(tr -d '[:space:]' < "$SAVEFILE" 2>/dev/null || true)
  if [ -z "$content" ] || [ "$content" = "{}" ]; then
    needs_restore=1
  fi
fi

if [ "$needs_restore" -eq 0 ]; then
  echo "[restore-saveconfig] $SAVEFILE is present and non-empty; nothing to restore"
  exit 0
fi

latest=$(ls -1t "$BACKUP_DIR"/saveconfig.*.json 2>/dev/null | head -n1 || true)
if [ -z "$latest" ]; then
  echo "[restore-saveconfig] No backups found in $BACKUP_DIR"
  exit 0
fi

cp -p "$latest" "$SAVEFILE"
echo "[restore-saveconfig] Restored $SAVEFILE from $latest"
