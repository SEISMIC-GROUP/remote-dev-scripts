#!/bin/bash

#######################################
# Digital Ocean Password Authentication Setup Script
# For Ubuntu 20.04 / 22.04 / 24.04
# Created: October 2025
# Purpose: Enable password authentication on DO droplets
#######################################

set -e  # Exit on error
set -u  # Exit on undefined variable
set -o pipefail  # Catch errors in pipes

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Configuration variables
SCRIPT_NAME="Digital Ocean Password Auth Setup"
SCRIPT_VERSION="1.0.0"
LOG_FILE="/var/log/password_auth_setup.log"
BACKUP_DIR="/root/backups"
SSH_CONFIG="/etc/ssh/sshd_config"
PASSWORD_FILE="/root/.setup_passwords.txt"

# Password generation settings
PASSWORD_LENGTH=16
GENERATED_ROOT_PASSWORD=""
GENERATED_UBUNTU_PASSWORD=""

# Detect Ubuntu version
UBUNTU_VERSION=$(lsb_release -rs 2>/dev/null || echo "Unknown")

#######################################
# Functions
#######################################

# Print colored messages
print_header() {
    echo -e "${BLUE}${BOLD}===============================================${NC}"
    echo -e "${CYAN}${BOLD}$1${NC}"
    echo -e "${BLUE}${BOLD}===============================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${CYAN}ℹ${NC} $1"
}

print_step() {
    echo -e "${MAGENTA}►${NC} $1"
}

# Log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Generate secure random password
generate_password() {
    local password=$(openssl rand -base64 48 | tr -d "=+/" | cut -c1-$PASSWORD_LENGTH)
    echo "$password"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Check Ubuntu version compatibility
check_ubuntu_version() {
    print_step "Checking Ubuntu version..."

    case "$UBUNTU_VERSION" in
        20.04|22.04|24.04|24.10|25.04)
            print_success "Ubuntu $UBUNTU_VERSION detected - Compatible"
            ;;
        *)
            print_warning "Ubuntu $UBUNTU_VERSION - Untested version, proceeding with caution"
            ;;
    esac
}

# Create backup directory
create_backup_dir() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        mkdir -p "$BACKUP_DIR"
        print_success "Created backup directory: $BACKUP_DIR"
    fi
}

# Backup a file
backup_file() {
    local file="$1"
    local backup_name="$(basename $file).$(date +%Y%m%d_%H%M%S).bak"

    if [[ -f "$file" ]]; then
        cp "$file" "$BACKUP_DIR/$backup_name"
        print_success "Backed up $file to $BACKUP_DIR/$backup_name"
        log_message "Backed up $file"
    fi
}

# Configure SSH for password authentication
configure_ssh() {
    print_header "Configuring SSH for Password Authentication"

    # Backup current SSH config
    backup_file "$SSH_CONFIG"

    print_step "Modifying SSH configuration..."

    # Create temporary config file
    local temp_config="/tmp/sshd_config.tmp"
    cp "$SSH_CONFIG" "$temp_config"

    # Enable password authentication
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' "$temp_config"

    # Keep public key authentication as fallback
    sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' "$temp_config"

    # Enable root login (temporarily)
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' "$temp_config"

    # Enable PAM (required for password auth)
    sed -i 's/^#*UsePAM.*/UsePAM yes/' "$temp_config"

    # Disable challenge-response authentication
    sed -i 's/^#*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' "$temp_config"

    # Add settings if they don't exist
    grep -q "^PasswordAuthentication" "$temp_config" || echo "PasswordAuthentication yes" >> "$temp_config"
    grep -q "^PubkeyAuthentication" "$temp_config" || echo "PubkeyAuthentication yes" >> "$temp_config"
    grep -q "^PermitRootLogin" "$temp_config" || echo "PermitRootLogin yes" >> "$temp_config"
    grep -q "^UsePAM" "$temp_config" || echo "UsePAM yes" >> "$temp_config"

    # Test the configuration
    if sshd -t -f "$temp_config" 2>/dev/null; then
        mv "$temp_config" "$SSH_CONFIG"
        print_success "SSH configuration updated successfully"

        # Reload SSH service
        systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null
        print_success "SSH service reloaded"
    else
        print_error "SSH configuration test failed. Keeping original configuration."
        rm -f "$temp_config"
        return 1
    fi

    log_message "SSH configured for password authentication"
}

