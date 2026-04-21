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
