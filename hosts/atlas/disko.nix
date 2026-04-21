{...}: {
  disko.devices = {
    disk.main = {
      device = "/dev/nvme0n1";
      type = "disk";

      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
            };
          };

          zfs = {
            size = "100%";
            content = {
              type = "zfs";
              pool = "rpool";
            };
          };
        };
      };
    };

    zpool.rpool = {
      type = "zpool";

      options = {
        ashift = "12";
        autotrim = "on";
      };

      rootFsOptions = {
        compression = "zstd";
        acltype = "posixacl";
        xattr = "sa";
        relatime = "on";
        atime = "off";
      };

      datasets = {
        root = {
          type = "zfs_fs";
          options.mountpoint = "none";
        };

        "root/ROOT" = {
          type = "zfs_fs";
          options.mountpoint = "none";
        };

        "root/ROOT/nixos" = {
          type = "zfs_fs";
          mountpoint = "/";
          options = {
            mountpoint = "legacy";
            canmount = "noauto";
          };
        };

        nix = {
          type = "zfs_fs";
          mountpoint = "/nix";
          options = {
            mountpoint = "legacy";
            atime = "off";
          };
        };

        home = {
          type = "zfs_fs";
          mountpoint = "/home";
          options.mountpoint = "legacy";
        };

        var = {
          type = "zfs_fs";
          mountpoint = "/var";
          options.mountpoint = "legacy";
        };

        vm = {
          type = "zfs_fs";
          mountpoint = "/var/lib/vms";
          options = {
            mountpoint = "legacy";
            recordsize = "1M";
            atime = "off";
          };
        };

        postgresql = {
          type = "zfs_fs";
          mountpoint = "/var/lib/postgresql";
          options = {
            mountpoint = "legacy";
            recordsize = "16K";
            compression = "zstd";
            atime = "off";
            logbias = "latency";
            primarycache = "all";
          };
        };

        garage = {
          type = "zfs_fs";
          #  Bind this dataset to /var/lib/private/garage via a systemd mount unit.
          #  Because garage use DynamicUser=true and StateDirectory=garage
          #  the actual persistent data is stored in a private, highly
          #  restricted directory within /var/lib/private/
          mountpoint = "/var/lib/private/garage";
          options = {
            mountpoint = "legacy";
            recordsize = "1M";
            relatime = "off";
            compression = "zstd";
            xattr = "sa";
            acltype = "posixacl";
            primarycache = "metadata";
            secondarycache = "none";
            redundant_metadata = "most";
            checksum = "blake3";
            logbias = "throughput";
            sync = "disabled";
          };
        };

        registry = {
          type = "zfs_fs";
          mountpoint = "/var/lib/private/registry";
          options = {
            mountpoint = "legacy";
            recordsize = "1M";
            relatime = "off";
            compression = "zstd";
            xattr = "sa";
            acltype = "posixacl";
            primarycache = "metadata";
            secondarycache = "none";
          };
        };
      };
    };
  };
}
