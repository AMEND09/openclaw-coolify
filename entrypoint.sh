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

# Create config directory if it doesn't exist
mkdir -p /data/.clawdbot

# Create a minimal config file if none exists
if [ ! -f /data/.clawdbot/clawdbot.json ]; then
    cat > /data/.clawdbot/clawdbot.json << EOF
{
  "gateway": {
    "mode": "local",
    "bind": "lan",
    "port": 18789,
    "auth": {
      "mode": "token",
      "token": "${CLAWDBOT_GATEWAY_TOKEN}"
    }
  },
  "agents": {
    "defaults": {
      "workspace": "/data/clawd"
    }
  }
}
EOF
    echo "Created default config at /data/.clawdbot/clawdbot.json"
fi

# Start the gateway with --allow-unconfigured flag as fallback
exec node dist/index.js gateway --bind lan --port 18789 --allow-unconfigured
