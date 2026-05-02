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
