# Quick Start Guide

## First Build (New Installation)

```bash
# Install dependencies (on Ubuntu/Debian)
sudo apt install -y xorriso squashfs-tools genisoimage p7zip-full wget curl jq

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

## Skip ISO Download

```bash
# Drop your Ubuntu ISO in cache/ to skip 3.6GB download
mkdir -p cache
cp ~/Downloads/ubuntu-22.10-desktop-amd64.iso cache/
```

## Essential Configuration

Minimum `secrets.env`:

```bash
CALLSIGN="N0CALL"
USER_USERNAME="emcomm"
WIFI_SSID_HOME="network"
WIFI_PASSWORD_HOME="password"
```

## Release Modes

| Mode | Command | Description |
|------|---------|-------------|
| Stable | `-r stable` | Latest GitHub Release (recommended) |
| Latest | `-r latest` | Most recent git tag |
| Specific | `-r tag -t <name>` | Exact tag by name |

## Output Location

ISOs are created in `output/`:

```bash
# Copy to Ventoy USB
cp output/*.iso /media/$USER/Ventoy/
sync
```

## Dry Run

Preview what would happen without making changes:

```bash
./build-etc-iso.sh -d
```
