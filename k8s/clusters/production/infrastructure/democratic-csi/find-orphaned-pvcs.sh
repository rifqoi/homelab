#!/usr/bin/env bash
set -euo pipefail

# find-orphaned-pvcs.sh
# Finds PVCs that exist in Kubernetes but have no corresponding backstore in targetcli
# Usage: ./find-orphaned-pvcs.sh <storage-ssh-target>

SSH_TARGET=${1:-}
if [ -z "$SSH_TARGET" ]; then
  echo "Usage: $0 <ssh-target>" >&2
  echo "Example: $0 rifqoi@192.168.30.101" >&2
  exit 2
fi

for pvc in $(kubectl get pvc -A -o jsonpath='{.items[*].metadata.uid}'); do
    # Check if this PVC UID exists in the targetcli backstores
    if ! ssh -o StrictHostKeyChecking=no "$SSH_TARGET" "sudo targetcli /backstores/block ls" | grep -q "$pvc"; then
        echo "Found Orphaned PVC (Exists in K8s, Missing in targetcli): $pvc"
        # Optional: show namespace/name for clarity
        kubectl get pvc -A -o json | jq -r ".items[] | select(.metadata.uid == \"$pvc\") | \"Namespace: \" + .metadata.namespace + \" Name: \" + .metadata.name"
    fi
done
