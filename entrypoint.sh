#!/bin/bash
# OpenClaw Gateway Entrypoint
# This script ensures the gateway can start with proper configuration

set -e

# Create config directory if it doesn't exist
mkdir -p /data/.openclaw

# Handle gateway token - persist across restarts
# Try to use provided env var first
GATEWAY_TOKEN="$OPENCLAW_GATEWAY_TOKEN"

# If no env var, try to load from existing config
if [ -z "$GATEWAY_TOKEN" ] && [ -f "/data/.openclaw/openclaw.json" ]; then
    GATEWAY_TOKEN=$(grep -o '"token"[[:space:]]*:[[:space:]]*"[^"]*"' /data/.openclaw/openclaw.json | head -1 | cut -d'"' -f4)
fi

# If still empty, generate a new token
if [ -z "$GATEWAY_TOKEN" ]; then
    GATEWAY_TOKEN=$(openssl rand -hex 32)
    echo "Generated new gateway token: $GATEWAY_TOKEN"
fi

export OPENCLAW_GATEWAY_TOKEN="$GATEWAY_TOKEN"

# Build trusted proxies JSON array from environment variable
# Default includes common Docker gateway IPs and ranges
DEFAULT_PROXIES="loopback,linklocal,uniquelocal,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
TRUSTED_PROXIES=${OPENCLAW_TRUSTED_PROXIES:-$DEFAULT_PROXIES}

# Convert comma-separated list to JSON array
PROXIES_JSON=$(echo "$TRUSTED_PROXIES" | sed 's/,/", "/g' | sed 's/^/["/' | sed 's/$/"]/')
echo "Trusted proxies: $PROXIES_JSON"

# Determine default model based on available API keys
DEFAULT_MODEL="anthropic/claude-sonnet-4-5"  # fallback
if [ -n "$ANTHROPIC_API_KEY" ] || [ -n "$OPENCLAW_ANTHROPIC_SETUP_TOKEN" ]; then
    DEFAULT_MODEL="anthropic/claude-sonnet-4-5"
elif [ -n "$GEMINI_API_KEY" ]; then
    DEFAULT_MODEL="google/gemini-3-pro-preview"
elif [ -n "$OPENAI_API_KEY" ]; then
    DEFAULT_MODEL="openai/gpt-4o"
elif [ -n "$OPENROUTER_API_KEY" ]; then
    DEFAULT_MODEL="openrouter/anthropic/claude-sonnet-4"
fi
echo "Default model: $DEFAULT_MODEL"

# Always regenerate config from environment variables to ensure
# current settings are applied (env vars are the source of truth)
SHOULD_REGENERATE=true
if [ -f "/data/.openclaw/openclaw.json" ]; then
    echo "Regenerating configuration from environment variables..."
else
    echo "No existing config found, creating new configuration"
fi

if [ "$SHOULD_REGENERATE" = true ]; then
    echo "Generating OpenClaw configuration..."

    # Build channels object dynamically
    CHANNELS_JSON="{"
    FIRST_CHANNEL=true

    # Add WhatsApp (always included)
    if [ "$FIRST_CHANNEL" = false ]; then
        CHANNELS_JSON="$CHANNELS_JSON,"
    fi
    CHANNELS_JSON="$CHANNELS_JSON\"whatsapp\":{\"enabled\":true,\"allowFrom\":[],\"groups\":{\"*\":{\"requireMention\":true}}}"
    FIRST_CHANNEL=false

    # Add Telegram if token is provided
    if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
        CHANNELS_JSON="$CHANNELS_JSON,\"telegram\":{\"enabled\":true,\"botToken\":\"$TELEGRAM_BOT_TOKEN\",\"groups\":{\"*\":{\"requireMention\":true}}}"
        echo "Configured Telegram channel"
    fi

    # Add Discord if token is provided
    if [ -n "$DISCORD_BOT_TOKEN" ]; then
        CHANNELS_JSON="$CHANNELS_JSON,\"discord\":{\"enabled\":true,\"token\":\"$DISCORD_BOT_TOKEN\",\"dm\":{\"policy\":\"pairing\"}}"
        echo "Configured Discord channel"
    fi

    # Add Slack if both tokens are provided
    if [ -n "$SLACK_BOT_TOKEN" ] && [ -n "$SLACK_APP_TOKEN" ]; then
        CHANNELS_JSON="$CHANNELS_JSON,\"slack\":{\"enabled\":true,\"botToken\":\"$SLACK_BOT_TOKEN\",\"appToken\":\"$SLACK_APP_TOKEN\",\"dm\":{\"policy\":\"pairing\"}}"
        echo "Configured Slack channel"
    fi

    CHANNELS_JSON="$CHANNELS_JSON}"

    # Create the complete config
    cat > /data/.openclaw/openclaw.json << EOF
{
  "agent": {
    "model": "${DEFAULT_MODEL}",
    "workspace": "/data/openclaw"
  },
  "gateway": {
    "bind": "${OPENCLAW_GATEWAY_BIND:-lan}",
    "port": ${OPENCLAW_GATEWAY_PORT:-18789},
    "auth": {
      "mode": "token",
      "token": "${OPENCLAW_GATEWAY_TOKEN}"
    },
    "trustedProxies": ${PROXIES_JSON},
    "controlUi": {
      "allowInsecureAuth": true
    }
  },
  "channels": ${CHANNELS_JSON},
  "browser": {
    "enabled": ${OPENCLAW_BROWSER_ENABLED:-true},
    "controlUrl": "${OPENCLAW_BROWSER_URL:-http://openclaw-browser:9222}"
  },
  "agents": {
    "defaults": {
      "workspace": "/data/openclaw"
    }
  }
}
EOF
    echo "Config written to /data/.openclaw/openclaw.json"
