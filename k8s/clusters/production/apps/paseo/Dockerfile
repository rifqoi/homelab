# Paseo's official image deliberately leaves provider CLIs out. Keep the
# provider layer small and build it on atlas, not on the workstation.
FROM ghcr.io/getpaseo/paseo:latest

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        iproute2 \
        openconnect \
        vpnc-scripts \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g \
    @openai/codex \
    @anthropic-ai/claude-code \
    opencode-ai

# Install Devin CLI into an image-owned location so the /home/paseo PVC cannot
# hide the binary at runtime. The installer verifies the downloaded bundle
# against Devin's published manifest checksum.
RUN set -eux; \
    devin_home="$(mktemp -d)"; \
    mkdir -p /opt/devin; \
    curl -fsSL https://cli.devin.ai/install.sh -o /tmp/devin-install.sh; \
    sed -i '/"\$VERSION_DIR\/bin\/\$COMPILED_BIN_NAME" setup/d' /tmp/devin-install.sh; \
    HOME="$devin_home" XDG_DATA_HOME=/opt/devin \
      bash /tmp/devin-install.sh; \
    ln -s /opt/devin/devin/cli/_versions/current/bin/devin /usr/local/bin/devin; \
    chmod -R a+rX /opt/devin; \
    rm -rf "$devin_home" /tmp/devin-install.sh

# The official entrypoint starts as root, prepares mounted volumes, and then
# drops the daemon and launched agents to the built-in paseo user (1000:1000).
