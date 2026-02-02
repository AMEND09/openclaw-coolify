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
if [ -n "$ANTHROPIC_API_KEY" ]; then
    DEFAULT_MODEL="anthropic/claude-sonnet-4-5"
elif [ -n "$GEMINI_API_KEY" ]; then
    DEFAULT_MODEL="google/gemini-3-pro-preview"
elif [ -n "$OPENAI_API_KEY" ]; then
    DEFAULT_MODEL="openai/gpt-4o"
elif [ -n "$OPENROUTER_API_KEY" ]; then
    DEFAULT_MODEL="openrouter/anthropic/claude-sonnet-4"
fi
echo "Default model: $DEFAULT_MODEL"

# Determine if we should regenerate config
# Only regenerate if config doesn't exist or missing critical fields
SHOULD_REGENERATE=false
if [ ! -f "/data/.openclaw/openclaw.json" ]; then
    SHOULD_REGENERATE=true
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
# OpenClaw reads API keys from environment variables and .env files
echo "Configuring authentication..."

# Create agent directory structure
AGENT_DIR="/data/.openclaw/agents/main/agent"
mkdir -p "$AGENT_DIR"

# Create .env file in the agent directory where OpenClaw expects it
ENV_FILE="$AGENT_DIR/.env"

# Check if any auth is configured
HAS_AUTH=false

# API keys are read directly from environment by OpenClaw
if [ -n "$ANTHROPIC_API_KEY" ]; then
    echo "ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY" >> "$ENV_FILE"
    echo "Configured Anthropic API key"
    HAS_AUTH=true
fi

if [ -n "$OPENAI_API_KEY" ]; then
    echo "OPENAI_API_KEY=$OPENAI_API_KEY" >> "$ENV_FILE"
    echo "Configured OpenAI API key"
    HAS_AUTH=true
fi

if [ -n "$GEMINI_API_KEY" ]; then
    echo "GEMINI_API_KEY=$GEMINI_API_KEY" >> "$ENV_FILE"
    echo "Configured Gemini API key"
    HAS_AUTH=true
fi

if [ -n "$OPENROUTER_API_KEY" ]; then
    echo "OPENROUTER_API_KEY=$OPENROUTER_API_KEY" >> "$ENV_FILE"
    echo "Configured OpenRouter API key"
    HAS_AUTH=true
fi

# For setup-tokens, create auth-profiles.json directly
if [ -n "$OPENCLAW_ANTHROPIC_SETUP_TOKEN" ]; then
    echo "Adding Anthropic setup-token..."
    AUTH_PROFILES_FILE="$AGENT_DIR/auth-profiles.json"
    cat > "$AUTH_PROFILES_FILE" << EOF
{
  "anthropic": {
    "type": "setup-token",
    "setupToken": "$OPENCLAW_ANTHROPIC_SETUP_TOKEN"
  }
}
EOF
    echo "Auth profiles written to $AUTH_PROFILES_FILE"
    HAS_AUTH=true
fi

# Also export API keys as environment variables for the process
export ANTHROPIC_API_KEY
export OPENAI_API_KEY
export GEMINI_API_KEY
export OPENROUTER_API_KEY

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