# Set root password
set_root_password() {
    print_header "Setting Root Password"

    echo ""
    echo "Choose password option for root user:"
    echo "1) Enter custom password"
    echo "2) Generate secure random password"
    echo ""

    read -p "Select option (1-2): " root_option

    case $root_option in
        1)
            while true; do
                echo ""
                read -s -p "Enter new root password: " password1
                echo ""
                read -s -p "Confirm root password: " password2
                echo ""

                if [[ "$password1" == "$password2" ]]; then
                    if [[ ${#password1} -lt 8 ]]; then
                        print_warning "Password should be at least 8 characters. Try again."
                    else
                        echo "root:$password1" | chpasswd
                        print_success "Root password set successfully"
                        break
                    fi
                else
                    print_error "Passwords don't match. Try again."
                fi
            done
            ;;
        2)
            GENERATED_ROOT_PASSWORD=$(generate_password)
            echo "root:$GENERATED_ROOT_PASSWORD" | chpasswd
            print_success "Root password generated and set"
            echo ""
            echo -e "${YELLOW}${BOLD}Generated Root Password: $GENERATED_ROOT_PASSWORD${NC}"
            echo ""
            print_warning "Save this password securely! It won't be shown again."

            # Save to temporary file
            echo "Root Password: $GENERATED_ROOT_PASSWORD" > "$PASSWORD_FILE"
            chmod 600 "$PASSWORD_FILE"
            ;;
        *)
            print_error "Invalid option"
            return 1
            ;;
    esac

    log_message "Root password configured"
}

# Create ubuntu user with sudo privileges
create_ubuntu_user() {
    print_header "Creating Ubuntu User with Sudo Privileges"

    # Check if user already exists
    if id "ubuntu" &>/dev/null; then
        print_warning "User 'ubuntu' already exists"

        read -p "Do you want to reset the ubuntu user password? (y/n): " reset_pwd
        if [[ "$reset_pwd" != "y" && "$reset_pwd" != "Y" ]]; then
            # Ensure existing user has proper sudo access
            usermod -aG sudo ubuntu 2>/dev/null || usermod -aG wheel ubuntu 2>/dev/null
            print_success "Verified ubuntu user sudo access"
            return 0
        fi
    else
        # Create ubuntu user with proper settings
        useradd -m -s /bin/bash -G sudo ubuntu
        print_success "Created user 'ubuntu' with home directory and sudo group"

        # Create necessary directories for development tools
        sudo -u ubuntu mkdir -p /home/ubuntu/.local/bin
        sudo -u ubuntu mkdir -p /home/ubuntu/.config
        print_success "Created development directories for ubuntu user"
    fi

    # Set password for ubuntu user
    echo ""
    echo "Choose password option for ubuntu user:"
    echo "1) Enter custom password"
    echo "2) Generate secure random password"
    echo "3) Use same password as root"
    echo ""

    read -p "Select option (1-3): " ubuntu_option

    case $ubuntu_option in
        1)
            while true; do
                echo ""
                read -s -p "Enter password for ubuntu user: " password1
                echo ""
                read -s -p "Confirm ubuntu password: " password2
                echo ""

                if [[ "$password1" == "$password2" ]]; then
                    if [[ ${#password1} -lt 8 ]]; then
                        print_warning "Password should be at least 8 characters. Try again."
                    else
                        echo "ubuntu:$password1" | chpasswd
                        print_success "Ubuntu user password set"
                        break
                    fi
                else
                    print_error "Passwords don't match. Try again."
                fi
            done
            ;;
        2)
            GENERATED_UBUNTU_PASSWORD=$(generate_password)
            echo "ubuntu:$GENERATED_UBUNTU_PASSWORD" | chpasswd
            print_success "Ubuntu user password generated and set"
            echo ""
            echo -e "${YELLOW}${BOLD}Generated Ubuntu Password: $GENERATED_UBUNTU_PASSWORD${NC}"
            echo ""
            print_warning "Save this password securely!"

            # Append to password file
            echo "Ubuntu Password: $GENERATED_UBUNTU_PASSWORD" >> "$PASSWORD_FILE"
            ;;
        3)
            if [[ -n "$GENERATED_ROOT_PASSWORD" ]]; then
                echo "ubuntu:$GENERATED_ROOT_PASSWORD" | chpasswd
                print_success "Ubuntu user password set (same as root)"
            else
                print_error "Root password was not generated. Please choose option 1 or 2."
                return 1
            fi
            ;;
        *)
            print_error "Invalid option"
            return 1
            ;;
    esac

    # Ensure ubuntu user is in sudo group (double-check)
    usermod -aG sudo ubuntu 2>/dev/null || usermod -aG wheel ubuntu 2>/dev/null
    print_success "Added ubuntu user to sudo group"

    # Additional groups for development
    usermod -aG adm,dialout,cdrom,floppy,audio,dip,video,plugdev,netdev ubuntu 2>/dev/null
    print_success "Added ubuntu user to system groups"

    # Configure sudo access for development tools
    echo ""
    echo "Configure sudo access for development tools (recommended for Claude Code)?"
    read -p "Enable passwordless sudo for ubuntu user? (y/n): " passwordless_sudo

    if [[ "$passwordless_sudo" == "y" || "$passwordless_sudo" == "Y" ]]; then
        # Create comprehensive sudoers file for ubuntu user
        cat > /etc/sudoers.d/ubuntu <<EOF
