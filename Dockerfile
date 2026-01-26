# Clawdbot Gateway - Optimized for Coolify Deployment
# https://github.com/clawdbot/clawdbot
#
# This Dockerfile builds a production-ready Clawdbot gateway with all
# required binaries baked in for persistent operation.

FROM node:22-bookworm

# Build arguments
ARG CLAWDBOT_VERSION=latest
ARG TARGETARCH

# Labels for container identification
LABEL org.opencontainers.image.title="Clawdbot Gateway"
LABEL org.opencontainers.image.description="Personal AI Assistant - Gateway Service"
LABEL org.opencontainers.image.source="https://github.com/clawdbot/clawdbot"
LABEL org.opencontainers.image.vendor="Clawdbot"
LABEL org.opencontainers.image.licenses="MIT"

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    wget \
    git \
    ca-certificates \
    gnupg \
    socat \
    jq \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# Install Bun (required for some build scripts)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

# Determine architecture for binary downloads
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then \
        echo "x86_64" > /tmp/arch; \
    elif [ "$ARCH" = "arm64" ]; then \
        echo "arm64" > /tmp/arch; \
    else \
        echo "x86_64" > /tmp/arch; \
    fi

# Install gog (Gmail CLI) - baked into image for persistence
RUN ARCH=$(cat /tmp/arch) && \
    curl -L "https://github.com/steipete/gog/releases/latest/download/gog_Linux_${ARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin && chmod +x /usr/local/bin/gog \
    || echo "Warning: gog installation failed (optional dependency)"

# Install goplaces (Google Places CLI)
RUN ARCH=$(cat /tmp/arch) && \
    curl -L "https://github.com/steipete/goplaces/releases/latest/download/goplaces_Linux_${ARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin && chmod +x /usr/local/bin/goplaces \
    || echo "Warning: goplaces installation failed (optional dependency)"

# Install wacli (WhatsApp CLI)
RUN ARCH=$(cat /tmp/arch) && \
    curl -L "https://github.com/steipete/wacli/releases/latest/download/wacli_Linux_${ARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin && chmod +x /usr/local/bin/wacli \
    || echo "Warning: wacli installation failed (optional dependency)"

# Create app user for security
RUN groupadd -r clawdbot && useradd -r -g clawdbot -d /home/clawdbot -s /bin/bash clawdbot
RUN mkdir -p /home/clawdbot && chown -R clawdbot:clawdbot /home/clawdbot

# Set working directory
WORKDIR /app

# Enable corepack for pnpm
RUN corepack enable

# Clone and build Clawdbot from source
RUN git clone --depth 1 https://github.com/clawdbot/clawdbot.git . && \
    pnpm install && \
    pnpm build && \
    pnpm ui:install && \
    pnpm ui:build

# Create directories for persistent data and set ownership
RUN mkdir -p /data/.clawdbot /data/clawd && \
    chown -R clawdbot:clawdbot /data && \
    chown -R clawdbot:clawdbot /app

# Environment variables
ENV NODE_ENV=production
ENV HOME=/home/clawdbot
ENV CLAWDBOT_CONFIG_PATH=/data/.clawdbot/clawdbot.json
ENV CLAWDBOT_STATE_DIR=/data/.clawdbot
ENV XDG_CONFIG_HOME=/data/.clawdbot

# Expose ports
# 18789 - Gateway WebSocket + HTTP (Control UI)
# 18793 - Canvas host
EXPOSE 18789 18793

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:18789/health || exit 1

# Switch to non-root user for security
USER clawdbot

# Default command
# --allow-unconfigured: start without pre-existing config file
# --no-auth: allow gateway to start without requiring a gateway token (auth handled by Coolify/Traefik)
CMD ["node", "dist/index.js", "gateway", "--bind", "lan", "--port", "18789", "--allow-unconfigured", "--no-auth"]
