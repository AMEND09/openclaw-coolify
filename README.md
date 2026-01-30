# OpenClaw on Coolify 🦞

One-click deployment of [OpenClaw](https://openclaw.ai) - your personal AI assistant - on [Coolify](https://coolify.io). Use your iPhone as a mobile workstation for vibecoding via Telegram and the OpenClaw Web UI.

## What is OpenClaw?

OpenClaw is an open-source personal AI assistant that runs on your own infrastructure. It connects to messaging platforms you already use (WhatsApp, Telegram, Discord, Slack, and more) and can:

- **Vibe Code from anywhere**: Prompt your agent from your phone to write, test, and deploy code.
- **Manage your digital life**: Emails, calendar, and task management.
- **Browse the web**: Research topics and automate browser tasks.
- **Execute code**: Run scripts and manage servers directly via chat.
- **Extensible**: Add custom skills and tools.

**Key Features:**
- Multi-channel inbox (WhatsApp, Telegram, Discord, Slack, iMessage (macOS), WebChat)
- Voice interaction (Voice notes + Transcription)
- Browser automation for web tasks
- Persistent memory and multi-agent routing
- Mobile-first experience for iPhone/Android

## Prerequisites

Before deploying, you'll need:

1. **Coolify** installed and running on your server (Hetzner, AWS, DigitalOcean, etc.)
2. **At least one AI model provider** API key:
   - [Anthropic API Key](https://console.anthropic.com/) (Claude 3.5 Sonnet / 3 Opis)
   - [OpenAI API Key](https://platform.openai.com/api-keys)
   - [Google Gemini API Key](https://aistudio.google.com/apikey)
3. **Optional channel tokens**:
   - Telegram: Bot token from [@BotFather](https://t.me/BotFather) (Highly recommended for mobile access)
   - Discord: Bot token from [Discord Developer Portal](https://discord.com/developers/applications)

## Quick Start (Coolify Deployment)

### Step 1: Create New Resource in Coolify

1. Open your Coolify dashboard
2. Navigate to your project
3. Click **"Create New Resource"**
4. Select **"Public Repository"**

### Step 2: Configure the Repository

Enter the following repository URL:

```
https://github.com/wiselancer/openclaw-coolify
```

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
```bash
OPENCLAW_GATEWAY_TOKEN=your-secure-token-here # Generate with: openssl rand -hex 32
ANTHROPIC_API_KEY=sk-ant-...
```

**Mobile Access (Telegram):**
```bash
TELEGRAM_BOT_TOKEN=123456:ABC...
```

### Step 5: Configure Domain

1. Go to the **Domains** tab in Coolify
2. Add your domain (e.g., `openclaw.yourdomain.com`)
3. Coolify will automatically provision SSL certificates via Traefik.

### Step 6: Deploy

Click **"Deploy"** and wait for the build to complete.

## Mobile Workstation (Vibecoding via iPhone)

OpenClaw is designed to turn your phone into a powerful workstation.

### 1. Telegram Workflow (The "Vibe" Way)
Connect your Telegram bot and use it for:
- Writing code snippets on the go.
- Asking for status updates on long-running tasks.
- Using **Voice Messages** to prompt complex logic while walking.

### 2. Web UI (The Desktop Experience)
Access your OpenClaw instance via Safari on iPhone.
- Tap **"Share"** -> **"Add to Home Screen"** to install it as a PWA.
- Use the built-in IDE/Terminal for more precise control.

### 3. Secure Remote Access
Since you are likely on the move, consider:
- **Tailscale**: Access your Coolify instance via its Tailnet IP for maximum security.
- **Cloudflare Tunnels**: Use Cloudflare Access to protect your OpenClaw UI.

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
│  │ openclaw-gateway │   │  redis  │   │ openclaw-browser │  │
│  │   (Node.js 22)    │◄──┤ (cache) │   │   (Chromium)     │  │
│  │                   │   └─────────┘   │                  │  │
│  │  Ports:           │                 │  Port: 9222 (CDP) │  │
│  │  - 18789 (WS/HTTP)│◄────────────────│                  │  │
│  │  - 18793 (Canvas) │                 │                  │  │
│  └──────────────────┘                 └──────────────────┘  │
│                                                              │
│  Persistent Volumes:                                         │
│  - openclaw-config (credentials, sessions)                  │
│  - openclaw-workspace (agent workspace)                     │
│  - openclaw-redis-data (cache)                              │
└─────────────────────────────────────────────────────────────┘
```

## Services & Ports

| Service | Description | Port |
|---------|-------------|------|
| `openclaw-gateway` | Main AI assistant gateway | 18789 |
| `openclaw-redis` | Cache and session storage | 6379 (int) |
| `openclaw-browser` | Browser automation (Chromium) | 9222 (int) |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `OPENCLAW_GATEWAY_TOKEN` | Auth token for gateway access |
| `ANTHROPIC_API_KEY` | Primary AI model (Claude) |
| `TELEGRAM_BOT_TOKEN` | For Telegram bot access |
| `OPENCLAW_GATEWAY_BIND` | Default: `lan` |

## Resources

- [Official OpenClaw Docs](https://docs.openclaw.ai)
- [Official OpenClaw GitHub](https://github.com/openclaw/openclaw)
- [Coolify Documentation](https://coolify.io/docs)

## License

This deployment configuration is MIT licensed.
OpenClaw itself is MIT licensed.

## Credits

- [OpenClaw](https://openclaw.ai) by Peter Steinberger ([@steipete](https://twitter.com/steipete))
- [Coolify](https://coolify.io) by Andras Bacsai
