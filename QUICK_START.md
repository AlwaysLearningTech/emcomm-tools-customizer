# Quick Start Guide

## First Build (New Installation)

```bash
# Install dependencies
sudo apt install -y xorriso squashfs-tools wget curl jq

# Clone and configure
git clone https://github.com/AlwaysLearningTech/emcomm-tools-customizer.git
cd emcomm-tools-customizer
cp secrets.env.template secrets.env
nano secrets.env  # Fill in your values

# List available releases (optional)
./build-etc-iso.sh -l

# Build from stable release
sudo ./build-etc-iso.sh -r stable
```

## Upgrade Build (From Running ETC)

```bash
# On your running ETC system
cd /opt/emcomm-customizer

# Build new ISO from latest development tag
sudo ./build-etc-iso.sh -r latest

# Copy to Ventoy and boot
# Settings restore automatically!
```

## Essential Configuration

```bash
# secrets.env minimum
CALLSIGN="N0CALL"
WIFI_SSID_HOME="network"
WIFI_PASSWORD_HOME="password"
```

## Release Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| `-r stable` | Latest GitHub Release | Production use (recommended) |
| `-r latest` | Most recent git tag | Development/testing |
| `-r tag -t <name>` | Specific tag by name | Reproducible builds |

Use `-l` to list available releases and tags.

## Common Commands

```bash
# List available releases/tags
./build-etc-iso.sh -l

# Standard stable build
sudo ./build-etc-iso.sh -r stable

# Latest development build
sudo ./build-etc-iso.sh -r latest

# Specific tag
sudo ./build-etc-iso.sh -r tag -t emcomm-tools-os-community-20251113-r5-build17

# Preview (dry-run)
./build-etc-iso.sh -d

# Verbose mode
sudo ./build-etc-iso.sh -r stable -v
```

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Permission denied | Use `sudo` |
| et-user-backup fails | Not on ETC system |
| Settings not restored | Check `journalctl -u emcomm-restore` |

---
See [README.md](README.md) for full documentation.