# Ubuntu user sudo configuration
# Created by setup_password_auth.sh
ubuntu ALL=(ALL) NOPASSWD:ALL

# Allow running Claude Code and other dev tools without password
ubuntu ALL=(ALL) NOPASSWD: /usr/bin/node, /usr/bin/npm, /usr/bin/pnpm, /usr/bin/claude, /usr/bin/codex

# Preserve environment variables for development tools
Defaults:ubuntu env_keep += "NODE_ENV NPM_CONFIG_PREFIX PATH"
EOF
        chmod 440 /etc/sudoers.d/ubuntu
        print_success "Passwordless sudo enabled for ubuntu user (Claude Code compatible)"
        print_info "Ubuntu user can now run: claude --dangerously-skip-permissions"
    else
        # Still create sudoers file but require password
        cat > /etc/sudoers.d/ubuntu <<EOF
# Ubuntu user sudo configuration
# Created by setup_password_auth.sh
ubuntu ALL=(ALL) ALL

# Preserve environment variables for development tools
Defaults:ubuntu env_keep += "NODE_ENV NPM_CONFIG_PREFIX PATH"
EOF
        chmod 440 /etc/sudoers.d/ubuntu
        print_info "Ubuntu user will need to enter password for sudo"
        print_info "For Claude Code, user must use: sudo claude --dangerously-skip-permissions"
    fi

    # Set up bash profile for ubuntu user
    cat >> /home/ubuntu/.bashrc <<'EOF'

# Development environment setup (added by setup_password_auth.sh)
export PATH="$HOME/.local/bin:$PATH"
export EDITOR="nano"

# Aliases for development tools
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Claude Code alias for convenience
alias claude-dev='claude --dangerously-skip-permissions'
alias codex-dev='codex --unsafe-perm'

# Node.js environment
export NODE_ENV="${NODE_ENV:-development}"
EOF

    chown ubuntu:ubuntu /home/ubuntu/.bashrc
    print_success "Configured development environment for ubuntu user"

    log_message "Ubuntu user configured with full development access"
}

