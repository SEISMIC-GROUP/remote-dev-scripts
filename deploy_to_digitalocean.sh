#!/bin/bash

#######################################
# Digital Ocean Remote Deployment Script
# Run this from your local machine to deploy to a fresh Ubuntu droplet
# Usage: ./deploy_to_digitalocean.sh <server-ip> [root-password]
#######################################

set -e
set -u
set -o pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Script info
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPT_NAME="Digital Ocean Remote Deployer"
VERSION="1.0.0"

#######################################
# Functions
#######################################

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

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"

    # Check for SSH
    if ! command -v ssh &> /dev/null; then
        print_error "SSH client not found. Please install SSH."
        exit 1
    fi
    print_success "SSH client found"

    # Check for SCP
    if ! command -v scp &> /dev/null; then
        print_error "SCP not found. Please install SCP."
        exit 1
    fi
    print_success "SCP found"

    # Check for required files
    if [[ ! -f "$SCRIPT_DIR/setup_password_auth.sh" ]]; then
        print_error "setup_password_auth.sh not found in current directory"
        exit 1
    fi
    print_success "Setup script found"

    if [[ ! -f "$SCRIPT_DIR/seismic_secrets.env.template" ]]; then
        print_warning "seismic_secrets.env.template not found - seismic-core deployment will be skipped"
    else
        print_success "Secrets template found"
    fi
}

