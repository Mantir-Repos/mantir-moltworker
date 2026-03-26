FROM docker.io/cloudflare/sandbox:0.7.0

# Build: HTTP Events API mode (no keep-alive cron)
# Install Node.js 22 (required by OpenClaw) and rclone (for R2 persistence)
# The base image has Node 20, we need to replace it with Node 22
# Using direct binary download for reliability
ENV NODE_VERSION=22.13.1
RUN ARCH="$(dpkg --print-architecture)" \
    && case "${ARCH}" in \
         amd64) NODE_ARCH="x64" ;; \
         arm64) NODE_ARCH="arm64" ;; \
         *) echo "Unsupported architecture: ${ARCH}" >&2; exit 1 ;; \
       esac \
    && apt-get update && apt-get install -y xz-utils ca-certificates rclone \
    && curl -fsSLk https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz -o /tmp/node.tar.xz \
    && tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 \
    && rm /tmp/node.tar.xz \
    && node --version \
    && npm --version

# Install pnpm globally
RUN npm install -g pnpm

# Install ws for cloudflare-browser skill scripts (screenshot.js, video.js, cdp-client.js)
RUN npm install -g ws

# Install OpenClaw (formerly clawdbot/moltbot)
# Pin to specific version for reproducible builds
RUN npm install -g openclaw@2026.2.17 \
    && openclaw --version

# Install gog CLI (Google Workspace: Gmail, Calendar, Drive, Contacts, Sheets, Docs)
# Uses file-based keyring backend (no OS keychain needed) — credentials stored in R2
RUN ARCH="$(dpkg --print-architecture)" \
    && case "${ARCH}" in \
         amd64) GOG_ARCH="amd64" ;; \
         arm64) GOG_ARCH="arm64" ;; \
         *) echo "Unsupported architecture: ${ARCH}" >&2; exit 1 ;; \
       esac \
    && GOG_VERSION=0.11.0 \
    && curl -fsSL "https://github.com/steipete/gogcli/releases/download/v${GOG_VERSION}/gogcli_${GOG_VERSION}_linux_${GOG_ARCH}.tar.gz" \
       -o /tmp/gogcli.tar.gz \
    && tar -xzf /tmp/gogcli.tar.gz -C /tmp \
    && install -m 0755 /tmp/gog /usr/local/bin/gog \
    && rm -f /tmp/gogcli.tar.gz /tmp/gog \
    && gog --version

# Create OpenClaw directories
# Legacy .clawdbot paths are kept for R2 backup migration
RUN mkdir -p /root/.openclaw \
    && mkdir -p /root/clawd \
    && mkdir -p /root/clawd/skills

# Copy startup script
# Build cache bust: 2026-02-17-v32-openclaw-update
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
