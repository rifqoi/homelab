{
  pkgs,
  sops-nix,
  config,
  ...
}: let
  acmeCertFolder = "/var/lib/acme";
  defaultBindMounts = {
    "/var/lib/sops-nix/key.txt" = {
      hostPath = "/var/lib/sops-nix/keys-container.txt";
      isReadOnly = true;
    };
    "${acmeCertFolder}" = {
      hostPath = acmeCertFolder;
      isReadOnly = false;
    };
  };

  openwrtHost = "192.168.31.1";
  openwrtUser = "root";
  openwrtPasswordFile = config.sops.secrets.openwrt_password.path;

  mkContainer = {
    hostBridge,
    localAddress,
    configModule,
    extraBindMounts ? {},
    autoStart ? true,
    privateNetwork ? true,
    isDockerContainer ? false,
    enableTun ? false,
    forwardPorts ? [],
    dnsRecords ? [],
  }: {
    inherit autoStart privateNetwork hostBridge localAddress;
    bindMounts = defaultBindMounts // extraBindMounts;
    config = configModule;
    specialArgs = {inherit sops-nix;};
    forwardPorts = forwardPorts;
    enableTun = enableTun;
    extraFlags = pkgs.lib.mkIf isDockerContainer [
      "--system-call-filter=keyctl"
      "--system-call-filter=bpf"
    ];
  };

  containerDefs = {
    blocky-dns = {
      hostBridge = "br31";
      localAddress = "192.168.31.11/24";
      configModule = ./blocky-dns.nix;
    };
    grafana = {
      hostBridge = "br31";
      localAddress = "192.168.31.12/24";
      configModule = ./grafana.nix;
      dnsRecords = [
        {
          name = "grafana.rifqoi.com";
          ip = "192.168.31.12";
        }
      ];
    };
    nginx = {
      hostBridge = "br31";
      localAddress = "192.168.31.30/24";
      configModule = ./nginx.nix;
    };
    pocket-id = {
      hostBridge = "br31";
      localAddress = "192.168.31.13/24";
      configModule = ./pocket-id.nix;
      extraBindMounts = {
        "/var/lib/pocket-id" = {
          hostPath = "/var/lib/pocket-id";
          isReadOnly = false;
        };
      };
      dnsRecords = [
        {
          name = "pocket.rifqoi.com";
          ip = "192.168.31.13";
        }
      ];
    };
    registry = {
      hostBridge = "br31";
      localAddress = "192.168.31.14/24";
      configModule = ./registry.nix;
      extraBindMounts = {
        "/var/lib/registry" = {
          hostPath = "/var/lib/registry";
          isReadOnly = false;
        };
      };
      dnsRecords = [
        {
          name = "registry.rifqoi.com";
          ip = "192.168.31.14";
        }
      ];
    };
    omni = {
      hostBridge = "br31";
      localAddress = "192.168.31.20/24";
      configModule = ./omni.nix;
      isDockerContainer = true;
      enableTun = true;
      forwardPorts = [
        {
          containerPort = 8090;
          hostPort = 8090;
          protocol = "tcp";
        }
      ];
      extraBindMounts = {
        "/var/lib/omni" = {
          hostPath = "/var/lib/omni";
          isReadOnly = false;
        };
        "/var/run/libvirt/libvirt-sock" = {
          hostPath = "/var/run/libvirt/libvirt-sock";
          isReadOnly = false;
        };
      };
      dnsRecords = [
        {
          name = "omni.rifqoi.com";
          ip = "192.168.31.20";
        }
        {
          name = "omni2omni.rifqoi.com";
          ip = "192.168.31.20";
        }
      ];
    };
  };

  allDnsRecords = pkgs.lib.flatten (
    pkgs.lib.mapAttrsToList (_: cfg: cfg.dnsRecords or []) containerDefs
  );

  uciRpc = let
    records = builtins.toJSON allDnsRecords;
  in
    pkgs.writeShellScript "openwrt-dns-upsert" ''
      CURL="${pkgs.curl}/bin/curl"
      JQ="${pkgs.jq}/bin/jq"
      BASE="http://${openwrtHost}/cgi-bin/luci/rpc"
      if [ -f "$CREDENTIALS_DIRECTORY/openwrt_password" ]; then
        PASSWORD=$(cat "$CREDENTIALS_DIRECTORY/openwrt_password")
      else
        echo "ERROR: openwrt_password credential not found in $CREDENTIALS_DIRECTORY" >&2
        exit 1
      fi

      TOKEN=$($CURL -sf -X POST "$BASE/auth" \
        -H 'Content-Type: application/json' \
        -d "{\"method\":\"login\",\"params\":[\"${openwrtUser}\",\"$PASSWORD\"],\"id\":1}" \
        | $JQ -r '.result')

      if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        echo "ERROR: Failed to authenticate with OpenWRT"
        exit 1
      fi

      rpc() {
        $CURL -sf -X POST "$BASE/uci?auth=$TOKEN" \
          -H 'Content-Type: application/json' \
          -d "$1"
      }

      echo '${records}' | $JQ -c '.[]' | while read -r record; do
        NAME=$(echo "$record" | $JQ -r '.name')
        IP=$(echo "$record" | $JQ -r '.ip')

        echo "Deleting existing record for $NAME..."
        rpc "{\"method\":\"get_all\",\"params\":[\"dhcp\"],\"id\":1}" \
          | $JQ -r ".result | to_entries[]
              | select(.value.name==\"$NAME\" and .value[\".type\"]==\"domain\")
              | .key" \
          | while read -r idx; do
              rpc "{\"method\":\"delete\",\"params\":[\"dhcp\",\"$idx\"],\"id\":1}"
            done

        echo "Adding DNS record: $NAME -> $IP"
        rpc '{"method":"add","params":["dhcp","domain"],"id":1}'
        rpc "{\"method\":\"set\",\"params\":[\"dhcp\",\"@domain[-1]\",\"name\",\"$NAME\"],\"id\":1}"
        rpc "{\"method\":\"set\",\"params\":[\"dhcp\",\"@domain[-1]\",\"ip\",\"$IP\"],\"id\":1}"
      done

      rpc '{"method":"commit","params":["dhcp"],"id":1}'
      echo "DNS records committed."
    '';
in {
  sops.secrets.openwrt_password = {
    sopsFile = ../../secrets/secrets.yaml;
    mode = "0400";
  };

  users.users.nginx = {
    isSystemUser = true;
    group = "nginx";
    uid = 10001;
    extraGroups = ["acme"];
  };
  users.groups.nginx = {gid = 10001;};
  systemd.tmpfiles.rules = ["d /var/lib/registry 0755 root root -"];

  systemd.services.openwrtDnsRecords = {
    description = "Upsert DNS records into OpenWRT";
    # No wantedBy here!
    after = ["sops-nix.service" "network-online.target"];
    wants = ["network-online.target"];
    bindsTo = ["trigger-openwrt-upsert.path"];

    serviceConfig = {
      Type = "oneshot";
      LoadCredential = ["openwrt_password:${config.sops.secrets.openwrt_password.path}"];
      ExecStart = uciRpc;
      RemainAfterExit = false;
    };
  };

  systemd.paths.trigger-openwrt-upsert = {
    description = "Watch for system configuration changes";
    pathConfig = {
      PathChanged = "/run/current-system";
    };
    wantedBy = ["multi-user.target"]; # The WATCHER starts on boot, not the script
  };

  containers = pkgs.lib.mapAttrs (_: cfg: mkContainer cfg) containerDefs;
}
