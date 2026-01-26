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
    "trustedProxies": ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "127.0.0.1"]
  },
  "agents": {
    "defaults": {
      "workspace": "/data/clawd"
    }
  }
}
EOF
echo "Config written to /data/.clawdbot/clawdbot.json"

# Start the gateway with --allow-unconfigured flag as fallback
exec node dist/index.js gateway --bind lan --port 18789 --allow-unconfigured
