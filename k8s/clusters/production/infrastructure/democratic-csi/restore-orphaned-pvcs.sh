#!/usr/bin/env bash
set -euo pipefail

# restore-orphaned-pvcs.sh
# Restores orphaned PVCs by piping UIDs into the fix script.
# Usage:
#   ./restore-orphaned-pvcs.sh <ssh-target> [--dry-run]
#   cat uids.txt | ./restore-orphaned-pvcs.sh <ssh-target>

SSH_TARGET=${1:-}
DRY_RUN=0
if [ "${2:-}" = "--dry-run" ]; then
  DRY_RUN=1
fi

if [ -z "$SSH_TARGET" ]; then
  echo "Usage: $0 <ssh-target> [--dry-run]" >&2
  exit 2
fi

SCRIPT_DIR=$(dirname "$0")
FIND_SCRIPT="$SCRIPT_DIR/find-orphaned-pvcs.sh"
FIX_SCRIPT="$SCRIPT_DIR/fix-iscsi-target.sh"

uids=()

# If stdin is piped, read UIDs from stdin (one per line or embedded)
if [ ! -t 0 ]; then
  # extract UUIDs from stdin
  mapfile -t uids < <(grep -oE '[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}' | sort -u)
else
  # Otherwise, run the finder script and extract UIDs
  mapfile -t uids < <("$FIND_SCRIPT" "$SSH_TARGET" | grep -oE '[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}' | sort -u)
fi

if [ ${#uids[@]} -eq 0 ]; then
  echo "No orphaned PVCs found."
  exit 0
fi

for uid in "${uids[@]}"; do
  echo "Restoring PVC $uid on $SSH_TARGET"
  if [ "$DRY_RUN" -eq 0 ]; then
    "$FIX_SCRIPT" "$SSH_TARGET" "$uid"
  else
    echo "DRY-RUN: Would run: $FIX_SCRIPT $SSH_TARGET $uid"
  fi
done
