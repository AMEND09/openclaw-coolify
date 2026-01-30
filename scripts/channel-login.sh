#!/bin/bash
# =============================================================================
# OpenClaw Channel Login Script
# =============================================================================
# Use this script to authenticate with messaging channels that require
# interactive login (like WhatsApp QR code scanning).
#
# Usage: ./scripts/channel-login.sh [channel]
#   channel: whatsapp (default), telegram, discord, all
# =============================================================================

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CHANNEL="${1:-whatsapp}"
CONTAINER="openclaw-gateway"

print_header() {
    echo ""
    echo -e "${BLUE}=================================================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}=================================================================${NC}"
    echo ""
}

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    echo -e "${YELLOW}Error: ${CONTAINER} is not running.${NC}"
    echo "Please ensure OpenClaw is deployed and running."
    exit 1
fi

case "$CHANNEL" in
    whatsapp|wa)
        print_header "WhatsApp Login"
        echo "A QR code will appear below. Scan it with your WhatsApp app:"
        echo "  1. Open WhatsApp on your phone"
        echo "  2. Go to Settings → Linked Devices"
        echo "  3. Tap 'Link a Device'"
        echo "  4. Scan the QR code"
        echo ""
        echo "Press Ctrl+C to cancel."
        echo ""
        docker exec -it "$CONTAINER" node dist/index.js channels login 2>/dev/null || \
            docker exec -it "$CONTAINER" openclaw channels login
        ;;
    
    telegram|tg)
        print_header "Telegram Configuration"
        echo "Telegram uses a bot token for authentication."
        echo ""
        echo "To configure Telegram:"
        echo "  1. Message @BotFather on Telegram"
        echo "  2. Send /newbot and follow the prompts"
        echo "  3. Copy the bot token"
        echo "  4. Set TELEGRAM_BOT_TOKEN in your Coolify environment variables"
        echo "  5. Redeploy your application"
        echo ""
        echo "Current status:"
        if docker exec "$CONTAINER" printenv TELEGRAM_BOT_TOKEN 2>/dev/null | grep -q .; then
            echo -e "${GREEN}✓ TELEGRAM_BOT_TOKEN is configured${NC}"
        else
            echo -e "${YELLOW}✗ TELEGRAM_BOT_TOKEN is not set${NC}"
        fi
        ;;
    
    discord)
        print_header "Discord Configuration"
        echo "Discord uses a bot token for authentication."
        echo ""
        echo "To configure Discord:"
        echo "  1. Go to https://discord.com/developers/applications"
        echo "  2. Create a new application or select existing"
        echo "  3. Go to Bot section and create/reset token"
        echo "  4. Set DISCORD_BOT_TOKEN in your Coolify environment variables"
        echo "  5. Redeploy your application"
        echo ""
        echo "Bot Invite URL format:"
        echo "  https://discord.com/api/oauth2/authorize?client_id=YOUR_CLIENT_ID&permissions=277025508416&scope=bot"
        echo ""
        echo "Current status:"
        if docker exec "$CONTAINER" printenv DISCORD_BOT_TOKEN 2>/dev/null | grep -q .; then
            echo -e "${GREEN}✓ DISCORD_BOT_TOKEN is configured${NC}"
        else
            echo -e "${YELLOW}✗ DISCORD_BOT_TOKEN is not set${NC}"
        fi
        ;;
    
    slack)
        print_header "Slack Configuration"
        echo "Slack requires both a Bot Token and App Token."
        echo ""
        echo "To configure Slack:"
        echo "  1. Go to https://api.slack.com/apps"
        echo "  2. Create a new app or select existing"
        echo "  3. Enable Socket Mode and get App Token (xapp-...)"
        echo "  4. Install to workspace and get Bot Token (xoxb-...)"
        echo "  5. Set SLACK_BOT_TOKEN and SLACK_APP_TOKEN in Coolify"
        echo "  6. Redeploy your application"
        echo ""
        echo "Current status:"
        if docker exec "$CONTAINER" printenv SLACK_BOT_TOKEN 2>/dev/null | grep -q .; then
            echo -e "${GREEN}✓ SLACK_BOT_TOKEN is configured${NC}"
        else
            echo -e "${YELLOW}✗ SLACK_BOT_TOKEN is not set${NC}"
        fi
        if docker exec "$CONTAINER" printenv SLACK_APP_TOKEN 2>/dev/null | grep -q .; then
            echo -e "${GREEN}✓ SLACK_APP_TOKEN is configured${NC}"
        else
            echo -e "${YELLOW}✗ SLACK_APP_TOKEN is not set${NC}"
        fi
        ;;
    
    status|all)
        print_header "Channel Status"
        docker exec "$CONTAINER" node dist/index.js status 2>/dev/null || \
            docker exec "$CONTAINER" openclaw status
        ;;
    
    *)
        echo "Usage: $0 [channel]"
        echo ""
        echo "Channels:"
        echo "  whatsapp, wa    - Login to WhatsApp (QR code)"
        echo "  telegram, tg    - Show Telegram setup instructions"
        echo "  discord         - Show Discord setup instructions"
        echo "  slack           - Show Slack setup instructions"
        echo "  status, all     - Show all channel status"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}Done!${NC}"