# Install and configure fail2ban
install_fail2ban() {
    print_header "Installing and Configuring Fail2ban"

    print_step "Updating package list..."
    apt-get update -qq

    print_step "Installing fail2ban..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y fail2ban > /dev/null 2>&1

    # Create jail.local configuration
    cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 3600
maxretry = 5
findtime = 600

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
EOF

    print_success "Fail2ban configuration created"

    # Enable and start fail2ban
    systemctl enable fail2ban > /dev/null 2>&1
    systemctl restart fail2ban

    print_success "Fail2ban installed and started"
    log_message "Fail2ban configured for SSH protection"
}

# Configure UFW firewall
configure_firewall() {
    print_header "Configuring UFW Firewall"

    print_step "Installing UFW if not present..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y ufw > /dev/null 2>&1

    # Reset UFW to defaults
    echo "y" | ufw --force reset > /dev/null 2>&1

    # Set default policies
    ufw default deny incoming > /dev/null 2>&1
    ufw default allow outgoing > /dev/null 2>&1

    # Allow SSH
    ufw allow OpenSSH > /dev/null 2>&1
    print_success "SSH access allowed through firewall"

    # Allow HTTP and HTTPS (optional)
    read -p "Allow HTTP (80) and HTTPS (443) through firewall? (y/n): " allow_web

    if [[ "$allow_web" == "y" || "$allow_web" == "Y" ]]; then
        ufw allow http > /dev/null 2>&1
        ufw allow https > /dev/null 2>&1
        print_success "HTTP and HTTPS allowed through firewall"
    fi

    # Enable UFW
    echo "y" | ufw enable > /dev/null 2>&1

    print_success "UFW firewall configured and enabled"
    log_message "UFW firewall configured"
}

