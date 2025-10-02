# Digital Ocean Password Authentication Setup

## Overview
The `setup_password_auth.sh` script enables password-based SSH authentication on Digital Ocean droplets running Ubuntu. This is useful when SSH key authentication is not desired or when you need a quick password-based access method.

## Features

### 🔐 SSH Configuration
- Backs up existing `/etc/ssh/sshd_config` before modifications
- Enables `PasswordAuthentication yes`
- Keeps `PubkeyAuthentication yes` as fallback
- Tests configuration with `sshd -t` before applying
- Safely reloads SSH service after changes

### 👤 User Management
- Sets root password (custom or generated)
- Creates 'ubuntu' user with sudo privileges
- Offers password options: custom, generated, or same as root
- Optional passwordless sudo configuration

### 🛡️ Security Hardening
- **Fail2ban**: Automatic brute-force protection
  - 3 max retry attempts
  - 1-hour ban time
  - Monitors `/var/log/auth.log`
- **UFW Firewall**: Network protection
  - Allows SSH (port 22)
  - Optional HTTP/HTTPS support
  - Default deny incoming policy

### ✅ Validation & Safety
- Uses `set -e` for error handling
- Creates backups in `/root/backups/`
- Tests SSH config before applying
- Verifies all services after setup
- Provides rollback capability via backups

## Usage

### Quick Start
```bash
# Download and run on your Digital Ocean droplet
wget https://raw.githubusercontent.com/SEISMIC-GROUP/remote-dev-scripts/main/setup_password_auth.sh
chmod +x setup_password_auth.sh
sudo ./setup_password_auth.sh
```

### Alternative: Direct execution
```bash
# Run directly without downloading
curl -fsSL https://raw.githubusercontent.com/SEISMIC-GROUP/remote-dev-scripts/main/setup_password_auth.sh | sudo bash
```

## Script Flow

1. **Pre-flight Checks**
   - Verifies root privileges
   - Detects Ubuntu version (20.04/22.04/24.04 supported)
   - Creates backup directory

2. **SSH Configuration**
   - Backs up `/etc/ssh/sshd_config`
   - Modifies authentication settings
   - Tests configuration with `sshd -t`
   - Reloads SSH service only if test passes

3. **Password Setup**
   - Root password: custom or 16-character generated
   - Ubuntu user: creation or password reset
   - Saves generated passwords to `/root/.setup_passwords.txt` (mode 600)

4. **Security Hardening**
   - Installs and configures fail2ban
   - Sets up UFW firewall rules
   - Enables all security services

5. **Verification**
   - Confirms SSH service is running
   - Validates password authentication enabled
   - Checks fail2ban and UFW status

## Safety Features

### Permission Handling
- Script requires root (`EUID -ne 0` check)
- Files created with appropriate permissions:
  - Password file: `chmod 600`
  - Sudoers file: `chmod 440`

### Error Prevention
- `set -e`: Exit on any error
- `set -u`: Exit on undefined variables
- `set -o pipefail`: Catch pipe failures
- Configuration testing before applying changes

### Backup & Recovery
All critical files are backed up before modification:
```bash
/root/backups/
├── sshd_config.20251002_143022.bak
└── [other timestamped backups]
```

To restore:
```bash
cp /root/backups/sshd_config.[timestamp].bak /etc/ssh/sshd_config
systemctl reload ssh
```

## Security Considerations

### ⚠️ Important Notes
1. **Password Authentication Risks**: Less secure than SSH keys
2. **Generated Passwords**: Save securely and delete `/root/.setup_passwords.txt`
3. **Root Access**: Consider disabling after initial setup
4. **Monitoring**: Check `/var/log/auth.log` regularly

### Post-Setup Hardening
```bash
# Disable root login (after creating ubuntu user)
sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl reload ssh

# View fail2ban status
fail2ban-client status sshd

# Check firewall rules
ufw status verbose

# Monitor authentication logs
tail -f /var/log/auth.log
```

## Requirements

- **OS**: Ubuntu 20.04, 22.04, 24.04 (tested on 25.04)
- **Access**: Root privileges required
- **Network**: Internet connection for package installation
- **Disk**: ~50MB for fail2ban and UFW

## Output Example

```
===============================================
Digital Ocean Password Auth Setup v1.0.0
===============================================

✓ Ubuntu 24.04 detected - Compatible
✓ Created backup directory: /root/backups
✓ Backed up /etc/ssh/sshd_config
✓ SSH configuration updated successfully
✓ SSH service reloaded
✓ Root password generated and set

Generated Root Password: Xk9mP2nL4qR7wT6v

✓ Created user 'ubuntu' with home directory
✓ Ubuntu user password generated and set

Generated Ubuntu Password: Bj3nK8pM5sQ2xY9w

✓ Fail2ban installed and started
✓ UFW firewall configured and enabled
✓ Password authentication is enabled

SSH Connection Commands:
  ssh root@167.172.166.13
  ssh ubuntu@167.172.166.13
```

## Troubleshooting

### SSH Connection Issues
```bash
# Check SSH service
systemctl status ssh

# View SSH config
grep -E '^(Password|Pubkey|PermitRoot)' /etc/ssh/sshd_config

# Test configuration
sshd -t
```

### Firewall Blocking Connection
```bash
# Check UFW status
ufw status numbered

# Allow SSH if blocked
ufw allow OpenSSH
```

### Fail2ban False Positives
```bash
# Unban an IP
fail2ban-client set sshd unbanip YOUR_IP

# Check jail status
fail2ban-client status sshd
```

## License
MIT License - Use at your own risk

## Support
For issues or questions, open an issue at:
https://github.com/SEISMIC-GROUP/remote-dev-scripts/issues