# Validate server IP
validate_ip() {
    local ip=$1
    if [[ ! $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        print_error "Invalid IP address format: $ip"
        return 1
    fi
    return 0
}

# Test SSH connection
test_connection() {
    local server_ip=$1
    local ssh_user=${2:-root}

    print_step "Testing SSH connection to $ssh_user@$server_ip..."

    if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o BatchMode=yes \
        $ssh_user@$server_ip "echo 'Connection successful'" &>/dev/null; then
        print_success "SSH key authentication successful"
        return 0
    else
        print_warning "SSH key authentication failed, will prompt for password"
        return 1
    fi
}

# Create secrets file locally
create_secrets_file() {
    local temp_secrets="/tmp/.seismic_secrets_$$.env"

    print_header "Configure Secrets (Optional)"
    echo ""
    read -p "Do you want to configure seismic-core secrets now? (y/n): " configure_secrets

    if [[ "$configure_secrets" != "y" && "$configure_secrets" != "Y" ]]; then
        print_info "Skipping secrets configuration"
        return 1
    fi

    cp "$SCRIPT_DIR/seismic_secrets.env.template" "$temp_secrets"

    echo ""
    print_info "Enter your actual credentials (or press Enter to skip each field):"
    echo ""

    # Database configuration
    read -p "Database URL (postgres://...): " db_url
    if [[ -n "$db_url" ]]; then
        sed -i.bak "s|DATABASE_URL=.*|DATABASE_URL=\"$db_url\"|" "$temp_secrets"
        sed -i.bak "s|DIRECT_DATABASE_URL=.*|DIRECT_DATABASE_URL=\"$db_url\"|" "$temp_secrets"

        # Extract components from URL
        if [[ "$db_url" =~ postgres://([^:]+):([^@]+)@([^:]+):([^/]+)/([^?]+) ]]; then
            local user="${BASH_REMATCH[1]}"
            local pass="${BASH_REMATCH[2]}"
            local host="${BASH_REMATCH[3]}"
            local port="${BASH_REMATCH[4]}"
            local db="${BASH_REMATCH[5]}"

            sed -i.bak "s|PGHOST=.*|PGHOST=\"$host\"|" "$temp_secrets"
            sed -i.bak "s|PGPORT=.*|PGPORT=\"$port\"|" "$temp_secrets"
            sed -i.bak "s|PGDATABASE=.*|PGDATABASE=\"$db\"|" "$temp_secrets"
            sed -i.bak "s|PGUSER=.*|PGUSER=\"$user\"|" "$temp_secrets"
            sed -i.bak "s|PGPASSWORD=.*|PGPASSWORD=\"$pass\"|" "$temp_secrets"
        fi
    fi

    # Auth secrets
    read -p "Better Auth Secret (32 chars, or press Enter to generate): " auth_secret
    if [[ -z "$auth_secret" ]]; then
        auth_secret=$(openssl rand -hex 16 2>/dev/null || cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
        print_info "Generated: $auth_secret"
    fi
    sed -i.bak "s|BETTER_AUTH_SECRET=.*|BETTER_AUTH_SECRET=\"$auth_secret\"|" "$temp_secrets"
    sed -i.bak "s|NEXTAUTH_SECRET=.*|NEXTAUTH_SECRET=\"$auth_secret\"|" "$temp_secrets"
    sed -i.bak "s|AUTH_SECRET=.*|AUTH_SECRET=\"$auth_secret\"|" "$temp_secrets"

    # API Keys
    read -p "OpenAI API Key (sk-proj-...): " openai_key
    if [[ -n "$openai_key" ]]; then
        sed -i.bak "s|OPENAI_API_KEY=.*|OPENAI_API_KEY=\"$openai_key\"|" "$temp_secrets"
    fi

    read -p "Perplexity API Key (pplx-...): " perplexity_key
    if [[ -n "$perplexity_key" ]]; then
        sed -i.bak "s|PERPLEXITY_API_KEY=.*|PERPLEXITY_API_KEY=\"$perplexity_key\"|" "$temp_secrets"
    fi

    read -p "Bright Data API Token: " brightdata_token
    if [[ -n "$brightdata_token" ]]; then
        sed -i.bak "s|BRIGHTDATA_API_TOKEN=.*|BRIGHTDATA_API_TOKEN=\"$brightdata_token\"|" "$temp_secrets"
    fi

    # Clean up backup files
    rm -f "$temp_secrets.bak"

    echo "$temp_secrets"
    return 0
}

# Deploy to server
deploy_to_server() {
    local server_ip=$1
    local ssh_pass_auth=$2
    local secrets_file=${3:-}

    print_header "Deploying to $server_ip"

    # Prepare SSH options
    local ssh_opts="-o StrictHostKeyChecking=no"
    if [[ "$ssh_pass_auth" == "true" ]]; then
        print_info "Password authentication will be required for each operation"
    fi

    # Copy setup script
    print_step "Copying setup script to server..."
    scp $ssh_opts "$SCRIPT_DIR/setup_password_auth.sh" root@$server_ip:/root/
    print_success "Setup script copied"

    # Copy documentation files
    if [[ -f "$SCRIPT_DIR/SETUP_PASSWORD_AUTH_README.md" ]]; then
        scp $ssh_opts "$SCRIPT_DIR/SETUP_PASSWORD_AUTH_README.md" root@$server_ip:/root/
        print_success "Documentation copied"
    fi

    # Copy secrets file if created
    if [[ -n "$secrets_file" && -f "$secrets_file" ]]; then
        print_step "Copying secrets configuration..."
        scp $ssh_opts "$secrets_file" root@$server_ip:/root/.seismic_secrets.env
        ssh $ssh_opts root@$server_ip "chmod 600 /root/.seismic_secrets.env"
        rm -f "$secrets_file"  # Remove local temp file
        print_success "Secrets configured on server"
    fi

    # Make script executable
    print_step "Setting permissions..."
    ssh $ssh_opts root@$server_ip "chmod +x /root/setup_password_auth.sh"
    print_success "Permissions set"

    # Run the setup script
    print_header "Running Setup Script on Server"
    echo ""
    print_warning "The script will now run interactively on the server."
    print_warning "You'll be prompted for various configuration options."
    echo ""
    read -p "Press Enter to continue..."
    echo ""

    # Run the script interactively
    ssh $ssh_opts -t root@$server_ip "/root/setup_password_auth.sh"

    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        print_success "Setup completed successfully!"
    else
        print_error "Setup failed with exit code: $exit_code"
        return $exit_code
    fi

    return 0
}

# Display connection info
display_connection_info() {
    local server_ip=$1

    print_header "Connection Information"
    echo ""
    echo -e "${CYAN}${BOLD}Your server is now configured!${NC}"
    echo ""
    echo -e "${YELLOW}${BOLD}SSH Access:${NC}"
    echo -e "  Root:   ${WHITE}ssh root@$server_ip${NC}"
    echo -e "  Ubuntu: ${WHITE}ssh ubuntu@$server_ip${NC}"
    echo ""
    echo -e "${YELLOW}${BOLD}Development Tools:${NC}"
    echo -e "  1. SSH as ubuntu user"
    echo -e "  2. Run: ${WHITE}claude --dangerously-skip-permissions${NC}"
    echo -e "  3. Or use alias: ${WHITE}claude-dev${NC}"
    echo ""

    if [[ -f "$SCRIPT_DIR/seismic_secrets.env.template" ]]; then
        echo -e "${YELLOW}${BOLD}Seismic Core (if deployed):${NC}"
        echo -e "  Portal:    ${WHITE}http://$server_ip:3888${NC}"
        echo -e "  Docs:      ${WHITE}http://$server_ip:3894${NC}"
        echo -e "  Storybook: ${WHITE}http://$server_ip:6006${NC}"
        echo ""
        echo -e "${CYAN}Start Application:${NC}"
        echo -e "  ${WHITE}ssh ubuntu@$server_ip${NC}"
        echo -e "  ${WHITE}cd /var/www/seismic-core${NC}"
        echo -e "  ${WHITE}npm run dev:portal${NC}"
        echo ""
    fi

    echo -e "${GREEN}${BOLD}Deployment completed at $(date '+%Y-%m-%d %H:%M:%S')${NC}"
}

# Clean up function
cleanup() {
    # Remove any temporary files
    rm -f /tmp/.seismic_secrets_*.env 2>/dev/null || true
}

# Set up trap for cleanup
trap cleanup EXIT

#######################################
# Main Execution
#######################################

main() {
    clear

    print_header "$SCRIPT_NAME v$VERSION"
    echo ""

    # Check arguments
    if [[ $# -lt 1 ]]; then
        echo -e "${YELLOW}Usage:${NC} $0 <server-ip> [root-password]"
        echo ""
        echo "Examples:"
        echo "  $0 167.172.166.13                    # SSH key auth"
        echo "  $0 167.172.166.13 mypassword         # Password auth"
        echo ""
        exit 1
    fi

    local SERVER_IP=$1
    local ROOT_PASSWORD=${2:-}

    # Validate IP
    if ! validate_ip "$SERVER_IP"; then
        exit 1
    fi

    print_info "Target server: $SERVER_IP"
    echo ""

    # Check prerequisites
    check_prerequisites
    echo ""

    # Test connection
    local ssh_pass_auth="false"
    if ! test_connection "$SERVER_IP"; then
        if [[ -z "$ROOT_PASSWORD" ]]; then
            print_info "SSH key authentication not available"
            read -s -p "Enter root password for $SERVER_IP: " ROOT_PASSWORD
            echo ""
        fi
        ssh_pass_auth="true"

        # Set up SSH pass for automated deployment
        if command -v sshpass &> /dev/null; then
            export SSHPASS="$ROOT_PASSWORD"
            print_info "Using sshpass for automated deployment"
        else
            print_warning "sshpass not installed - you'll need to enter password multiple times"
            print_info "Install sshpass for automated deployment: brew install hudochenkov/sshpass/sshpass"
        fi
    fi
    echo ""

    # Create secrets file (optional)
    local secrets_file=""
    secrets_file=$(create_secrets_file)
    if [[ $? -eq 0 && -n "$secrets_file" ]]; then
        print_success "Secrets file created"
    fi
    echo ""

    # Deploy to server
    if deploy_to_server "$SERVER_IP" "$ssh_pass_auth" "$secrets_file"; then
        echo ""
        display_connection_info "$SERVER_IP"
    else
        print_error "Deployment failed"
        exit 1
    fi
}

# Run main function
main "$@"