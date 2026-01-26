# Clawdbot on Coolify

One-click deployment of [Clawdbot](https://clawdbot.com) - your personal AI assistant - on [Coolify](https://coolify.io).

## What is Clawdbot?

Clawdbot is an open-source personal AI assistant that runs on your own infrastructure. It connects to messaging platforms you already use (WhatsApp, Telegram, Discord, Slack, and more) and can:

- Manage your emails and calendar
- Browse the web and research topics
- Write and execute code
- Control smart home devices
- And much more through extensible skills

**Key Features:**
- Multi-channel inbox (WhatsApp, Telegram, Discord, Slack, iMessage, Signal, WebChat)
- Voice interaction (Voice Wake + Talk Mode)
- Browser automation for web tasks
- Persistent memory across sessions
- Self-improving through custom skills

## Prerequisites

Before deploying, you'll need:

1. **Coolify** installed and running on your server
2. **At least one AI model provider** API key:
   - [Anthropic API Key](https://console.anthropic.com/) (recommended)
   - [OpenAI API Key](https://platform.openai.com/api-keys)
3. **Optional channel tokens** (can be configured later):
   - Telegram: Bot token from [@BotFather](https://t.me/BotFather)
   - Discord: Bot token from [Discord Developer Portal](https://discord.com/developers/applications)
   - Slack: Bot and App tokens from [Slack API](https://api.slack.com/apps)

## Quick Start (Coolify Deployment)

### Step 1: Create New Resource in Coolify

1. Open your Coolify dashboard
2. Navigate to your project
3. Click **"Create New Resource"**
4. Select **"Public Repository"**

### Step 2: Configure the Repository

Enter the following repository URL:

```
https://github.com/YOUR_USERNAME/clawdbot-coolify
```

Or deploy directly from this repo.

### Step 3: Select Build Pack

1. Click on the build pack selector
2. Choose **"Docker Compose"**
3. Set the following:
   - **Branch:** `main`
   - **Base Directory:** `/`
   - **Docker Compose Location:** `docker-compose.yml`

### Step 4: Configure Environment Variables

In the Coolify environment variables section, add:

**Required:**
```
CLAWDBOT_GATEWAY_TOKEN=your-secure-token-here
ANTHROPIC_API_KEY=sk-ant-...
```

**Optional Channels:**
```
TELEGRAM_BOT_TOKEN=123456:ABC...
DISCORD_BOT_TOKEN=MTIz...
```

> **Tip:** Generate a secure gateway token with: `openssl rand -hex 32`

### Step 5: Configure Domain

1. Go to the **Domains** tab in Coolify
2. Add your domain (e.g., `clawdbot.yourdomain.com`)
3. Coolify will automatically provision SSL certificates

### Step 6: Deploy

Click **"Deploy"** and wait for the build to complete (first build takes ~5-10 minutes).

## Post-Deployment Setup

### Access the Control UI

1. Open `https://your-domain.com` in your browser
2. Enter your gateway token when prompted
3. You should see the Clawdbot Control UI dashboard

### Configure WhatsApp (Optional)

WhatsApp requires a QR code scan for authentication:

```bash
# Connect to your Coolify server via SSH, then:
docker exec -it clawdbot-gateway clawdbot channels login
```

Scan the QR code with WhatsApp on your phone (Settings → Linked Devices).

### Configure Model Authentication

If you're using OAuth instead of API keys:

```bash
docker exec -it clawdbot-gateway clawdbot configure --section auth
```

### Verify Channels

Check that all configured channels are working:

```bash
docker exec -it clawdbot-gateway clawdbot status
docker exec -it clawdbot-gateway clawdbot health
```

## Architecture

```
                    Coolify Reverse Proxy (Traefik)
                              │
                              │ HTTPS (auto SSL)
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Docker Compose Stack                      │
│                                                              │
│  ┌──────────────────┐   ┌─────────┐   ┌──────────────────┐  │
│  │  clawdbot-gateway │   │  redis  │   │  clawdbot-browser │  │
│  │   (Node.js 22)    │◄──┤ (cache) │   │   (Chromium+CDP) │  │
│  │                   │   └─────────┘   │                  │  │
│  │  Ports:           │                 │  Port: 9222 (CDP) │  │
│  │  - 18789 (WS/HTTP)│◄────────────────│  - 6080 (noVNC)   │  │
│  │  - 18793 (Canvas) │                 │                  │  │
│  └──────────────────┘                 └──────────────────┘  │
│                                                              │
│  Persistent Volumes:                                         │
│  - clawdbot-config (credentials, sessions)                  │
│  - clawdbot-workspace (agent workspace)                     │
│  - clawdbot-redis-data (cache)                              │
└─────────────────────────────────────────────────────────────┘
```

## Services

| Service | Description | Port |
|---------|-------------|------|
| `clawdbot-gateway` | Main AI assistant gateway | 18789 |
| `clawdbot-redis` | Cache and session storage | 6379 (internal) |
| `clawdbot-browser` | Browser automation (Chromium) | 9222 (internal), 6080 (noVNC) |

## Environment Variables

### Required

| Variable | Description |
|----------|-------------|
| `CLAWDBOT_GATEWAY_TOKEN` | Authentication token for the gateway |
| `ANTHROPIC_API_KEY` or `OPENAI_API_KEY` | AI model provider API key |

### Channel Configuration

| Variable | Description |
|----------|-------------|
| `TELEGRAM_BOT_TOKEN` | Telegram bot token from @BotFather |
| `DISCORD_BOT_TOKEN` | Discord bot token |
| `SLACK_BOT_TOKEN` | Slack bot token |
| `SLACK_APP_TOKEN` | Slack app-level token |

### Optional

| Variable | Description | Default |
|----------|-------------|---------|
| `CLAWDBOT_GATEWAY_BIND` | Network bind mode | `lan` |
| `CLAWDBOT_GATEWAY_PORT` | Gateway port | `18789` |
| `CLAWDBOT_BROWSER_ENABLED` | Enable browser tool | `true` |
| `BRAVE_SEARCH_API_KEY` | Web search capability | - |
| `GOG_KEYRING_PASSWORD` | Gmail credential encryption | - |

## Persistent Data

All data is stored in Docker volumes:

| Volume | Path in Container | Contents |
|--------|-------------------|----------|
| `clawdbot-config` | `/data/.clawdbot` | Config, credentials, sessions |
| `clawdbot-workspace` | `/data/clawd` | Agent workspace, code, artifacts |
| `clawdbot-redis-data` | `/data` | Redis persistence |
| `clawdbot-browser-data` | `/home/browser` | Browser profiles |

## Helper Scripts

The `scripts/` directory contains helper scripts for post-deployment configuration:

```bash
# Make scripts executable (if running locally)
chmod +x scripts/*.sh

# Run initial setup and verification
./scripts/setup.sh

# Configure WhatsApp (QR code login)
./scripts/channel-login.sh whatsapp

# View channel setup instructions
./scripts/channel-login.sh telegram
./scripts/channel-login.sh discord
./scripts/channel-login.sh slack
```

## Updating

To update Clawdbot:

1. Go to your application in Coolify
2. Click **"Redeploy"** to rebuild with latest changes

For manual updates on the server:
```bash
# If deployed with build context
cd /path/to/clawdbot-coolify
git pull
# Then redeploy via Coolify UI
```

## Troubleshooting

### Gateway not starting

Check logs:
```bash
docker logs clawdbot-gateway
```

Common issues:
- Missing `CLAWDBOT_GATEWAY_TOKEN`
- Invalid API keys
- Port conflicts

### WhatsApp disconnected

Re-authenticate:
```bash
docker exec -it clawdbot-gateway clawdbot channels login
```

### Browser tool not working

Check browser container:
```bash
docker logs clawdbot-browser
docker exec clawdbot-browser curl -s http://localhost:9222/json/version
```

### Health check failing

```bash
docker exec clawdbot-gateway clawdbot health
docker exec clawdbot-gateway clawdbot doctor
```

## Security Considerations

1. **Gateway Token**: Use a strong, unique token. Never commit it to version control.
2. **API Keys**: Store securely. Consider using Coolify's secret management.
3. **Network**: The gateway binds to `lan` by default. Use `loopback` for stricter security.
4. **DM Policy**: By default, unknown DMs require pairing approval.

For detailed security guidance, see [Clawdbot Security Docs](https://docs.clawd.bot/gateway/security).

## Resources

- [Clawdbot Documentation](https://docs.clawd.bot)
- [Clawdbot GitHub](https://github.com/clawdbot/clawdbot)
- [Coolify Documentation](https://coolify.io/docs)
- [Discord Community](https://discord.gg/clawd)

## License

This deployment configuration is MIT licensed.
Clawdbot itself is MIT licensed - see [Clawdbot License](https://github.com/clawdbot/clawdbot/blob/main/LICENSE).

## Credits

- [Clawdbot](https://clawdbot.com) by Peter Steinberger ([@steipete](https://twitter.com/steipete))
- [Coolify](https://coolify.io) by Andras Bacsai
