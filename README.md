# Remote Dev Scripts

Production-ready automation scripts for setting up complete development environments on Ubuntu DigitalOcean droplets.

## 🎯 Quick Start

```bash
# Copy to your Ubuntu server
scp setup-dev-environment.sh root@your-server-ip:/root/

# SSH and run
ssh root@your-server-ip
sudo bash /root/setup-dev-environment.sh
```

## 📦 What Gets Installed

- **Node.js** v22 LTS, NPM, PNPM
- **AI Tools:** Claude Code, OpenAI Codex, OpenCode
- **Browser Automation:** Playwright (Chromium, Firefox, WebKit)
- **MCP Servers:** 6 total (Playwright, Context7, Sequential Thinking, Bright Data, Task Master, Perplexity)
- **Developer Tools:** GitHub CLI

## 📄 Documentation

See [`claude.md`](./claude.md) for complete documentation, usage guide, and troubleshooting.

## ✅ Validated

Tested and validated on Ubuntu 25.04 (DigitalOcean) - October 2025

**Installation Time:** ~6-8 minutes
**Disk Space:** ~3.7 GB
**Success Rate:** 100%

## 📋 Files

- `setup-dev-environment.sh` - Main installation script
- `validate-installation.sh` - Validation script with 7 gates
- `claude.md` - Complete documentation
- `MCP_Configuration_Report.md` - MCP server guide
- `FINAL_INSTALLATION_SUMMARY.md` - Detailed validation report

## 🔑 Requirements

- Ubuntu 22.04/24.04/25.04 LTS
- Root access
- Internet connection

---

**Created with Claude Code (Sonnet 4.5)**
**License:** MIT
