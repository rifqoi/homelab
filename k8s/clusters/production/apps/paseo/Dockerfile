# Paseo's official image deliberately leaves provider CLIs out. Keep the
# provider layer small and build it on atlas, not on the workstation.
FROM ghcr.io/getpaseo/paseo:latest

USER root

RUN npm install -g \
    @openai/codex \
    @anthropic-ai/claude-code \
    opencode-ai

# The official entrypoint starts as root, prepares mounted volumes, and then
# drops the daemon and launched agents to the built-in paseo user (1000:1000).
