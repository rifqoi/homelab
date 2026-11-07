# atlas incident, 2026-11-06 to 2026-11-07

Paseo was down for about 31h. Fixing it turned into an Omni and Talos upgrade,
a NixOS 26.11 bump on atlas, and an etcd WAL corruption on the single control
plane. Everything points at silent memory corruption on atlas, which has
non-ECC RAM. Below is the timeline, followed by one recovery procedure per
failure we hit.

## Timeline (WIB)

| when | what |
| --- | --- |
| Nov 6 06:01 | zed logs `class=dio_verify_wr err=5` on rpool. In the same second libvirt pauses `talos-prod-cluster-workers-hblqnd` with `IO error ... No space left on device`. The pool had 537G free. |
| Nov 6 06:02 | The node goes NotReady. Paseo's RWO iSCSI PVC stays attached to the dead node; the replacement pod sticks at `Init:0/2` and the site returns 503. |
| Nov 7 13:12 | `virsh resume` brings the node back. Its guest clock is 31h behind, so its Talos apid cert (24h validity) looks valid to the node but expired to Omni. |
| Nov 7 13:20 | `zfs set direct=disabled rpool/vm rpool/vm-images` (PR #70). |
| Nov 7 13:36 | Omni 1.6.1 -> 1.13.2, libvirt provider pinned to v0.3.0 (PR #71). |
| Nov 7 14:26-14:28 | During the Talos 1.13.12 rollout atlas runs out of memory. The OOM killer takes out omni, pocket-id, the registry, garage, grafana, prometheus and tailscaled. |
| Nov 7 ~15:26 | A single bit flips in an etcd WAL record on the control plane. Nothing notices yet. |
| Nov 7 15:06-15:29 | The Talos 1.14.5 rollout hangs draining a node because of the single-instance CNPG PDBs (PR #72). |
| Nov 7 16:29 | A live `switch` to NixOS 26.11 fails and rolls back. Meanwhile pocket-id has migrated its DB forward, so the old pocket-id now refuses to start, and Omni with it. |
| Nov 7 16:41 | atlas reboots into 26.11 (PR #75 and this branch). The control-plane etcd won't start: `walpb: crc mismatch`. |
| Nov 7 16:58 | Moving the corrupt (already snapshotted) WAL files aside brings etcd back. No data lost. |

## Root cause: bit flips in atlas RAM (likely)

- atlas is a Lenovo ThinkCentre `11DQS08100` with 2x16G SK Hynix DDR4 SODIMMs
  (`HMA82GS6CJR8N-VK` and `HMA82GS6DJR8N-VK`, different revisions).
  `dmidecode -t memory` reports `Error Correction Type: None`, and there's no
  EDAC, so bit flips are silent.
- The etcd WAL damage was exactly one bit: the protobuf tag of a HardState
  record went `0x18` -> `0x38`, while the commit value after it was still
  correct. ZFS reported 0 checksum errors, so the buffer was already wrong
  before ZFS checksummed it. The flip happened in RAM, not on the NVMe.
- `dio_verify_wr` means ZFS checksummed a Direct I/O buffer and found it
  changed by the time it wrote it. A RAM flip and a guest modifying its
  buffer mid-write both produce that error.
- The control-plane disk also holds an older `...wal.broken` from 2026-10-05.

**TODO:** run memtest86+ on atlas overnight (whole-cluster downtime). If it
finds errors, test each DIMM on its own and replace the bad one.

## Recovery procedures

All commands assume the homelab kubeconfig from the Omni UI and omnictl
>= 1.13 (in the dev shell since PR #75). The kubeconfig authenticates via
`kubectl oidc-login`; get it with `nix build nixpkgs#kubelogin-oidc` if it's
missing.

### A Talos VM is `paused (I/O error)`

```bash
virsh -c qemu:///system list --all                 # state: paused
virsh -c qemu:///system domstate <dom> --reason    # paused (I/O error)
virsh -c qemu:///system domblkerror <dom>          # sticky; may still show the old error
journalctl -k | grep dio_verify                    # zed event at the same second?
virsh -c qemu:///system resume <dom>
```

After a long pause the guest clock lags. Sync it from the host through the
guest agent (the `hwclock` error at the end is harmless; the system time does
get set):

```bash
virsh -c qemu:///system domtime <dom> --now
virsh -c qemu:///system domtime <dom> --pretty     # should match `date -u`
```

If Omni still logs `x509: certificate has expired` for that node, Talos won't
rotate apid until its monotonic-clock timer fires. Reboot the guest with
`virsh reboot <dom> --mode agent`.

### Host OOM during a Talos rollout

The five guests need ~27.8G of the 31G host, and only fit thanks to KSM. A
guest rebooting into a new Talos build stops sharing pages with the others.
At the kernel's default scan rate KSM needed ~25min to catch up, and atlas
ran out of memory in the meantime. Now set in `hosts/atlas/configuration.nix`:

- `pages_to_scan=2000` via tmpfiles (ksmd costs about 1% of a core)
- `zramSwap` at 25% of RAM

Watch it during a rollout:

```bash
awk '/MemAvailable/' /proc/meminfo
awk '{printf "%.1fG\n", $1*4096/2^30}' /sys/kernel/mm/ksm/pages_sharing
journalctl -k --since -5min | grep "Killed process"
```

After an OOM, check the services nothing restarts on its own (they hit the
systemd start limit):

```bash
for c in omni pocket-id registry garage-s3; do sudo nixos-container run $c -- systemctl --failed; done
```

Omni needs pocket-id for OIDC at startup, and exits with `502 Bad Gateway`
when it's down. Restart pocket-id first, then
`systemctl reset-failed podman-omni && systemctl start podman-omni` inside
the omni container.

### Omni drain hangs on a Talos upgrade

From Talos 1.13 on, Omni cordons and drains through the Talos lifecycle API
before each node reboot. PDBs that never allow a disruption block it forever:

```
cordon/drain before reboot failed: failed to drain node
```

```bash
kubectl get pdb -A | awk 'NR==1 || $(NF-1)==0'
```

Single-instance CNPG clusters now set `enablePDB: false` (PR #72). Any new
single-instance `Cluster` needs the same. `immich-pg` (2 instances) keeps its
PDB; CNPG switches the primary over when its node is cordoned.

### etcd won't start: `walpb: crc mismatch`

The cluster has a single etcd member, so this takes the whole API down.

1. Look at the files (Talos API, read-only):
   ```bash
   omnictl talosconfig --cluster talos-prod-cluster ./talosconfig
   talosctl --talosconfig ./talosconfig -n <cp-node> logs etcd --tail 40
   talosctl --talosconfig ./talosconfig -n <cp-node> ls -l /var/lib/etcd/member/wal
   talosctl --talosconfig ./talosconfig -n <cp-node> ls -l /var/lib/etcd/member/snap
   talosctl --talosconfig ./talosconfig -n <cp-node> cp /var/lib/etcd ./etcd-backup
   ```
2. A WAL file is named `<seq>-<first-index>.wal`. If every entry in the
   corrupt file comes before the newest `.snap` index, the snapshot already
   holds its data. etcd still scans every WAL on startup, so moving the old
   files aside fixes it. Keep the files from the one containing the snapshot
   index onward, and keep the sequence contiguous. You can rehearse this
   against the backup copy with a local etcd.
3. Talos can't delete files over its API, so do it offline from atlas:
   ```bash
   virsh -c qemu:///system shutdown <cp-dom>
   sudo zfs snapshot rpool/vm-images@pre-etcd-fix
   sudo modprobe nbd max_part=16
   sudo qemu-nbd --connect=/dev/nbd0 /rpool/vm-images/<cp-dom>.qcow2
   lsblk -o NAME,FSTYPE,PARTLABEL /dev/nbd0          # EPHEMERAL is xfs
   sudo mount -t xfs /dev/nbd0p5 /mnt/talos-cp-ephemeral
   # etcd data lives at /mnt/talos-cp-ephemeral/lib/etcd/member/wal
   # move old WALs OUT of lib/etcd, e.g. to /mnt/talos-cp-ephemeral/etcd-wal-corrupt-<date>
   sudo umount /mnt/talos-cp-ephemeral && sudo qemu-nbd --disconnect /dev/nbd0
   virsh -c qemu:///system start <cp-dom>
   ```
4. If the corruption is newer than the latest snapshot, the last resort is
   Talos disaster recovery: wipe EPHEMERAL and
   `talosctl bootstrap --recover-from=<copied member/snap/db> --recover-skip-hash-check`.

### etcd backups (set up after this incident)

Omni takes hourly etcd snapshots of `talos-prod-cluster` and stores them in
garage:

- `--etcd-backup-s3` in `modules/container/omni.nix` turns on the S3 store.
- The store's bucket, endpoint and key live in Omni, not in the repo:
  resource `EtcdBackupS3Configs` id `etcd-backup-s3-conf`, bucket
  `omni-etcd-backups`, endpoint `https://s3.garage.rifqoi.com`, region
  `garage`, with the dedicated garage key `omni-etcd-backup`.
- `features.backupConfiguration.interval: 1h` in the cluster template sets
  the schedule.
- Retention: the bucket has a lifecycle rule `expire-etcd-backups-7d`
  (7 days; incomplete multipart uploads are dropped after 1 day). garage
  applies it in a daily sweep. At ~84MB per snapshot that's ~14GB.

```bash
omnictl get etcdbackup -l omni.sidero.dev/cluster=talos-prod-cluster
omnictl get etcdbackupoverallstatus -o yaml   # configurationerror should be ""
```

garage runs on atlas, so these backups cover etcd corruption, not losing
atlas. To restore, follow Omni's "restore etcd from backup" docs, which
create the cluster from a chosen `EtcdBackup` snapshot.

### Bumping nixpkgs on atlas

- Evaluate on the Mac, but don't build there: the Mac has no Linux builder,
  and deploy-rs builds on atlas (`remoteBuild = true`).
  ```bash
  nix eval --raw .#nixosConfigurations.atlas.config.system.build.toplevel.drvPath
  ```
- Update `sops-nix` together with `nixpkgs`. The 26.11 bump removed
  `buildGo125Module`, and the old sops-nix failed to evaluate.
- A live switch can migrate state forward that the old generation can't read:
  pocket-id migrated its DB during the failed 26.11 switch. A deploy-rs
  rollback is not always clean. Prefer `deploy --boot` plus a planned reboot
  for big jumps.
- Before rebooting atlas, shut the Talos VMs down yourself (workers first,
  control plane last) unless the running generation already has
  `virtualisation.libvirtd.onShutdown = "shutdown"`. The old default,
  `suspend`, saves ~28G of guest RAM and resumes the VMs with stale clocks
  and dropped iSCSI sessions.

### Pods stuck in ContainerCreating after a full atlas reboot

After the VMs come back, iSCSI attaches can time out for ~25min with
`timed out waiting for external-attacher of org.democratic-csi.zfs-generic-iscsi`.
The PVCs are still Bound and the targets on atlas are fine. The
democratic-csi controller just hasn't re-acquired its leader lease yet.
Check that before digging into iSCSI:

```bash
kubectl get events -A --sort-by=.lastTimestamp | grep -E "FailedAttach|LeaderElection" | tail
sudo targetcli ls /iscsi | grep -c linux-iscsi.k8s   # on atlas, should match the PV count
```

Once the attacher logs `became leader`, the attaches go through and the app
pods recover on their own (DB clients crash-loop until Postgres is up).

## Snapshots and backups from this incident

- `rpool/var@pre-omni-1.13.2`, `rpool/var@pre-26.11-reboot`
- `rpool/vm-images@pre-etcd-wal-fix`
- Control plane: `/var/etcd-wal-corrupt-20261107` (the moved WAL files)

Delete them once the cluster has been stable for a while.
