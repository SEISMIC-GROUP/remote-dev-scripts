# Seismic Core Secrets Configuration Guide

## Overview
The `setup_password_auth.sh` script now uses environment variables for all sensitive data to prevent secrets from being committed to version control. Before running the script with seismic-core deployment, you must create a secrets file on your server.

## Quick Setup

### 1. Copy the Template to Your Server
```bash
# From your local machine
scp seismic_secrets.env.template root@YOUR_SERVER_IP:/root/.seismic_secrets.env
```

### 2. SSH to Your Server
```bash
ssh root@YOUR_SERVER_IP
```

### 3. Edit the Secrets File
```bash
nano /root/.seismic_secrets.env
```

### 4. Replace All Placeholders
Update these values with your actual credentials:

#### Database Configuration
```bash
DATABASE_URL="postgres://doadmin:ACTUAL_PASSWORD@your-db-host.com:25060/your-database?sslmode=require"
PGHOST="your-db-host.com"
PGDATABASE="your-database"
PGPASSWORD="ACTUAL_PASSWORD"
```

#### Authentication Secrets
Generate random 32-character secrets:
```bash
# Generate random secrets
openssl rand -hex 16  # For BETTER_AUTH_SECRET
openssl rand -hex 16  # For NEXTAUTH_SECRET
```

#### API Keys
- **OpenAI API Key**: Get from https://platform.openai.com/api-keys
- **Perplexity API Key**: Get from https://www.perplexity.ai/settings/api
- **Bright Data Token**: Get from https://brightdata.com/cp/api_tokens

### 5. Secure the File
```bash
chmod 600 /root/.seismic_secrets.env
```

### 6. Run the Setup Script
```bash
./setup_password_auth.sh
```

## Security Best Practices

### DO's
✅ Keep the secrets file on the server only
✅ Use `chmod 600` to restrict access
✅ Use strong, unique passwords
✅ Rotate secrets regularly
✅ Back up the file securely (encrypted)

### DON'Ts
❌ Never commit `.seismic_secrets.env` to git
❌ Never share the file publicly
❌ Never use default/example passwords
❌ Never store the file unencrypted in backups

## File Locations

| File | Location | Purpose |
|------|----------|---------|
| Secrets File | `/root/.seismic_secrets.env` | Actual credentials (server only) |
| Template | `seismic_secrets.env.template` | Example template (safe to commit) |
| Script | `setup_password_auth.sh` | Main setup script |
| Application | `/var/www/seismic-core/` | Deployed application |

## Troubleshooting

### Secrets File Not Found
```bash
# Error: Secrets file not found at /root/.seismic_secrets.env

# Solution: Create the file from template
cp seismic_secrets.env.template /root/.seismic_secrets.env
nano /root/.seismic_secrets.env
chmod 600 /root/.seismic_secrets.env
```

### Database Connection Failed
```bash
# Verify your database credentials
psql "postgres://doadmin:PASSWORD@HOST:PORT/DATABASE?sslmode=require"
```

### API Keys Invalid
- Verify keys are active in their respective dashboards
- Check for typos or missing characters
- Ensure no extra spaces or quotes

## Example Complete Secrets File

```bash
#!/bin/bash
# Database
DATABASE_URL="postgres://doadmin:YOUR_ACTUAL_PASSWORD_HERE@db-cluster-do-user-12345.db.ondigitalocean.com:25060/myapp?sslmode=require"
DIRECT_DATABASE_URL="postgres://doadmin:YOUR_ACTUAL_PASSWORD_HERE@db-cluster-do-user-12345.db.ondigitalocean.com:25060/myapp?sslmode=require"

PGHOST="db-cluster-do-user-12345.db.ondigitalocean.com"
PGPORT="25060"
PGDATABASE="myapp"
PGUSER="doadmin"
PGPASSWORD="YOUR_ACTUAL_PASSWORD_HERE"
PGSSLMODE="require"

# Auth
BETTER_AUTH_SECRET="a1b2c3d4e5f6789012345678901234567"
NEXTAUTH_SECRET="9876543210fedcba9876543210fedcba"
AUTH_SECRET="9876543210fedcba9876543210fedcba"

# APIs
OPENAI_API_KEY="sk-proj-actualKeyHere1234567890"
PERPLEXITY_API_KEY="pplx-actualKeyHere9876543210"
BRIGHTDATA_API_TOKEN="12345678-90ab-cdef-1234-567890abcdef"
```

## Support
For issues with the script, open an issue at:
https://github.com/SEISMIC-GROUP/remote-dev-scripts/issues