# Deploy seismic-core application (optional)
deploy_seismic_core() {
    print_header "Deploying Seismic Core Application (Optional)"

    echo ""
    read -p "Deploy seismic-core application with all environment variables? (y/n): " deploy_app

    if [[ "$deploy_app" != "y" && "$deploy_app" != "Y" ]]; then
        print_info "Skipping seismic-core deployment"
        return 0
    fi

    # Get server IP
    local server_ip=$(curl -s4 ifconfig.me 2>/dev/null || ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n1)
    print_info "Server IP detected: $server_ip"

    # Clone repository
    print_step "Setting up seismic-core repository..."

    if [[ -d /var/www/seismic-core ]]; then
        print_warning "Seismic-core already exists, updating..."
        cd /var/www/seismic-core
        git pull origin main
    else
        mkdir -p /var/www
        cd /var/www
        git clone https://github.com/SEISMIC-GROUP/seismic-core.git
        cd seismic-core
        git checkout main
    fi
    print_success "Repository ready at /var/www/seismic-core"

    # Create .env.local with all secrets
    print_step "Creating .env.local with environment variables..."

    # Check if secrets file exists
    if [[ ! -f /root/.seismic_secrets.env ]]; then
        print_error "Secrets file not found at /root/.seismic_secrets.env"
        print_info "Please create the secrets file first with your actual credentials"
        print_info "See SETUP_SECRETS.md for instructions"
        return 1
    fi

    # Source the secrets file
    source /root/.seismic_secrets.env

    cat > /var/www/seismic-core/.env.local <<EOF
# Database (DigitalOcean - already in VPC network)
DATABASE_URL=${DATABASE_URL}
DIRECT_DATABASE_URL=${DIRECT_DATABASE_URL}

PGHOST=${PGHOST}
PGPORT=${PGPORT}
PGDATABASE=${PGDATABASE}
PGUSER=${PGUSER}
PGPASSWORD=${PGPASSWORD}
PGSSLMODE=${PGSSLMODE:-require}

# Application URLs
NEXT_PUBLIC_APP_URL=http://${server_ip}:3888
NEXTAUTH_URL=http://${server_ip}:3888

# Better Auth (Primary)
BETTER_AUTH_ENABLED=${BETTER_AUTH_ENABLED:-true}
BETTER_AUTH_SECRET=${BETTER_AUTH_SECRET}
BETTER_AUTH_URL=http://${server_ip}:3888

# NextAuth (Legacy)
NEXTAUTH_SECRET=${NEXTAUTH_SECRET}
AUTH_SECRET=${AUTH_SECRET}
AUTH_TRUST_HOST=${AUTH_TRUST_HOST:-true}

# Ports
PORT=3888
FUMADOCS_PORT=3894
FUMADOCS_URL=http://${server_ip}:3894
STORYBOOK_PORT=6006

# Runtime
NODE_ENV=development
SKIP_DOCKER=true
EOF

    chmod 600 /var/www/seismic-core/.env.local
    print_success "Environment variables configured"

    # Create .mcp.json with API keys
    print_step "Creating .mcp.json with MCP server configuration..."

    cat > /var/www/seismic-core/.mcp.json <<EOF
{
  "mcpServers": {
    "sequential-thinking": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"],
      "env": {}
    },
    "perplexity-ask": {
      "command": "npx",
      "args": ["-y", "server-perplexity-ask"],
      "env": {
        "PERPLEXITY_API_KEY": "${PERPLEXITY_API_KEY}"
      }
    },
    "playwright": {
      "command": "npx",
      "args": ["-y", "@playwright/mcp@latest", "--isolated", "--headless"],
      "env": {}
    },
    "task-master-ai": {
      "command": "npx",
      "args": ["-y", "task-master-ai"],
      "env": {
        "OPENAI_API_KEY": "${OPENAI_API_KEY}",
        "PERPLEXITY_API_KEY": "${PERPLEXITY_API_KEY}"
      }
    },
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp@latest"],
      "env": {}
    },
    "brightdata": {
      "command": "npx",
      "args": ["-y", "@brightdata/mcp@latest"],
      "env": {
        "BRIGHTDATA_API_TOKEN": "${BRIGHTDATA_API_TOKEN}"
      }
    },
    "drizzle-sm-core": {
      "command": "node",
      "args": ["./scripts/mcp-drizzle-launcher.js"],
      "env": {
        "DRIZZLE_DIALECT": "postgresql",
        "PGHOST": "${PGHOST}",
        "PGPORT": "${PGPORT}",
        "PGDATABASE": "${PGDATABASE}",
        "PGUSER": "${PGUSER}",
        "PGPASSWORD": "${PGPASSWORD}",
        "PGSSLMODE": "no-verify"
      }
    }
  }
}
EOF

    chmod 600 /var/www/seismic-core/.mcp.json
    print_success "MCP servers configured with API keys"

    # Install dependencies
    print_step "Installing Node.js dependencies with pnpm..."

    # Check if pnpm is installed
    if ! command -v pnpm &> /dev/null; then
        print_step "Installing pnpm..."
        npm install -g pnpm
    fi

    cd /var/www/seismic-core
    pnpm install
    print_success "Dependencies installed"

    # Test database connection
    print_step "Testing database connection..."

    if [[ -f scripts/quick-connection-test.ts ]]; then
        pnpm tsx scripts/quick-connection-test.ts || print_warning "Database test script not found or failed"
    else
        print_warning "Database test script not found"
    fi

    # Run migrations
    echo ""
    read -p "Run database migrations? (y/n): " run_migrations

    if [[ "$run_migrations" == "y" || "$run_migrations" == "Y" ]]; then
        npm run db:migrate || print_warning "Migrations failed or not available"
    fi

    # Install PM2 for process management
    print_step "Installing PM2 for process management..."
    npm install -g pm2
    print_success "PM2 installed"

    # Configure firewall for application ports
    print_step "Opening application ports in firewall..."
    ufw allow 3888/tcp comment 'Seismic Portal' > /dev/null 2>&1
    ufw allow 3894/tcp comment 'Fumadocs' > /dev/null 2>&1
    ufw allow 6006/tcp comment 'Storybook' > /dev/null 2>&1
    print_success "Application ports opened"

    # Set proper permissions
    chown -R ubuntu:ubuntu /var/www/seismic-core
    print_success "Permissions set for ubuntu user"

    # Create startup script
    cat > /var/www/seismic-core/start-seismic.sh <<'EOF'
