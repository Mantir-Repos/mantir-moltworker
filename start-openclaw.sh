#!/bin/bash
# Startup script for OpenClaw in Cloudflare Sandbox
# This script:
# 1. Restores config/workspace/skills from R2 via rclone (if configured)
# 2. Runs openclaw onboard --non-interactive to configure from env vars
# 3. Patches config for features onboard doesn't cover (channels, gateway auth)
# 4. Starts a background sync loop (rclone, watches for file changes)
# 5. Starts the gateway

set -e

if pgrep -f "openclaw gateway" > /dev/null 2>&1; then
    echo "OpenClaw gateway is already running, exiting."
    exit 0
fi

CONFIG_DIR="/root/.openclaw"
CONFIG_FILE="$CONFIG_DIR/openclaw.json"
WORKSPACE_DIR="/root/clawd"
SKILLS_DIR="/root/clawd/skills"
RCLONE_CONF="/root/.config/rclone/rclone.conf"
LAST_SYNC_FILE="/tmp/.last-sync"

R2_RESTORED=false
WORKSPACE_RESTORED=false

echo "Config directory: $CONFIG_DIR"

mkdir -p "$CONFIG_DIR"

# ============================================================
# RCLONE SETUP
# ============================================================

r2_configured() {
    [ -n "$R2_ACCESS_KEY_ID" ] && [ -n "$R2_SECRET_ACCESS_KEY" ] && [ -n "$CF_ACCOUNT_ID" ]
}

R2_BUCKET="${R2_BUCKET_NAME:-moltbot-data}"

setup_rclone() {
    mkdir -p "$(dirname "$RCLONE_CONF")"
    cat > "$RCLONE_CONF" << EOF
[r2]
type = s3
provider = Cloudflare
access_key_id = $R2_ACCESS_KEY_ID
secret_access_key = $R2_SECRET_ACCESS_KEY
endpoint = https://${CF_ACCOUNT_ID}.r2.cloudflarestorage.com
acl = private
no_check_bucket = true
EOF
    touch /tmp/.rclone-configured
    echo "Rclone configured for bucket: $R2_BUCKET"
}

RCLONE_FLAGS="--transfers=16 --fast-list --s3-no-check-bucket"

# ============================================================
# RESTORE FROM R2
# ============================================================

if r2_configured; then
    setup_rclone

    echo "Checking R2 for existing backup..."
    # Check if R2 has an openclaw config backup
    if rclone ls "r2:${R2_BUCKET}/openclaw/openclaw.json" $RCLONE_FLAGS 2>/dev/null | grep -q openclaw.json; then
        echo "Restoring config from R2..."
        rclone copy "r2:${R2_BUCKET}/openclaw/" "$CONFIG_DIR/" $RCLONE_FLAGS -v 2>&1 || echo "WARNING: config restore failed with exit code $?"
        R2_RESTORED=true
        echo "Config restored"
    elif rclone ls "r2:${R2_BUCKET}/clawdbot/clawdbot.json" $RCLONE_FLAGS 2>/dev/null | grep -q clawdbot.json; then
        echo "Restoring from legacy R2 backup..."
        rclone copy "r2:${R2_BUCKET}/clawdbot/" "$CONFIG_DIR/" $RCLONE_FLAGS -v 2>&1 || echo "WARNING: legacy config restore failed with exit code $?"
        if [ -f "$CONFIG_DIR/clawdbot.json" ] && [ ! -f "$CONFIG_FILE" ]; then
            mv "$CONFIG_DIR/clawdbot.json" "$CONFIG_FILE"
        fi
        R2_RESTORED=true
        echo "Legacy config restored and migrated"
    else
        echo "No backup found in R2, starting fresh"
    fi

    # Restore workspace
    REMOTE_WS_COUNT=$(rclone ls "r2:${R2_BUCKET}/workspace/" $RCLONE_FLAGS 2>/dev/null | wc -l)
    if [ "$REMOTE_WS_COUNT" -gt 0 ]; then
        echo "Restoring workspace from R2 ($REMOTE_WS_COUNT files)..."
        mkdir -p "$WORKSPACE_DIR"
        rclone copy "r2:${R2_BUCKET}/workspace/" "$WORKSPACE_DIR/" $RCLONE_FLAGS -v 2>&1 || echo "WARNING: workspace restore failed with exit code $?"
        WORKSPACE_RESTORED=true
        echo "Workspace restored"
    fi

    # Restore skills
    REMOTE_SK_COUNT=$(rclone ls "r2:${R2_BUCKET}/skills/" $RCLONE_FLAGS 2>/dev/null | wc -l)
    if [ "$REMOTE_SK_COUNT" -gt 0 ]; then
        echo "Restoring skills from R2 ($REMOTE_SK_COUNT files)..."
        mkdir -p "$SKILLS_DIR"
        rclone copy "r2:${R2_BUCKET}/skills/" "$SKILLS_DIR/" $RCLONE_FLAGS -v 2>&1 || echo "WARNING: skills restore failed with exit code $?"
        echo "Skills restored"
    fi

    # Restore gog credentials (Google Workspace OAuth tokens + client credentials)
    REMOTE_GOG_COUNT=$(rclone ls "r2:${R2_BUCKET}/gog/" $RCLONE_FLAGS 2>/dev/null | wc -l)
    if [ "$REMOTE_GOG_COUNT" -gt 0 ]; then
        echo "Restoring gog credentials from R2..."
        mkdir -p /root/.config/gogcli
        rclone copy "r2:${R2_BUCKET}/gog/" /root/.config/gogcli/ $RCLONE_FLAGS 2>&1 || echo "WARNING: gog credentials restore failed"
        echo "gog credentials restored"
    fi
