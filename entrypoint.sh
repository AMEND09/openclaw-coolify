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

# Create auth-profiles.json for API keys / OAuth tokens
AUTH_DIR="/data/.openclaw/agents/main/agent"
mkdir -p "$AUTH_DIR"

# Build auth profiles JSON directly (avoid jq complexity)
echo "Building auth profiles..."

# Start JSON object
AUTH_JSON="{"
FIRST=true

# Add Anthropic API key if provided
if [ -n "$ANTHROPIC_API_KEY" ]; then
    [ "$FIRST" = false ] && AUTH_JSON="$AUTH_JSON,"
    AUTH_JSON="$AUTH_JSON\"anthropic:api\":{\"provider\":\"anthropic\",\"mode\":\"api_key\",\"apiKey\":\"$ANTHROPIC_API_KEY\"}"
    echo "Added Anthropic API key"
    FIRST=false
fi

# Add Anthropic OAuth token if provided (Claude Code subscription)
if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
    [ "$FIRST" = false ] && AUTH_JSON="$AUTH_JSON,"
    AUTH_JSON="$AUTH_JSON\"anthropic:oauth\":{\"provider\":\"anthropic\",\"mode\":\"oauth\",\"oauthToken\":\"$CLAUDE_CODE_OAUTH_TOKEN\"}"
    echo "Added Anthropic OAuth token (Claude Code)"
    FIRST=false
fi

# Add OpenAI API key if provided
if [ -n "$OPENAI_API_KEY" ]; then
    [ "$FIRST" = false ] && AUTH_JSON="$AUTH_JSON,"
    AUTH_JSON="$AUTH_JSON\"openai:api\":{\"provider\":\"openai\",\"mode\":\"api_key\",\"apiKey\":\"$OPENAI_API_KEY\"}"
    echo "Added OpenAI API key"
    FIRST=false
fi

# Add OpenRouter API key if provided
if [ -n "$OPENROUTER_API_KEY" ]; then
    [ "$FIRST" = false ] && AUTH_JSON="$AUTH_JSON,"
    AUTH_JSON="$AUTH_JSON\"openrouter:api\":{\"provider\":\"openrouter\",\"mode\":\"api_key\",\"apiKey\":\"$OPENROUTER_API_KEY\"}"
    echo "Added OpenRouter API key"
    FIRST=false
fi

# Add Gemini API key if provided
if [ -n "$GEMINI_API_KEY" ]; then
    [ "$FIRST" = false ] && AUTH_JSON="$AUTH_JSON,"
    AUTH_JSON="$AUTH_JSON\"google:api\":{\"provider\":\"google\",\"mode\":\"api_key\",\"apiKey\":\"$GEMINI_API_KEY\"}"
    echo "Added Gemini API key"
    FIRST=false
fi

# Close JSON object
AUTH_JSON="$AUTH_JSON}"

# Write auth profiles if any keys were added
if [ "$FIRST" = false ]; then
    echo "$AUTH_JSON" > "$AUTH_DIR/auth-profiles.json"
    echo "Auth profiles written to $AUTH_DIR/auth-profiles.json"
else
    echo ""
    echo "=========================================="
    echo "WARNING: No API keys configured!"
    echo "=========================================="
    echo "Add one of these environment variables in Coolify:"
    echo "  - CLAUDE_CODE_OAUTH_TOKEN - for Claude Pro (run 'claude setup-token')"
    echo "  - ANTHROPIC_API_KEY - get from https://console.anthropic.com/settings/keys"
    echo "  - GEMINI_API_KEY - get from https://aistudio.google.com/apikey"
    echo "  - OPENAI_API_KEY - get from https://platform.openai.com/api-keys"
    echo "  - OPENROUTER_API_KEY - get from https://openrouter.ai/keys"
    echo "=========================================="
    echo ""
fi

# Start the gateway with environment-variable-driven configuration
exec node dist/index.js gateway --bind "${OPENCLAW_GATEWAY_BIND:-lan}" --port "${OPENCLAW_GATEWAY_PORT:-18789}" --allow-unconfigured