else
    echo "Using existing configuration from /data/.openclaw/openclaw.json"
fi

# Setup authentication using OpenClaw's native methods
echo "Configuring authentication..."

# Create agent directory structure (where OpenClaw reads auth-profiles.json)
AGENT_DIR="/data/.openclaw/agents/main/agent"
mkdir -p "$AGENT_DIR"

# Write .env to BOTH locations (root config dir + agent dir)
# OpenClaw docs: cat >> ~/.openclaw/.env <<'EOF' ANTHROPIC_API_KEY=... EOF
ROOT_ENV="/data/.openclaw/.env"
AGENT_ENV="$AGENT_DIR/.env"

# Clear previous .env files to avoid duplicates on restart
> "$ROOT_ENV"
> "$AGENT_ENV"

# Check if any auth is configured
HAS_AUTH=false

# Write API keys to both .env locations
if [ -n "$ANTHROPIC_API_KEY" ]; then
    echo "ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY" >> "$ROOT_ENV"
    echo "ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY" >> "$AGENT_ENV"
    echo "Configured Anthropic API key"
    HAS_AUTH=true
fi

if [ -n "$OPENAI_API_KEY" ]; then
    echo "OPENAI_API_KEY=$OPENAI_API_KEY" >> "$ROOT_ENV"
    echo "OPENAI_API_KEY=$OPENAI_API_KEY" >> "$AGENT_ENV"
    echo "Configured OpenAI API key"
    HAS_AUTH=true
fi

if [ -n "$GEMINI_API_KEY" ]; then
    echo "GEMINI_API_KEY=$GEMINI_API_KEY" >> "$ROOT_ENV"
    echo "GEMINI_API_KEY=$GEMINI_API_KEY" >> "$AGENT_ENV"
    echo "Configured Gemini API key"
    HAS_AUTH=true
fi

if [ -n "$OPENROUTER_API_KEY" ]; then
    echo "OPENROUTER_API_KEY=$OPENROUTER_API_KEY" >> "$ROOT_ENV"
    echo "OPENROUTER_API_KEY=$OPENROUTER_API_KEY" >> "$AGENT_ENV"
    echo "Configured OpenRouter API key"
    HAS_AUTH=true
fi

# For setup-tokens, use the paste-token CLI command which writes the correct
# OAuth-based format to auth-profiles.json. Do NOT manually create the file.
# Ref: openclaw models auth paste-token --provider anthropic
if [ -n "$OPENCLAW_ANTHROPIC_SETUP_TOKEN" ]; then
    echo "Adding Anthropic setup-token via paste-token command..."
    echo "$OPENCLAW_ANTHROPIC_SETUP_TOKEN" | node dist/index.js models auth paste-token --provider anthropic --yes 2>&1 || {
        echo "ERROR: paste-token command failed. Retrying with explicit agent dir..."
        # Retry with OPENCLAW_STATE_DIR explicitly set
        OPENCLAW_STATE_DIR=/data/.openclaw echo "$OPENCLAW_ANTHROPIC_SETUP_TOKEN" | node dist/index.js models auth paste-token --provider anthropic --yes 2>&1 || {
            echo "ERROR: Setup-token configuration failed. Check token validity."
            echo "Generate a fresh token with: claude setup-token"
        }
    }
    # Verify auth-profiles.json was created
    if [ -f "$AGENT_DIR/auth-profiles.json" ]; then
        echo "Auth profiles written to $AGENT_DIR/auth-profiles.json"
        HAS_AUTH=true
    else
        echo "WARNING: auth-profiles.json not found at $AGENT_DIR/auth-profiles.json"
        # Search for where it was actually written
        find /data/.openclaw -name "auth-profiles.json" -type f 2>/dev/null | while read f; do
            echo "  Found auth-profiles.json at: $f"
        done
    fi
fi

# Also handle CLAUDE_CODE_OAUTH_TOKEN if present
if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
    echo "CLAUDE_CODE_OAUTH_TOKEN=$CLAUDE_CODE_OAUTH_TOKEN" >> "$ROOT_ENV"
    echo "CLAUDE_CODE_OAUTH_TOKEN=$CLAUDE_CODE_OAUTH_TOKEN" >> "$AGENT_ENV"
    echo "Configured Claude Code OAuth token"
    HAS_AUTH=true
fi

# Export API keys as environment variables for the process
export ANTHROPIC_API_KEY
export OPENAI_API_KEY
export GEMINI_API_KEY
export OPENROUTER_API_KEY
export CLAUDE_CODE_OAUTH_TOKEN

if [ "$HAS_AUTH" = false ]; then
    echo ""
    echo "=========================================="
    echo "WARNING: No API keys configured!"
    echo "=========================================="
    echo "Add one of these environment variables in Coolify:"
    echo "  - OPENCLAW_ANTHROPIC_SETUP_TOKEN - for Claude Pro/Max (run 'claude setup-token')"
    echo "  - ANTHROPIC_API_KEY - get from https://console.anthropic.com/settings/keys"
    echo "  - GEMINI_API_KEY - get from https://aistudio.google.com/apikey"
    echo "  - OPENAI_API_KEY - get from https://platform.openai.com/api-keys"
    echo "  - OPENROUTER_API_KEY - get from https://openrouter.ai/keys"
    echo "=========================================="
    echo ""
fi

# Start the gateway with environment-variable-driven configuration
exec node dist/index.js gateway --bind "${OPENCLAW_GATEWAY_BIND:-lan}" --port "${OPENCLAW_GATEWAY_PORT:-18789}"
