FROM registry.cloudflare.com/6644a20cd7020bf5625ea250ee029ff7/moltbot-sandbox-sandbox:ea99d41d

# Build: HTTP Events API mode (layered on top of existing image to avoid re-pushing 1.9GB openclaw layer)
# Only the files below change — all Node/OpenClaw/gog layers are inherited from the base

# Copy startup script (updated for HTTP Events API mode, 300s R2 sync)
COPY start-openclaw.sh /usr/local/bin/start-openclaw.sh
RUN chmod +x /usr/local/bin/start-openclaw.sh

# Copy custom identity files to staging directory
# These are applied on first boot (after onboard), but R2 restores take priority
COPY identity/ /opt/openclaw-identity/

# Copy bundled skills to staging — applied after R2 restore in start-openclaw.sh
# (prevents R2 backups of old skill versions from overriding image updates)
COPY skills/ /opt/openclaw-bundled-skills/

# Set working directory
WORKDIR /root/clawd

# Expose the gateway port
EXPOSE 18789
