#!/usr/bin/env bash

# fix-iscsi-target.sh - Recreate missing iSCSI targets for dangling PVCs
# 
# Usage: ./fix-iscsi-target.sh <ssh-target> <pvc-uuid>
# Example: ./fix-iscsi-target.sh root@192.168.30.101 f785d643-e7e3-41d1-86bd-bdd5f1bc43e8
#
# This script recreates an iSCSI target configuration when a PVC becomes dangling
# after host reboot or configuration loss. It executes all commands via SSH.
# See README.md for full documentation.

set -euo pipefail

SSH_TARGET=$1
PVC_ID=$2
ZVOL_PATH="/dev/zvol/rpool/k8s-data/vols/pvc-${PVC_ID}"
IQN="iqn.2003-01.org.linux-iscsi.k8s:csi-pvc-${PVC_ID}"

if [ -z "$SSH_TARGET" ] || [ -z "$PVC_ID" ]; then
    echo "Error: Missing required arguments."
    echo "Usage: ./fix-iscsi-target.sh <ssh-target> <pvc-uuid>"
    echo "Example: ./fix-iscsi-target.sh root@192.168.30.101 f785d643-e7e3-41d1-86bd-bdd5f1bc43e8"
    exit 1
fi

# Helper function to run commands on remote host via SSH
run_remote() {
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$SSH_TARGET" "$@"
}

echo "--- Configuring iSCSI Target for $PVC_ID on $SSH_TARGET ---"

# Check if target already exists and delete it first to ensure clean state
echo "[0/5] Checking for existing target..."
if run_remote sudo targetcli ls | grep -q "$IQN"; then
    echo "Target already exists. Deleting for clean reconfiguration..."
    run_remote sudo targetcli /iscsi delete "$IQN" || true
fi

# Check if backstore already exists and delete it
echo "Checking for existing backstore..."
if run_remote sudo targetcli ls | grep -q "csi-pvc-${PVC_ID}"; then
    echo "Backstore already exists. Deleting for clean reconfiguration..."
    run_remote sudo targetcli /backstores/block delete "csi-pvc-${PVC_ID}" || true
fi

# Verify ZVOL exists before proceeding
if ! run_remote test -b "$ZVOL_PATH"; then
    echo "Error: ZVOL $ZVOL_PATH not found on $SSH_TARGET. Is the ZFS pool imported?"
    exit 1
fi

# 1. Create Backstore
# This exposes the ZVOL as a block device target
echo "[1/5] Creating backstore..."
run_remote sudo targetcli /backstores/block create name="csi-pvc-${PVC_ID}" dev="$ZVOL_PATH"

# 2. Create Target IQN
# IQN (iSCSI Qualified Name) uniquely identifies this target
# Format: iqn.yyyy-mm.org.example.project:unique-identifier
echo "[2/5] Creating target IQN..."
run_remote sudo targetcli /iscsi create "$IQN"

# 3. Create LUN0 mapping
# Maps the backstore block device to LUN 0 (Logical Unit Number)
# This is what initiators will see when connecting to the target
echo "[3/5] Creating LUN0 mapping..."
run_remote sudo targetcli "/iscsi/${IQN}/tpg1/luns" create "/backstores/block/csi-pvc-${PVC_ID}"

# 4. Set Attributes (Democratic-CSI defaults)
# - generate_node_acls=1: Automatically create ACLs for any connecting initiator
# - demo_mode_write_protect=0: Allow write access (not read-only)
# - cache_dynamic_acls=1: Cache ACL decisions for performance
echo "[4/5] Setting target attributes..."
run_remote sudo targetcli "/iscsi/${IQN}/tpg1" set attribute generate_node_acls=1
run_remote sudo targetcli "/iscsi/${IQN}/tpg1" set attribute demo_mode_write_protect=0
run_remote sudo targetcli "/iscsi/${IQN}/tpg1" set attribute cache_dynamic_acls=1

# 5. Save configuration to /etc/target/saveconfig.json
# This ensures the target configuration persists across reboots
echo "[5/5] Saving configuration..."
run_remote sudo targetcli saveconfig

echo ""
echo "✓ Done! iSCSI target configured successfully on $SSH_TARGET."
echo ""
echo "Verify with: ssh $SSH_TARGET sudo targetcli ls"
echo ""
echo "Next steps:"
echo "1. On Kubernetes cluster, restart the pod"
echo "2. The pod will reconnect to the newly configured target"
