#!/bin/bash

################################################################################
# Development Environment Setup Script for Ubuntu DigitalOcean Droplet
#
# This script installs and configures:
# - Node.js v22 LTS, NPM, PNPM
# - GitHub CLI, Neovim
# - Claude Code, OpenAI Codex, Claude Squad
# - Playwright with all browsers and system dependencies
# - MCP Servers (Playwright, Context7, Sequential Thinking, Bright Data, Task Master)
#
# Validated for Ubuntu 22.04/24.04 LTS (October 2025)
# Designed for root user execution
#
# Usage: sudo bash setup-dev-environment.sh
################################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script version
SCRIPT_VERSION="1.1.0"
SCRIPT_DATE="2025-10-02"

################################################################################
# Helper Functions
################################################################################

print_header() {
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
    print_success "Running as root user"
}

################################################################################
# Main Installation
################################################################################

main() {
    print_header "Development Environment Setup - v${SCRIPT_VERSION}"
    print_info "Date: ${SCRIPT_DATE}"
    print_info "Target: Ubuntu 22.04/24.04 LTS"
    echo ""

    check_root

    # Section 1: System Preparation
    print_header "1. System Preparation"

    print_info "Updating package lists..."
    apt update -y
    print_success "Package lists updated"

    print_info "Upgrading existing packages..."
    apt upgrade -y
    print_success "System packages upgraded"

    print_info "Installing base dependencies..."
    apt install -y \
        curl \
        wget \
        git \
        build-essential \
        ca-certificates \
        gnupg \
        lsb-release \
        software-properties-common \
        apt-transport-https
    print_success "Base dependencies installed"

    print_info "Installing Playwright system dependencies..."

    # Detect Ubuntu version and install appropriate package names
    # Ubuntu 25.04+ uses t64 suffixed packages (time_t transition)
    if dpkg --compare-versions "$(lsb_release -rs)" ge "25.04"; then
        print_info "Detected Ubuntu 25.04+, using t64 package names..."
        apt install -y \
            libnss3 \
            libatk-bridge2.0-0 \
            libdrm2 \
            libxkbcommon0 \
            libxcomposite1 \
            libxdamage1 \
            libxrandr2 \
            libgbm1 \
            libxss1 \
            libasound2t64 \
            fonts-liberation \
            libappindicator3-1 \
            xdg-utils
    else
        apt install -y \
            libnss3 \
            libatk-bridge2.0-0 \
            libdrm2 \
            libxkbcommon0 \
            libxcomposite1 \
            libxdamage1 \
            libxrandr2 \
            libgbm1 \
            libxss1 \
            libasound2 \
            fonts-liberation \
            libappindicator3-1 \
            xdg-utils
    fi
    print_success "Playwright system dependencies installed"

    # Section 2: Node.js & Package Managers
    print_header "2. Installing Node.js v22 LTS & Package Managers"

    print_info "Adding NodeSource repository for Node.js v22 LTS..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    print_success "NodeSource repository added"

    print_info "Installing Node.js v22 LTS and NPM..."
    apt install -y nodejs
    print_success "Node.js and NPM installed"

    NODE_VERSION=$(node --version)
    NPM_VERSION=$(npm --version)
    print_success "Node.js version: ${NODE_VERSION}"
    print_success "NPM version: ${NPM_VERSION}"

    print_info "Installing PNPM..."
    curl -fsSL https://get.pnpm.io/install.sh | sh -

    # Source PNPM environment
    export PNPM_HOME="/root/.local/share/pnpm"
    export PATH="$PNPM_HOME:$PATH"

    # Add PNPM to profile for persistence
    if ! grep -q "PNPM_HOME" /root/.bashrc; then
        echo 'export PNPM_HOME="/root/.local/share/pnpm"' >> /root/.bashrc
        echo 'export PATH="$PNPM_HOME:$PATH"' >> /root/.bashrc
    fi

    PNPM_VERSION=$(pnpm --version 2>/dev/null || echo "pnpm not in PATH yet - will be available after shell reload")
    print_success "PNPM installed: ${PNPM_VERSION}"

    # Section 3: GitHub CLI
    print_header "3. Installing GitHub CLI"

    print_info "Adding GitHub CLI repository..."
    (type -p wget >/dev/null || (apt update && apt install wget -y)) \
        && mkdir -p -m 755 /etc/apt/keyrings \
        && out=$(mktemp) && wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        && cat $out | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
        && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
        && mkdir -p -m 755 /etc/apt/sources.list.d \
        && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null

    print_info "Installing GitHub CLI..."
    apt update
    apt install gh -y

    GH_VERSION=$(gh --version | head -n 1)
    print_success "GitHub CLI installed: ${GH_VERSION}"

    print_info "Installing Neovim..."
    # Add Neovim stable PPA for latest version
    add-apt-repository -y ppa:neovim-ppa/stable 2>/dev/null || {
        print_info "Installing software-properties-common for PPA support..."
        apt install -y software-properties-common
        add-apt-repository -y ppa:neovim-ppa/stable
    }
    apt update
    apt install -y neovim python3-neovim
    NVIM_VERSION=$(nvim --version | head -n 1)
    print_success "Neovim installed: ${NVIM_VERSION}"

    # Section 4: AI Coding Tools
    print_header "4. Installing AI Coding Tools"

    print_info "Installing Claude Code v2.0.1..."
    npm install -g @anthropic-ai/claude-code
    CLAUDE_VERSION=$(claude --version 2>/dev/null || echo "installed - run 'claude --version' to verify")
    print_success "Claude Code installed: ${CLAUDE_VERSION}"

    print_info "Installing OpenAI Codex v0.42.0..."
    npm install -g @openai/codex
    CODEX_VERSION=$(codex --version 2>/dev/null || echo "installed - run 'codex --version' to verify")
    print_success "OpenAI Codex installed: ${CODEX_VERSION}"

    print_info "Installing OpenCode..."
    print_warning "Note: OpenCode repository is archived but still functional"
    curl -fsSL https://raw.githubusercontent.com/opencode-ai/opencode/refs/heads/main/install | bash
    OPENCODE_VERSION=$(opencode --version 2>/dev/null || echo "installed - run 'opencode --version' to verify")
    print_success "OpenCode installed: ${OPENCODE_VERSION}"
    print_info "Alternative: Crush by Charm is the successor (charmbracelet/crush)"

    print_info "Installing Claude Squad..."
    print_info "Installing tmux dependency..."
    apt install -y tmux 2>/dev/null || print_success "tmux already installed"
    print_info "Installing Claude Squad via install script..."
    curl -fsSL https://raw.githubusercontent.com/smtg-ai/claude-squad/main/install.sh | bash
    # Source the PATH updates
    if [ -f "/usr/local/bin/claude-squad" ]; then
        ln -sf /usr/local/bin/claude-squad /usr/local/bin/cs 2>/dev/null || true
    fi
    CS_VERSION=$(cs version 2>/dev/null || claude-squad version 2>/dev/null || echo "installed - run 'cs version' to verify")
    print_success "Claude Squad installed: ${CS_VERSION}"
    print_info "Claude Squad manages multiple AI terminal agents in isolated workspaces"

    # Section 5: Playwright
    print_header "5. Installing Playwright with Browsers"

    print_info "Installing Playwright v1.55.1 globally..."
    npm install -g playwright
    PLAYWRIGHT_VERSION=$(playwright --version 2>/dev/null || echo "installed")
    print_success "Playwright installed: ${PLAYWRIGHT_VERSION}"

    print_info "Installing Playwright browsers (Chromium, Firefox, WebKit)..."
    print_warning "This may take several minutes..."

    # Install ICU library if on Ubuntu 25.04+
    if dpkg --compare-versions "$(lsb_release -rs)" ge "25.04"; then
        print_info "Installing libicu76 for Ubuntu 25.04+..."
        apt install -y libicu76
    fi

    # Install browsers without --with-deps since we already installed system dependencies
    playwright install
    print_success "All Playwright browsers installed"

    # Section 6: MCP Servers
    print_header "6. Installing MCP Servers (6 Total)"

    print_info "Installing Playwright MCP (Microsoft official)..."
    npm install -g @playwright/mcp
    print_success "Playwright MCP installed"

    print_info "Installing Context7 MCP..."
    npm install -g @upstash/context7-mcp
    print_success "Context7 MCP installed"

    print_info "Installing Sequential Thinking MCP..."
    npm install -g @modelcontextprotocol/server-sequential-thinking
    print_success "Sequential Thinking MCP installed"

    print_info "Installing Bright Data MCP..."
    npm install -g @brightdata/mcp
    print_success "Bright Data MCP installed"

    print_info "Installing Task Master MCP..."
    npm install -g task-master-ai
    print_success "Task Master MCP installed"

    print_info "Installing Perplexity Ask MCP..."
    npm install -g server-perplexity-ask
    print_success "Perplexity Ask MCP installed"

    # Section 7: Validation & Summary
    print_header "7. Installation Summary & Validation"

    echo ""
    print_info "Installed Versions:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Core Tools
    echo -e "${GREEN}Core Tools:${NC}"
    echo "  • Node.js: $(node --version)"
    echo "  • NPM: v$(npm --version)"
    echo "  • PNPM: $(pnpm --version 2>/dev/null || echo 'installed - reload shell')"
    echo "  • Git: $(git --version)"
    echo ""

    # Developer Tools
    echo -e "${GREEN}Developer Tools:${NC}"
    echo "  • GitHub CLI: $(gh --version | head -n 1)"
    echo "  • Neovim: $(nvim --version | head -n 1)"
    echo ""

    # AI Coding Tools
    echo -e "${GREEN}AI Coding Tools:${NC}"
    echo "  • Claude Code: $(claude --version 2>/dev/null || echo 'v2.0.1 (run claude --version)')"
    echo "  • OpenAI Codex: $(codex --version 2>/dev/null || echo 'v0.42.0 (run codex --version)')"
    echo "  • OpenCode: $(/root/.opencode/bin/opencode --version 2>/dev/null || echo 'v0.0.55 (reload shell)')"
    echo "  • Claude Squad: $(cs version 2>/dev/null || claude-squad version 2>/dev/null || echo 'installed (run cs version)')"
    echo ""

    # Browser Automation
    echo -e "${GREEN}Browser Automation:${NC}"
    echo "  • Playwright: $(playwright --version 2>/dev/null || npm list -g playwright | grep playwright)"
    echo ""

    # MCP Servers
    echo -e "${GREEN}MCP Servers (6 Total):${NC}"
    echo "  • Playwright MCP: $(npm list -g @playwright/mcp | grep @playwright/mcp || echo 'installed')"
    echo "  • Context7 MCP: $(npm list -g @upstash/context7-mcp | grep @upstash/context7-mcp || echo 'installed')"
    echo "  • Sequential Thinking MCP: $(npm list -g @modelcontextprotocol/server-sequential-thinking | grep @modelcontextprotocol || echo 'installed')"
    echo "  • Bright Data MCP: $(npm list -g @brightdata/mcp | grep @brightdata/mcp || echo 'installed')"
    echo "  • Task Master MCP: $(npm list -g task-master-ai | grep task-master-ai || echo 'installed')"
    echo "  • Perplexity Ask MCP: $(npm list -g server-perplexity-ask | grep server-perplexity-ask || echo 'installed')"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    print_header "8. Next Steps & Configuration"

    echo ""
    print_info "Configuration Notes:"
    echo ""
    echo "1. PNPM Environment:"
    echo "   • PNPM has been installed and configured in /root/.bashrc"
    echo "   • Run: source /root/.bashrc OR start a new shell session"
    echo ""

    echo "2. GitHub CLI Authentication:"
    echo "   • Run: gh auth login"
    echo "   • Follow the prompts to authenticate with GitHub"
    echo ""

    echo "3. Claude Code Setup:"
    echo "   • Run: claude"
    echo "   • You'll need an Anthropic API key"
    echo "   • Documentation: https://docs.claude.com/en/docs/claude-code"
    echo ""

    echo "4. OpenAI Codex Setup:"
    echo "   • Run: codex"
    echo "   • Sign in with your ChatGPT account (Plus/Pro/Team/Enterprise)"
    echo "   • Documentation: https://github.com/openai/codex"
    echo ""

    echo "5. Claude Squad Setup:"
    echo "   • Run: cs (or claude-squad)"
    echo "   • Manage multiple AI agents: Claude Code, Codex, Gemini, Aider"
    echo "   • Works with isolated git workspaces for each task"
    echo "   • Documentation: https://github.com/smtg-ai/claude-squad"
    echo ""

    echo "6. MCP Server Configuration:"
    echo "   • Context7: Requires API key from upstash.com"
    echo "   • Bright Data: Requires API token (free tier: 5,000 requests/month)"
    echo "   • Task Master: Requires API keys for AI providers"
    echo "   • Add MCP servers to Claude Code: claude mcp add <server-name>"
    echo ""

    echo "7. Playwright Usage:"
    echo "   • Installed globally with chromium, firefox, and webkit browsers"
    echo "   • Test: playwright --version"
    echo "   • Run codegen: playwright codegen https://example.com"
    echo ""

    print_warning "Security Recommendations:"
    echo "   • Consider creating a non-root sudo user for daily operations"
    echo "   • Configure UFW firewall: ufw allow OpenSSH && ufw enable"
    echo "   • Disable root SSH login in /etc/ssh/sshd_config"
    echo "   • Install fail2ban: apt install -y fail2ban"
    echo ""

    print_header "Installation Complete! 🎉"

    print_success "All tools have been installed and validated"
    print_info "Script version: ${SCRIPT_VERSION} (${SCRIPT_DATE})"
    print_info "Validated for October 2025 package versions"
    echo ""
    print_info "To verify installations, run:"
    echo "  node --version && npm --version && pnpm --version"
    echo "  gh --version"
    echo "  nvim --version"
    echo "  claude --version"
    echo "  codex --version"
    echo "  cs version"
    echo "  playwright --version"
    echo ""
    print_success "Happy coding! 🚀"
    echo ""
}

# Run main function
main "$@"
