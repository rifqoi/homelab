# OpenWRT Configuration for Router
# Deploy with: nix run .#packages.x86_64-linux.openwrt.targets.router
{
  openwrt.router = {
    # Deploy configuration
    deploy = {
      host = "192.168.11.1";
      sshConfig = {
        Port = 22;
        StrictHostKeyChecking = false;
      };
      user = "root";
      rebootAllowance = 60;
      rollbackTimeout = 90;
      reloadServiceWait = 10;
    };

    # Install additional packages
    packages = [
      "htop"
      "tcpdump"
      "ip-full"
      "curl"
      "tailscale"
      "prometheus-node-exporter-lua"
      "sqm-scripts"
      "luci-app-sqm"
    ];

    # Root password configuration (use hashed password)
    # users.root.hashedPassword = "$y$j9T$7kyoRqhthgY01SBHfCAUz0$Fc/nQP7onR5WHcJ0/3GE6kcb9c.93Y0WfEwoQSR0pa.";

    # SSH authorized keys
    etc."dropbear/authorized_keys".text = ''
      # Add your SSH public keys here
    '';

    # Retain UCI configurations that are defaults/system configs
    uci.retain = [
      "rpcd" # Keep default authentication config
      "ucitrack" # Keep default system tracking
      "wireless" # Keep WiFi configuration (radios + SSIDs)
      "luci" # Keep LuCI web interface configuration
    ];

    # UCI settings
    uci.settings = {
      # System configuration
      system = {
        system = [
          {
            hostname = "openwrt";
            timezone = "WIB-7";
            zonename = "Asia/Jakarta";
            ttylogin = 0;
            log_size = 64;
            urandom_seed = 0;
            compat_version = "1.1";
            log_proto = "udp";
            conloglevel = 8;
            cronloglevel = 5;
          }
        ];

        # NTP configuration
        timeserver.ntp = {
          server = [
            "0.openwrt.pool.ntp.org"
            "1.openwrt.pool.ntp.org"
            "2.openwrt.pool.ntp.org"
            "3.openwrt.pool.ntp.org"
          ];
        };
      };

      # Network configuration (MINIMAL TEST)
      network = {
        # Loopback interface
        interface.loopback = {
          device = "lo";
          proto = "static";
          ipaddr = "127.0.0.1";
          netmask = "255.0.0.0";
        };

        # Global network settings
        globals.globals = {
          ula_prefix = "fdbb:7e3e:4c23::/48";
          packet_steering = 1;
        };

        # LAN interface (simplified - no VLANs)
        interface.lan = {
          device = "br-lan";
          proto = "static";
          ipaddr = "192.168.11.1";
          netmask = "255.255.255.0";
          ip6assign = 60;
        };

        # WAN interface
        interface.wan = {
          device = "wan";
          proto = "dhcp";
        };

        interface.wan6 = {
          device = "wan";
          proto = "dhcpv6";
        };
      };

      # DHCP and DNS configuration (MINIMAL)
      dhcp = {
        dnsmasq = [
          {
            domainneeded = 1;
            localise_queries = 1;
            local = "/lan/";
            domain = "lan";
            expandhosts = 1;
            cachesize = 1000;
            authoritative = 1;
            readethers = 1;
            leasefile = "/tmp/dhcp.leases";
            resolvfile = "/tmp/resolv.conf.d/resolv.conf.auto";
            localservice = 1;
          }
        ];

        dhcp.lan = {
          interface = "lan";
          start = 100;
          limit = 150;
          leasetime = "12h";
        };

        dhcp.wan = {
          interface = "wan";
          ignore = 1;
        };

        odhcpd.odhcpd = {
          maindhcp = 0;
          leasefile = "/tmp/hosts/odhcpd";
          leasetrigger = "/usr/sbin/odhcpd-update";
          loglevel = 4;
        };
      };

      # Dropbear SSH configuration
      dropbear.dropbear = [
        {
          PasswordAuth = "on";
          RootPasswordAuth = "on";
          Port = 22;
        }
      ];

      # Firewall configuration (MINIMAL)
      firewall = {
        defaults = [
          {
            input = "REJECT";
            output = "ACCEPT";
            forward = "REJECT";
            synflood_protect = 1;
          }
        ];

        zone = [
          # LAN Zone
          {
            name = "lan";
            input = "ACCEPT";
            output = "ACCEPT";
            forward = "ACCEPT";
            network = "lan";
          }
          # WAN Zone
          {
            name = "wan";
            input = "REJECT";
            output = "ACCEPT";
            forward = "REJECT";
            masq = 1;
            mtu_fix = 1;
            network = ["wan" "wan6"];
          }
        ];

        forwarding = [
          {
            src = "lan";
            dest = "wan";
          }
        ];

        rule = [
          {
            name = "Allow-DHCP-Renew";
            src = "wan";
            proto = "udp";
            dest_port = 68;
            target = "ACCEPT";
            family = "ipv4";
          }
          {
            name = "Allow-Ping";
            src = "wan";
            proto = "icmp";
            icmp_type = "echo-request";
            family = "ipv4";
            target = "ACCEPT";
          }
          {
            name = "Allow-IGMP";
            src = "wan";
            proto = "igmp";
            family = "ipv4";
            target = "ACCEPT";
          }
        ];
      };
    };
  };
}
