# homelab

## ZFS and Disko Safety Note

Do not add a `fileSystems` mount for a ZFS dataset that does not already exist.

- New datasets are often created imperatively (for example with `zfs create ...`).
- A normal `nixos-rebuild` does not run Disko to create newly declared datasets.
- If you declare a mount first and the dataset is missing, boot/rebuild can fail.

Recommended order:
1. Create the dataset first (imperatively or by running Disko in the correct workflow).
2. Verify it exists with `zfs list`.
3. Only then add the corresponding `fileSystems` mount in Nix config.

## Cluster Template Sync Operations

When performing cluster template sync operations (such as adding patches, extensions, or other configuration changes), ensure proper node maintenance:

**⚠️ IMPORTANT:** If nodes are not properly cordoned and drained before updates, the upgrade sequence will fail with context deadline exceeded errors and enter an upgrade loop (constantly restarting). This can cause service disruptions and require manual intervention to recover.

**Before updating:**
1. Cordon the node(s) being updated: `kubectl cordon <node-name>`
2. Drain the node(s) to evict workloads: `kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data`
3. Proceed with applying patches or extensions

**Using omnictl:**

Sync cluster templates using omnictl:
```bash
omnictl cluster template sync -f filename.yaml
```

This command applies cluster template changes defined in the YAML file to your cluster. The template typically includes configurations for patches, extensions, and other cluster-level settings.

**After completing updates:**
1. Uncordon the node(s): `kubectl uncordon <node-name>`

This ensures zero-downtime updates and prevents scheduling of new pods on nodes undergoing maintenance.

## iSCSI with Democratic-CSI

Democratic-CSI provides Kubernetes persistent volumes backed by iSCSI targets. The iSCSI targets are backed by ZFS volumes and managed by `targetcli`.

### Troubleshooting After Host Reboot

When the storage host reboots, verify the iSCSI target configuration with these checks:

**1. Check target configuration:**
```bash
sudo targetcli ls
```
Should show all configured iSCSI targets with backstores, portals, and LUNs. If empty, configuration was lost.

**2. Verify persistence file exists:**
```bash
ls -la /etc/target/saveconfig.json
```
If this file doesn't exist, targets won't persist across reboots.

**3. Check service status:**
```bash
sudo systemctl status iscsi-target
```
If inactive, restart with: `sudo systemctl restart iscsi-target`

**4. Restore from backup if needed:**
```bash
ls -lt /etc/target/backups/
# Restore latest backup
sudo cp /etc/target/backups/saveconfig.json.YYYYMMDD-HHMMSS /etc/target/saveconfig.json
sudo systemctl restart iscsi-target
```

### Fixing Dangling PVCs

When a PVC becomes dangling (iSCSI target missing but ZVOL exists), use the recovery script:

```bash
sudo /path/to/fix-iscsi-target.sh <pvc-uuid>
```

The script recreates the iSCSI target with proper configuration:
- Creates backstore from ZVOL at `/dev/zvol/rpool/k8s-data/vols/pvc-<uuid>`
- Creates target IQN: `iqn.2003-01.org.linux-iscsi.k8s:csi-pvc-<uuid>`
- Maps LUN0 and creates portal on 0.0.0.0:3260
- Sets Democratic-CSI defaults (auto-ACLs, write-enabled, cached)
- Saves configuration to `/etc/target/saveconfig.json`

**Why dangling PVCs happen:**
- Configuration file (`/etc/target/saveconfig.json`) was deleted or corrupted during reboot
- Manual target deletion with `targetcli delete`
- Partial provisioning when pod was deleted mid-setup
- iSCSI frontend not recreated when storage backend exists

**After running the script:**
```bash
# Verify target was created
sudo targetcli ls

# Restart the pod to reconnect to the newly configured target
kubectl delete pod <pod-name> -n <namespace>

# The PVC will automatically remount once the pod is recreated
```

### Common Issues

**"ZVOL not found"** → Check ZFS pool is imported: `sudo zpool list` and `sudo zfs list rpool/k8s-data/vols/`

**"Target already exists"** → Delete existing target first: `sudo targetcli /iscsi delete iqn.2003-01.org.linux-iscsi.k8s:csi-pvc-<uuid>`

**PVC still won't mount** → Talos automatically discovers and connects to iSCSI targets. Restart the pod to trigger reconnection: `kubectl delete pod <pod-name> -n <namespace>`

**Debugging Talos iSCSI connectivity** → Check the external iSCSI daemon logs:
```bash
talosctl logs ext-iscsid -n <node-name>
```
This shows discovery and connection issues between Talos nodes and iSCSI targets.

**Read-only filesystem errors in PostgreSQL** → If you see `could not open file: Read-only file system` errors:
1. First check if iSCSI targets are properly connected on the storage host:
   ```bash
   ssh rifqoi@<storage-host> sudo targetcli ls
   ```
2. Check if the node has iSCSI connectivity issues:
   ```bash
   talosctl logs ext-iscsid -n <node-name>
   ```
3. If iSCSI is properly connected but filesystem is still read-only, reboot the affected node:
   ```bash
   talosctl reboot -n <node-name>
   ```
4. After reboot, verify the filesystem mounted correctly:
   ```bash
   kubectl exec -it <postgres-pod> -n <namespace> -- df -h
   # Should show rw (not ro) for the volume mount
   ```
5. Check the node logs to confirm there were no lingering filesystem errors:
   ```bash
   talosctl logs -k -n <node-name> | grep -i "read-only"
   ```

### Running the Recovery Script

**Option 1: From root flake** (recommended)
```bash
nix run .#fix-iscsi-target -- <storage-host> <pvc-uuid>
```

**Option 2: Direct execution**
```bash
./k8s/clusters/production/infrastructure/democratic-csi/fix-iscsi-target.sh <storage-host> <pvc-uuid>
```