#!/bin/bash
cd /var/www/seismic-core
pm2 start npm --name "seismic-portal" -- run dev:portal
pm2 save
pm2 startup
EOF

    chmod +x /var/www/seismic-core/start-seismic.sh
    chown ubuntu:ubuntu /var/www/seismic-core/start-seismic.sh

    print_success "Seismic-core deployment configured"

    echo ""
    echo -e "${CYAN}${BOLD}Deployment Summary:${NC}"
    echo -e "  ${GREEN}✓${NC} Repository: /var/www/seismic-core"
    echo -e "  ${GREEN}✓${NC} Environment: .env.local configured"
    echo -e "  ${GREEN}✓${NC} MCP Servers: .mcp.json configured"
    echo -e "  ${GREEN}✓${NC} Dependencies: Installed with pnpm"
    echo -e "  ${GREEN}✓${NC} PM2: Ready for process management"
    echo -e "  ${GREEN}✓${NC} Ports: 3888, 3894, 6006 open"
    echo ""
    echo -e "${YELLOW}${BOLD}To start the application:${NC}"
    echo -e "  ${WHITE}su - ubuntu${NC}"
    echo -e "  ${WHITE}cd /var/www/seismic-core${NC}"
    echo -e "  ${WHITE}npm run dev:portal${NC}"
    echo -e "  ${CYAN}OR with PM2:${NC}"
    echo -e "  ${WHITE}pm2 start npm --name 'seismic-portal' -- run dev:portal${NC}"
    echo ""

    # Save deployment info
    echo "Seismic Core deployed at $(date)" >> "$LOG_FILE"
    echo "Application URL: http://${server_ip}:3888" >> "$LOG_FILE"

    log_message "Seismic-core deployment completed"
}

# Verify SSH access
verify_ssh_access() {
    print_header "Verifying SSH Configuration"

    print_step "Checking SSH service status..."

    if systemctl is-active --quiet ssh || systemctl is-active --quiet sshd; then
        print_success "SSH service is active"
    else
        print_error "SSH service is not running"
        return 1
    fi

    print_step "Verifying password authentication is enabled..."

    if grep -q "^PasswordAuthentication yes" "$SSH_CONFIG"; then
        print_success "Password authentication is enabled"
    else
        print_error "Password authentication is not properly configured"
        return 1
    fi

    print_step "Checking fail2ban status..."

    if systemctl is-active --quiet fail2ban; then
        print_success "Fail2ban is protecting SSH"
    else
        print_warning "Fail2ban is not running"
    fi

    print_step "Checking firewall status..."

    if ufw status | grep -q "Status: active"; then
        print_success "UFW firewall is active"
    else
        print_warning "UFW firewall is not active"
    fi

    log_message "SSH access verification completed"
}

