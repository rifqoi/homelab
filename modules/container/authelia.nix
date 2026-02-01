{
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./common.nix
  ];

  # Override/extend common configuration
  networking.defaultGateway = "192.168.31.1";
  networking.firewall.allowedTCPPorts = [22 9091]; # Authelia port

  # SOPS secrets for Authelia
  sops.secrets = {
    authelia_jwt_secret = {
      sopsFile = ../../secrets/secrets.yaml;
      owner = "authelia";
      mode = "0400";
    };
    authelia_session_secret = {
      sopsFile = ../../secrets/secrets.yaml;
      owner = "authelia";
      mode = "0400";
    };
    authelia_storage_encryption_key = {
      sopsFile = ../../secrets/secrets.yaml;
      owner = "authelia";
      mode = "0400";
    };
    authelia_oidc_hmac_secret = {
      sopsFile = ../../secrets/secrets.yaml;
      owner = "authelia";
      mode = "0400";
    };
    authelia_oidc_issuer_private_key = {
      sopsFile = ../../secrets/secrets.yaml;
      owner = "authelia";
      mode = "0400";
    };
  };

  services.authelia.instances.main = {
    enable = true;

    secrets = {
      jwtSecretFile = config.sops.secrets.authelia_jwt_secret.path;
      storageEncryptionKeyFile = config.sops.secrets.authelia_storage_encryption_key.path;
      oidcHmacSecretFile = config.sops.secrets.authelia_oidc_hmac_secret.path;
      oidcIssuerPrivateKeyFile = config.sops.secrets.authelia_oidc_issuer_private_key.path;
    };

    settings = {
      theme = "dark";
      default_2fa_method = "totp";

      server = {
        host = "0.0.0.0";
        port = 9091;
      };

      log = {
        level = "info";
        format = "text";
      };

      totp = {
        disable = false;
        issuer = "authelia.home.local";
      };

      authentication_backend = {
        file = {
          path = "/var/lib/authelia-main/users_database.yml";
          password = {
            algorithm = "argon2";
            argon2 = {
              variant = "argon2id";
              iterations = 3;
              memory = 65536;
              parallelism = 4;
              key_length = 32;
              salt_length = 16;
            };
          };
        };
      };

      access_control = {
        default_policy = "deny";
        rules = [
          {
            domain = ["*.home.local"];
            policy = "one_factor";
          }
          {
            domain = ["grafana.home.local"];
            policy = "bypass";
          }
        ];
      };

      session = {
        secret = "insecure_session_secret"; # Will be overridden by secret file
        name = "authelia_session";
        domain = "home.local";
        expiration = "1h";
        inactivity = "5m";
        remember_me_duration = "1M";
      };

      regulation = {
        max_retries = 3;
        find_time = "2m";
        ban_time = "5m";
      };

      storage = {
        local = {
          path = "/var/lib/authelia-main/db.sqlite3";
        };
      };

      notifier = {
        filesystem = {
          filename = "/var/lib/authelia-main/notification.txt";
        };
      };

      # Identity providers (OIDC)
      identity_providers = {
        oidc = {
          hmac_secret = "insecure_hmac_secret"; # Will be overridden by secret file
          issuer_private_key = ""; # Will be overridden by secret file

          access_token_lifespan = "1h";
          authorize_code_lifespan = "1m";
          id_token_lifespan = "1h";
          refresh_token_lifespan = "90m";

          enable_client_debug_messages = false;
          minimum_parameter_entropy = 8;

          clients = [
            {
              id = "grafana";
              description = "Grafana";
              secret = "$pbkdf2-sha512$310000$c8p78n7pUMln0jzvd4aK4Q$JNRBzwAo0ek5qKn50cFzzvE9RXV88h1wJn5KGiHrD0YKtZaR/nCb2CJPOsKaPK0hjf.9yHxzQGZziziccp6Yng";
              public = false;
              authorization_policy = "one_factor";
              redirect_uris = [
                "http://grafana.home.local:3000/login/generic_oauth"
              ];
              scopes = [
                "openid"
                "profile"
                "email"
                "groups"
              ];
              grant_types = [
                "authorization_code"
                "refresh_token"
              ];
              response_types = [
                "code"
              ];
            }
          ];
        };
      };
    };
  };

  # Create initial users file if it doesn't exist
  systemd.tmpfiles.rules = [
    "d /var/lib/authelia-main 0700 authelia authelia -"
  ];

  # Additional packages
  environment.systemPackages = with pkgs; [
    authelia
  ];

  users.users.root.password = "changeme";
}
