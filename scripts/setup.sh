#!/bin/bash
# =============================================================================
# OpenClaw Coolify Setup Script
# =============================================================================
# This script helps configure OpenClaw after deployment on Coolify.
# Run this script on your Coolify server after the initial deployment.
#
# Usage: ./scripts/setup.sh
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored message
print_msg() {
    echo -e "${2}${1}${NC}"
}

print_header() {
    echo ""
    echo -e "${BLUE}=================================================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}=================================================================${NC}"
    echo ""
}

print_success() {
    print_msg "✓ $1" "$GREEN"
}

print_warning() {
    print_msg "⚠ $1" "$YELLOW"
}

print_error() {
    print_msg "✗ $1" "$RED"
}

# Check if running as root or with docker access
check_docker_access() {
    if ! docker ps > /dev/null 2>&1; then
        print_error "Cannot access Docker. Please run with sudo or add your user to the docker group."
        exit 1
    fi
}

# Check if containers are running
check_containers() {
    print_header "Checking Container Status"
    
    local containers=("openclaw-gateway" "openclaw-redis" "openclaw-browser")
    local all_running=true
    
    for container in "${containers[@]}"; do
        if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
            print_success "$container is running"
        else
            print_error "$container is not running"
            all_running=false
        fi
    done
    
    if [ "$all_running" = false ]; then
        print_warning "Some containers are not running. Please check your deployment."
        return 1
    fi
    
    return 0
}

# Check gateway health
check_gateway_health() {
    print_header "Checking Gateway Health"
    
    if docker exec openclaw-gateway curl -sf http://localhost:18789/health > /dev/null 2>&1; then
        print_success "Gateway is healthy"
        return 0
    else
        print_warning "Gateway health check failed. It may still be starting up."
        return 1
    fi
}

# Run openclaw doctor
run_doctor() {
    print_header "Running OpenClaw Doctor"
    docker exec openclaw-gateway node dist/index.js doctor 2>/dev/null || \
        docker exec openclaw-gateway openclaw doctor 2>/dev/null || \
        print_warning "Could not run doctor command"
}

# Show status
show_status() {
    print_header "OpenClaw Status"
    docker exec openclaw-gateway node dist/index.js status 2>/dev/null || \
        docker exec openclaw-gateway openclaw status 2>/dev/null || \
        print_warning "Could not get status"
}

# Configure WhatsApp
configure_whatsapp() {
    print_header "WhatsApp Configuration"
    
    echo "WhatsApp requires scanning a QR code to link your account."
    echo ""
    read -p "Do you want to configure WhatsApp now? (y/n): " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        echo "Starting WhatsApp login... Scan the QR code with your phone."
        echo "(WhatsApp → Settings → Linked Devices → Link a Device)"
        echo ""
        docker exec -it openclaw-gateway node dist/index.js channels login 2>/dev/null || \
            docker exec -it openclaw-gateway openclaw channels login
    else
        print_msg "Skipping WhatsApp configuration. You can run this later with:" "$YELLOW"
        echo "  docker exec -it openclaw-gateway openclaw channels login"
    fi
}

# Show configured channels
show_channels() {
    print_header "Configured Channels"
    
    # Check environment variables
    if docker exec openclaw-gateway printenv TELEGRAM_BOT_TOKEN 2>/dev/null | grep -q .; then
        print_success "Telegram: Configured"
    else
        print_msg "Telegram: Not configured" "$YELLOW"
    fi
    
    if docker exec openclaw-gateway printenv DISCORD_BOT_TOKEN 2>/dev/null | grep -q .; then
        print_success "Discord: Configured"
    else
        print_msg "Discord: Not configured" "$YELLOW"
    fi
    
    if docker exec openclaw-gateway printenv SLACK_BOT_TOKEN 2>/dev/null | grep -q .; then
        print_success "Slack: Configured"
    else
        print_msg "Slack: Not configured" "$YELLOW"
    fi
    
    print_msg "WhatsApp: Requires QR scan (run channel-login.sh)" "$YELLOW"
    print_success "WebChat: Available at your domain"
}

# Show next steps
show_next_steps() {
    print_header "Next Steps"
    
    echo "1. Access the Control UI at your configured domain"
    echo "   Enter your OPENCLAW_GATEWAY_TOKEN to authenticate"
    echo ""
    echo "2. Configure additional channels if needed:"
    echo "   - WhatsApp: ./scripts/channel-login.sh"
    echo "   - Add tokens via Coolify environment variables"
    echo ""
    echo "3. Start chatting! Send a message via any configured channel."
    echo ""
    echo "Useful commands:"
    echo "  docker exec openclaw-gateway openclaw status"
    echo "  docker exec openclaw-gateway openclaw health"
    echo "  docker exec openclaw-gateway openclaw doctor"
    echo "  docker logs openclaw-gateway"
    echo ""
    print_msg "Documentation: https://docs.openclaw.ai" "$BLUE"
}

# Main
main() {
    print_header "OpenClaw Coolify Setup"
    
    check_docker_access
    
    if check_containers; then
        check_gateway_health
        run_doctor
        show_status
        show_channels
        configure_whatsapp
    fi
    
    show_next_steps
}

main "$@"