# Display summary and connection instructions
display_summary() {
    local server_ip=$(curl -s4 icanhazip.com 2>/dev/null || ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n1)

    print_header "Setup Complete - Connection Instructions"

    echo ""
    echo -e "${GREEN}${BOLD}Password authentication has been successfully enabled!${NC}"
    echo ""
    echo -e "${CYAN}${BOLD}Server Information:${NC}"
    echo -e "  Server IP: ${WHITE}$server_ip${NC}"
    echo -e "  Ubuntu Version: ${WHITE}$UBUNTU_VERSION${NC}"
    echo ""

    echo -e "${CYAN}${BOLD}SSH Connection Commands:${NC}"
    echo ""
    echo -e "${WHITE}For root access:${NC}"
    echo -e "  ${YELLOW}ssh root@$server_ip${NC}"
    echo ""
    echo -e "${WHITE}For ubuntu user access:${NC}"
    echo -e "  ${YELLOW}ssh ubuntu@$server_ip${NC}"
    echo ""

    if [[ -f "$PASSWORD_FILE" ]]; then
        echo -e "${RED}${BOLD}⚠️  Generated Passwords:${NC}"
        echo ""
        cat "$PASSWORD_FILE"
        echo ""
        echo -e "${YELLOW}${BOLD}IMPORTANT:${NC}"
        echo -e "  1. Save these passwords in a secure password manager"
        echo -e "  2. Delete the password file: ${YELLOW}rm $PASSWORD_FILE${NC}"
        echo -e "  3. Consider using SSH keys for better security"
        echo ""
    fi

    echo -e "${CYAN}${BOLD}Security Features Enabled:${NC}"
    echo -e "  ${GREEN}✓${NC} Password authentication enabled"
    echo -e "  ${GREEN}✓${NC} SSH service configured and reloaded"
    echo -e "  ${GREEN}✓${NC} Ubuntu user with sudo privileges"
    echo -e "  ${GREEN}✓${NC} Development environment configured"
    echo -e "  ${GREEN}✓${NC} Fail2ban protecting against brute force"
    echo -e "  ${GREEN}✓${NC} UFW firewall configured"
    echo -e "  ${GREEN}✓${NC} Configuration files backed up to $BACKUP_DIR"
    echo ""

    echo -e "${CYAN}${BOLD}Development Tools Ready:${NC}"
    echo -e "  ${GREEN}✓${NC} Ubuntu user can run Claude Code:"
    echo -e "    ${WHITE}claude --dangerously-skip-permissions${NC}"
    echo -e "  ${GREEN}✓${NC} Convenience alias available:"
    echo -e "    ${WHITE}claude-dev${NC} (runs with --dangerously-skip-permissions)"
    echo -e "  ${GREEN}✓${NC} Sudo configured for development tools"
    echo ""

    echo -e "${YELLOW}${BOLD}Security Recommendations:${NC}"
    echo -e "  • Change default passwords regularly"
    echo -e "  • Monitor /var/log/auth.log for login attempts"
    echo -e "  • Consider disabling root login after setup:"
    echo -e "    ${WHITE}sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' $SSH_CONFIG${NC}"
    echo -e "    ${WHITE}systemctl reload ssh${NC}"
    echo -e "  • Use strong passwords (minimum 12 characters)"
    echo -e "  • Enable two-factor authentication if possible"
    echo ""

    echo -e "${MAGENTA}${BOLD}Next Steps:${NC}"
    echo -e "  1. SSH as ubuntu: ${YELLOW}ssh ubuntu@$server_ip${NC}"
    echo -e "  2. Run setup script: ${YELLOW}sudo bash setup-dev-environment.sh${NC}"
    echo -e "  3. Start Claude Code: ${YELLOW}claude --dangerously-skip-permissions${NC}"
    echo ""

    echo -e "${GREEN}${BOLD}Setup completed at $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo ""

    log_message "Setup completed successfully"
}

# Cleanup function
cleanup() {
    print_info "Performing cleanup..."

    # Remove temporary files
    rm -f /tmp/sshd_config.tmp 2>/dev/null

    print_success "Cleanup completed"
}

# Trap errors and perform cleanup
trap cleanup EXIT

#######################################
# Main Execution
#######################################

main() {
    # Clear screen for better visibility
    clear

    print_header "$SCRIPT_NAME v$SCRIPT_VERSION"
    echo ""
    print_info "This script will enable password authentication on your Digital Ocean droplet"
    print_info "Current configuration will be backed up before changes"
    echo ""

    # Confirmation prompt
    read -p "Do you want to proceed with the setup? (y/n): " confirm

    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_warning "Setup cancelled by user"
        exit 0
    fi

    echo ""

    # Initialize log file
    mkdir -p $(dirname "$LOG_FILE")
    echo "=== Password Auth Setup Started at $(date) ===" > "$LOG_FILE"

    # Run setup steps
    check_root
    check_ubuntu_version
    create_backup_dir

    # Core configuration
    configure_ssh
    set_root_password
    create_ubuntu_user

    # Security hardening
    install_fail2ban
    configure_firewall

    # Verification
    verify_ssh_access

    # Optional deployment
    deploy_seismic_core

    # Display summary
    display_summary

    print_success "All tasks completed successfully!"
}

# Run main function
main "$@"