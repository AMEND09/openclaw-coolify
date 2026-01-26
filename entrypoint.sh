#!/bin/bash
# Clawdbot Gateway Entrypoint
# This script ensures the gateway can start with proper configuration

set -e

# If no gateway token is set, generate one automatically
if [ -z "$CLAWDBOT_GATEWAY_TOKEN" ]; then
    export CLAWDBOT_GATEWAY_TOKEN=$(openssl rand -hex 32)
    echo "Generated gateway token: $CLAWDBOT_GATEWAY_TOKEN"
    echo "Save this token to access the Control UI!"
fi

# Build trusted proxies JSON array from environment variable
# Default includes common Docker gateway IPs
DEFAULT_PROXIES="10.0.0.1,10.0.1.1,10.0.1.2,10.0.2.1,10.0.2.2,10.0.3.1,10.0.3.2,10.0.4.1,172.17.0.1,172.18.0.1,127.0.0.1"
TRUSTED_PROXIES=${CLAWDBOT_TRUSTED_PROXIES:-$DEFAULT_PROXIES}

# Convert comma-separated list to JSON array
PROXIES_JSON=$(echo "$TRUSTED_PROXIES" | sed 's/,/", "/g' | sed 's/^/["/' | sed 's/$/"]/')
echo "Trusted proxies: $PROXIES_JSON"

# Create config directory if it doesn't exist
mkdir -p /data/.clawdbot

# Determine default model based on available API keys
DEFAULT_MODEL="anthropic/claude-sonnet-4-5"  # fallback
if [ -n "$ANTHROPIC_API_KEY" ]; then
    DEFAULT_MODEL="anthropic/claude-sonnet-4-5"
elif [ -n "$GEMINI_API_KEY" ]; then
    DEFAULT_MODEL="google/gemini-2.5-pro"
elif [ -n "$OPENAI_API_KEY" ]; then
    DEFAULT_MODEL="openai/gpt-4o"
elif [ -n "$OPENROUTER_API_KEY" ]; then
    DEFAULT_MODEL="openrouter/anthropic/claude-sonnet-4"
fi
echo "Default model: $DEFAULT_MODEL"

# Always create/update config to ensure gateway.mode is set
# (Previous configs may be missing required fields)
cat > /data/.clawdbot/clawdbot.json << EOF
{
  "gateway": {
    "mode": "local",
    "bind": "lan",
    "port": 18789,
    "auth": {
      "mode": "token",
      "token": "${CLAWDBOT_GATEWAY_TOKEN}"
    },
    "trustedProxies": ${PROXIES_JSON},
    "controlUi": {
      "allowInsecureAuth": true
    }
  },
  "agents": {
    "defaults": {
      "workspace": "/data/clawd",
      "model": {
        "primary": "${DEFAULT_MODEL}"
      }
    }
  }
}
EOF
echo "Config written to /data/.clawdbot/clawdbot.json"

# Create auth-profiles.json for API keys / OAuth tokens
AUTH_DIR="/data/.clawdbot/agents/main/agent"
mkdir -p "$AUTH_DIR"

# Build auth profiles from environment variables
AUTH_PROFILES="{}"
HAS_AUTH=false

# Add Anthropic API key if provided (RECOMMENDED - simplest option)
if [ -n "$ANTHROPIC_API_KEY" ]; then
    AUTH_PROFILES=$(echo "$AUTH_PROFILES" | jq --arg key "$ANTHROPIC_API_KEY" '. + {"anthropic:api": {"provider": "anthropic", "mode": "api_key", "apiKey": $key}}')
    echo "Added Anthropic API key to auth profiles"
    HAS_AUTH=true
fi

# Add OpenAI API key if provided
if [ -n "$OPENAI_API_KEY" ]; then
    AUTH_PROFILES=$(echo "$AUTH_PROFILES" | jq --arg key "$OPENAI_API_KEY" '. + {"openai:api": {"provider": "openai", "mode": "api_key", "apiKey": $key}}')
    echo "Added OpenAI API key to auth profiles"
    HAS_AUTH=true
fi

# Add OpenRouter API key if provided
if [ -n "$OPENROUTER_API_KEY" ]; then
    AUTH_PROFILES=$(echo "$AUTH_PROFILES" | jq --arg key "$OPENROUTER_API_KEY" '. + {"openrouter:api": {"provider": "openrouter", "mode": "api_key", "apiKey": $key}}')
    echo "Added OpenRouter API key to auth profiles"
    HAS_AUTH=true
fi

# Add Gemini API key if provided
if [ -n "$GEMINI_API_KEY" ]; then
    AUTH_PROFILES=$(echo "$AUTH_PROFILES" | jq --arg key "$GEMINI_API_KEY" '. + {"google:api": {"provider": "google", "mode": "api_key", "apiKey": $key}}')
    echo "Added Gemini API key to auth profiles"
    HAS_AUTH=true
fi

# Write auth profiles if any keys were added
if [ "$HAS_AUTH" = true ]; then
    echo "$AUTH_PROFILES" > "$AUTH_DIR/auth-profiles.json"
    echo "Auth profiles written to $AUTH_DIR/auth-profiles.json"
fi

# Handle Claude setup-token separately (requires clawdbot CLI to process)
if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ] && [ "$HAS_AUTH" = false ]; then
    echo "CLAUDE_CODE_OAUTH_TOKEN detected but setup-tokens require CLI processing."
    echo "For easiest setup, use ANTHROPIC_API_KEY instead."
    echo "Get an API key from: https://console.anthropic.com/settings/keys"
fi

if [ "$HAS_AUTH" = false ] && [ -z "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
    echo ""
    echo "=========================================="
    echo "WARNING: No API keys configured!"
    echo "=========================================="
    echo "Add one of these environment variables in Coolify:"
    echo "  - ANTHROPIC_API_KEY (recommended) - get from https://console.anthropic.com/settings/keys"
    echo "  - OPENAI_API_KEY - get from https://platform.openai.com/api-keys"
    echo "  - OPENROUTER_API_KEY - get from https://openrouter.ai/keys"
    echo "=========================================="
    echo ""
fi

# Start the gateway with --allow-unconfigured flag as fallback
exec node dist/index.js gateway --bind lan --port 18789 --allow-unconfigured