else
    echo "R2 not configured, starting fresh"
fi

# ============================================================
# ONBOARD (only if no config exists yet)
# ============================================================
if [ ! -f "$CONFIG_FILE" ]; then
    echo "No existing config found, running openclaw onboard..."

    AUTH_ARGS=""
    if [ -n "$CLOUDFLARE_AI_GATEWAY_API_KEY" ] && [ -n "$CF_AI_GATEWAY_ACCOUNT_ID" ] && [ -n "$CF_AI_GATEWAY_GATEWAY_ID" ]; then
        AUTH_ARGS="--auth-choice cloudflare-ai-gateway-api-key \
            --cloudflare-ai-gateway-account-id $CF_AI_GATEWAY_ACCOUNT_ID \
            --cloudflare-ai-gateway-gateway-id $CF_AI_GATEWAY_GATEWAY_ID \
            --cloudflare-ai-gateway-api-key $CLOUDFLARE_AI_GATEWAY_API_KEY"
    elif [ -n "$ANTHROPIC_API_KEY" ]; then
        AUTH_ARGS="--auth-choice apiKey --anthropic-api-key $ANTHROPIC_API_KEY"
    elif [ -n "$OPENAI_API_KEY" ]; then
        AUTH_ARGS="--auth-choice openai-api-key --openai-api-key $OPENAI_API_KEY"
    elif [ -n "$MINIMAX_API_KEY" ]; then
        # Use MiniMax key as Anthropic key for onboard (patcher will override provider config)
        AUTH_ARGS="--auth-choice apiKey --anthropic-api-key $MINIMAX_API_KEY"
    fi

    openclaw onboard --non-interactive --accept-risk \
        --mode local \
        $AUTH_ARGS \
        --gateway-port 18789 \
        --gateway-bind lan \
        --skip-channels \
        --skip-skills \
        --skip-health

    echo "Onboard completed"
else
    echo "Using existing config"
fi

# ============================================================
# APPLY BUNDLED SKILLS (always override R2 to keep image skills current)
# ============================================================
BUNDLED_SKILLS="/opt/openclaw-bundled-skills"
if [ -d "$BUNDLED_SKILLS" ]; then
    mkdir -p "$SKILLS_DIR"
    cp -r "$BUNDLED_SKILLS/." "$SKILLS_DIR/"
    echo "Bundled skills applied from image"
fi

