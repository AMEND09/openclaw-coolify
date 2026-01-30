#!/bin/bash
# OpenClaw Gateway Entrypoint
# This script ensures the gateway can start with proper configuration

set -e

# If no gateway token is set, generate one automatically
if [ -z "$OPENCLAW_GATEWAY_TOKEN" ]; then
    export OPENCLAW_GATEWAY_TOKEN=$(openssl rand -hex 32)
    echo "Generated gateway token: $OPENCLAW_GATEWAY_TOKEN"
    echo "Save this token to access the Control UI!"
fi

# Build trusted proxies JSON array from environment variable
# Default includes common Docker gateway IPs and ranges
DEFAULT_PROXIES="loopback,linklocal,uniquelocal,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
TRUSTED_PROXIES=${OPENCLAW_TRUSTED_PROXIES:-$DEFAULT_PROXIES}

# Convert comma-separated list to JSON array
PROXIES_JSON=$(echo "$TRUSTED_PROXIES" | sed 's/,/", "/g' | sed 's/^/["/' | sed 's/$/"]/')
echo "Trusted proxies: $PROXIES_JSON"

# Create config directory if it doesn't exist
mkdir -p /data/.openclaw

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

# Log which channel tokens are present
if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
    echo "Telegram bot token detected"
fi

if [ -n "$DISCORD_BOT_TOKEN" ]; then
    echo "Discord bot token detected"
fi

# Always create/update config with proper gateway configuration
# (Previous configs may be missing required fields)
cat > /data/.openclaw/openclaw.json << EOF
{
  "gateway": {
    "bind": "lan",
    "port": 18789,
    "auth": {
      "mode": "token",
      "token": "${OPENCLAW_GATEWAY_TOKEN}"
    },
    "trustedProxies": ${PROXIES_JSON},
    "controlUi": {
      "allowInsecureAuth": true
    }
  },
  "web": {
    "enabled": true
  },
  "channels": {
    "whatsapp": {
      "dmPolicy": "open",
      "allowFrom": ["*"]
    },
    "discord": {
      "groupPolicy": "open",
      "dm": {
        "enabled": true,
        "policy": "open",
        "allowFrom": ["*"]
      },
      "guilds": {
        "*": {
          "requireMention": false
        }
      }
    }
  },
  "agents": {
    "defaults": {
      "workspace": "/data/openclaw",
      "model": {
        "primary": "${DEFAULT_MODEL}"
      }
    }
  }
}
EOF
echo "Config written to /data/.openclaw/openclaw.json"

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
    echo "  - ANTHROPIC_API_KEY - get from https://console.anthropic.com/settings/keys"
    echo "  - GEMINI_API_KEY - get from https://aistudio.google.com/apikey"
    echo "  - OPENAI_API_KEY - get from https://platform.openai.com/api-keys"
    echo "  - OPENROUTER_API_KEY - get from https://openrouter.ai/keys"
    echo "=========================================="
    echo ""
fi

# Start the gateway with --allow-unconfigured flag as fallback
exec node dist/index.js gateway --bind lan --port 18789 --allow-unconfigured