# ============================================================
# APPLY CUSTOM IDENTITY FILES
# ============================================================
# Identity files (IDENTITY.md, SOUL.md, HEARTBEAT.md, etc.) live in the
# OpenClaw workspace directory (/root/.openclaw/workspace/), where OpenClaw
# auto-discovers and loads them into the system prompt.
# Note: This is different from WORKSPACE_DIR (/root/clawd/) which is for
# user workspace files. OpenClaw's onboard creates its workspace at
# ~/.openclaw/workspace/ by default.
IDENTITY_DEFAULTS="/opt/openclaw-identity"
OPENCLAW_WORKSPACE="$CONFIG_DIR/workspace"
if [ -d "$IDENTITY_DEFAULTS" ]; then
    mkdir -p "$OPENCLAW_WORKSPACE"
    echo "Applying custom identity files to $OPENCLAW_WORKSPACE..."
    for f in "$IDENTITY_DEFAULTS"/*.md; do
        [ -f "$f" ] || continue
        filename=$(basename "$f")
        cp "$f" "$OPENCLAW_WORKSPACE/$filename"
        echo "  Applied: $filename"
    done
fi

# ============================================================
# PATCH CONFIG (channels, gateway auth, trusted proxies)
# ============================================================
# openclaw onboard handles provider/model config, but we need to patch in:
# - Channel config (Telegram, Discord, Slack)
# - Gateway token auth
# - Trusted proxies for sandbox networking
# - Base URL override for legacy AI Gateway path
node << 'EOFPATCH'
const fs = require('fs');

const configPath = '/root/.openclaw/openclaw.json';
console.log('Patching config at:', configPath);
let config = {};

try {
    config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
} catch (e) {
    console.log('Starting with empty config');
}

config.gateway = config.gateway || {};
config.channels = config.channels || {};

// Gateway configuration
config.gateway.port = 18789;
config.gateway.mode = 'local';
config.gateway.trustedProxies = ['10.1.0.0'];

if (process.env.OPENCLAW_GATEWAY_TOKEN) {
    config.gateway.auth = config.gateway.auth || {};
    config.gateway.auth.token = process.env.OPENCLAW_GATEWAY_TOKEN;
}

// Fully reset controlUi to prevent stale/invalid keys from accumulating via R2.
// allowedOrigins is required when the gateway is on a non-loopback address.
const workerUrl = process.env.WORKER_URL ? process.env.WORKER_URL.replace(/\/+$/, '') : null;
config.gateway.controlUi = {};
if (workerUrl) {
    config.gateway.controlUi.allowedOrigins = [workerUrl];
}
if (process.env.OPENCLAW_DEV_MODE === 'true') {
    config.gateway.controlUi.allowInsecureAuth = true;
}

// Legacy AI Gateway base URL override:
// ANTHROPIC_BASE_URL is picked up natively by the Anthropic SDK,
// so we don't need to patch the provider config. Writing a provider
// entry without a models array breaks OpenClaw's config validation.

// AI Gateway model override (CF_AI_GATEWAY_MODEL=provider/model-id)
// Adds a provider entry for any AI Gateway provider and sets it as default model.
// Examples:
//   workers-ai/@cf/meta/llama-3.3-70b-instruct-fp8-fast
//   openai/gpt-4o
//   anthropic/claude-sonnet-4-5
if (process.env.CF_AI_GATEWAY_MODEL) {
    const raw = process.env.CF_AI_GATEWAY_MODEL;
    const slashIdx = raw.indexOf('/');
    const gwProvider = raw.substring(0, slashIdx);
    const modelId = raw.substring(slashIdx + 1);

    const accountId = process.env.CF_AI_GATEWAY_ACCOUNT_ID;
    const gatewayId = process.env.CF_AI_GATEWAY_GATEWAY_ID;
    const apiKey = process.env.CLOUDFLARE_AI_GATEWAY_API_KEY;

    let baseUrl;
    if (accountId && gatewayId) {
        baseUrl = 'https://gateway.ai.cloudflare.com/v1/' + accountId + '/' + gatewayId + '/' + gwProvider;
        if (gwProvider === 'workers-ai') baseUrl += '/v1';
    } else if (gwProvider === 'workers-ai' && process.env.CF_ACCOUNT_ID) {
        baseUrl = 'https://api.cloudflare.com/client/v4/accounts/' + process.env.CF_ACCOUNT_ID + '/ai/v1';
    }

    if (baseUrl && apiKey) {
        const api = gwProvider === 'anthropic' ? 'anthropic-messages' : 'openai-completions';
        const providerName = 'cf-ai-gw-' + gwProvider;

        config.models = config.models || {};
        config.models.providers = config.models.providers || {};
        config.models.providers[providerName] = {
            baseUrl: baseUrl,
            apiKey: apiKey,
            api: api,
            models: [{ id: modelId, name: modelId, contextWindow: 131072, maxTokens: 8192 }],
        };
        config.agents = config.agents || {};
        config.agents.defaults = config.agents.defaults || {};
        config.agents.defaults.model = { primary: providerName + '/' + modelId };
        console.log('AI Gateway model override: provider=' + providerName + ' model=' + modelId + ' via ' + baseUrl);
    } else {
        console.warn('CF_AI_GATEWAY_MODEL set but missing required config (account ID, gateway ID, or API key)');
    }
}

// MiniMax provider configuration (Anthropic-compatible API)
if (process.env.MINIMAX_API_KEY) {
    const modelId = process.env.MINIMAX_MODEL || 'MiniMax-M2.5';

    config.models = config.models || {};
    config.models.providers = config.models.providers || {};
    config.models.providers['minimax'] = {
        baseUrl: 'https://api.minimax.io/anthropic',
        apiKey: process.env.MINIMAX_API_KEY,
        api: 'anthropic-messages',
        models: [{ id: modelId, name: modelId, contextWindow: 204800, maxTokens: 8192 }],
    };
    config.agents = config.agents || {};
    config.agents.defaults = config.agents.defaults || {};
    config.agents.defaults.model = { primary: 'minimax/' + modelId };
    console.log('MiniMax provider configured: model=' + modelId);
}

// Telegram configuration
// Overwrite entire channel object to drop stale keys from old R2 backups
// that would fail OpenClaw's strict config validation (see #47)
if (process.env.TELEGRAM_BOT_TOKEN) {
    const dmPolicy = process.env.TELEGRAM_DM_POLICY || 'pairing';
    config.channels.telegram = {
        botToken: process.env.TELEGRAM_BOT_TOKEN,
        enabled: true,
        dmPolicy: dmPolicy,
    };
    if (process.env.TELEGRAM_DM_ALLOW_FROM) {
        config.channels.telegram.allowFrom = process.env.TELEGRAM_DM_ALLOW_FROM.split(',');
    } else if (dmPolicy === 'open') {
        config.channels.telegram.allowFrom = ['*'];
    }
}

// Discord configuration
// Discord uses a nested dm object: dm.policy, dm.allowFrom (per DiscordDmConfig)
if (process.env.DISCORD_BOT_TOKEN) {
    const dmPolicy = process.env.DISCORD_DM_POLICY || 'pairing';
    const dm = { policy: dmPolicy };
    if (dmPolicy === 'open') {
        dm.allowFrom = ['*'];
    }
    config.channels.discord = {
        token: process.env.DISCORD_BOT_TOKEN,
        enabled: true,
        dm: dm,
    };
}

// Slack configuration (HTTP Events API mode — no persistent socket, container can sleep)
if (process.env.SLACK_BOT_TOKEN && process.env.SLACK_SIGNING_SECRET) {
    const groupPolicy = process.env.SLACK_GROUP_POLICY || 'open';
    const requireMention = process.env.SLACK_REQUIRE_MENTION === 'true';
    const historyLimit = parseInt(process.env.SLACK_HISTORY_LIMIT, 10) || 10;
    config.channels.slack = {
        mode: 'http',
        botToken: process.env.SLACK_BOT_TOKEN,
        signingSecret: process.env.SLACK_SIGNING_SECRET,
        webhookPath: '/slack/events',
        enabled: true,
        groupPolicy: groupPolicy,
        requireMention: requireMention,
        historyLimit: historyLimit,
    };
    // Enable Slack plugin
    config.plugins = config.plugins || {};
    config.plugins.entries = config.plugins.entries || {};
    config.plugins.entries.slack = { enabled: true };
    console.log('Slack configured (HTTP mode): groupPolicy=' + groupPolicy + ' requireMention=' + requireMention);
}

// Mention patterns for group chats (e.g. "jeff,jeff barnes,@jeff,hey jeff")
if (process.env.MENTION_PATTERNS) {
    const patterns = process.env.MENTION_PATTERNS.split(',').map(p => p.trim());
    config.messages = config.messages || {};
    config.messages.ackReactionScope = 'group-mentions';
    config.messages.groupChat = config.messages.groupChat || {};
    config.messages.groupChat.mentionPatterns = patterns;
    config.messages.groupChat.historyLimit = config.messages.groupChat.historyLimit || 10;
    console.log('Mention patterns configured: ' + patterns.join(', '));
}

// Notion skill configuration
if (process.env.NOTION_API_KEY) {
    config.skills = config.skills || {};
    config.skills.entries = config.skills.entries || {};
    config.skills.entries.notion = { apiKey: process.env.NOTION_API_KEY };
    console.log('Notion skill configured');
}

// Cloudflare Browser Rendering profile
// Requires CDP_SECRET and WORKER_URL secrets set via wrangler secret put
if (process.env.CDP_SECRET && process.env.WORKER_URL) {
    const workerUrl = process.env.WORKER_URL.replace(/\/+$/, '');
    config.browser = config.browser || {};
    config.browser.profiles = config.browser.profiles || {};
    config.browser.profiles.cloudflare = {
        cdpUrl: workerUrl + '/cdp?secret=' + encodeURIComponent(process.env.CDP_SECRET),
        color: '#F48120'
    };
    console.log('Browser cloudflare profile configured');
}

fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
console.log('Configuration patched successfully');
EOFPATCH

# ============================================================
# BACKGROUND SYNC LOOP
# ============================================================
if r2_configured; then
    echo "Starting background R2 sync loop..."
    (
        MARKER=/tmp/.last-sync-marker
        LOGFILE=/tmp/r2-sync.log
        touch "$MARKER"

        while true; do
            sleep 300

            CHANGED=/tmp/.changed-files
            {
                find "$CONFIG_DIR" -newer "$MARKER" -type f -printf '%P\n' 2>/dev/null
                find "$WORKSPACE_DIR" -newer "$MARKER" \
                    -not -path '*/node_modules/*' \
                    -not -path '*/.git/*' \
                    -type f -printf '%P\n' 2>/dev/null
            } > "$CHANGED"

            COUNT=$(wc -l < "$CHANGED" 2>/dev/null || echo 0)

            if [ "$COUNT" -gt 0 ]; then
                echo "[sync] Uploading changes ($COUNT files) at $(date)" >> "$LOGFILE"
                rclone sync "$CONFIG_DIR/" "r2:${R2_BUCKET}/openclaw/" \
                    $RCLONE_FLAGS --exclude='*.lock' --exclude='*.log' --exclude='*.tmp' --exclude='.git/**' 2>> "$LOGFILE"
                if [ -d "$WORKSPACE_DIR" ]; then
                    rclone sync "$WORKSPACE_DIR/" "r2:${R2_BUCKET}/workspace/" \
                        $RCLONE_FLAGS --exclude='skills/**' --exclude='.git/**' --exclude='node_modules/**' 2>> "$LOGFILE"
                fi
                if [ -d "$SKILLS_DIR" ]; then
                    rclone sync "$SKILLS_DIR/" "r2:${R2_BUCKET}/skills/" \
                        $RCLONE_FLAGS 2>> "$LOGFILE"
                fi
                if [ -d /root/.config/gogcli ]; then
                    rclone sync /root/.config/gogcli/ "r2:${R2_BUCKET}/gog/" \
                        $RCLONE_FLAGS 2>> "$LOGFILE"
                fi
                date -Iseconds > "$LAST_SYNC_FILE"
                touch "$MARKER"
                echo "[sync] Complete at $(date)" >> "$LOGFILE"
            fi
        done
    ) &
    echo "Background sync loop started (PID: $!)"
fi

# ============================================================
# GOG (GOOGLE WORKSPACE) CONFIGURATION
# ============================================================
# Use file-based keyring — no OS keychain available in container
export GOG_KEYRING_BACKEND=file
if [ -n "$GOG_KEYRING_PASSWORD" ]; then
    export GOG_KEYRING_PASSWORD="$GOG_KEYRING_PASSWORD"
fi
if [ -n "$GOG_ACCOUNT" ]; then
    export GOG_ACCOUNT="$GOG_ACCOUNT"
fi

# Store the OAuth Desktop app client credentials (client_secret JSON from GCP).
# GOG_OAUTH_CREDENTIALS is the base64-encoded client_secret_*.json file.
# This registers the OAuth client with gog — the actual refresh token comes
# from the keyring files restored from R2 above (written by a one-time local auth).
if [ -n "$GOG_OAUTH_CREDENTIALS" ]; then
    echo "Configuring gog OAuth client credentials..."
    mkdir -p /root/.config/gogcli
    echo "$GOG_OAUTH_CREDENTIALS" | base64 -d > /tmp/gog-credentials.json
    chmod 600 /tmp/gog-credentials.json
    gog auth credentials /tmp/gog-credentials.json \
        && echo "gog OAuth client configured" \
        || echo "WARNING: gog auth credentials failed"
    rm -f /tmp/gog-credentials.json
fi

# ============================================================
# START GATEWAY
# ============================================================
echo "Starting OpenClaw Gateway..."
echo "Gateway will be available on port 18789"

rm -f /tmp/openclaw-gateway.lock 2>/dev/null || true
rm -f "$CONFIG_DIR/gateway.lock" 2>/dev/null || true

echo "Dev mode: ${OPENCLAW_DEV_MODE:-false}"

if [ -n "$OPENCLAW_GATEWAY_TOKEN" ]; then
    echo "Starting gateway with token auth..."
    exec openclaw gateway --port 18789 --verbose --allow-unconfigured --bind lan --token "$OPENCLAW_GATEWAY_TOKEN"
else
    echo "Starting gateway with device pairing (no token)..."
    exec openclaw gateway --port 18789 --verbose --allow-unconfigured --bind lan
fi
