# EmComm Tools Customizer

Fully automated customization of EmComm Tools Community (ETC) ISO images using xorriso/squashfs. No GUI required.

## Overview

**Upstream Project**: [EmComm Tools Community](https://github.com/thetechprepper/emcomm-tools-os-community)  
**Documentation**: [community.emcommtools.com](https://community.emcommtools.com/)

### What Gets Customized

ETC already includes all ham radio tools (Winlink, VARA, JS8Call, fldigi, etc.). This customizer adds:

- ✅ Pre-configured WiFi networks (auto-connect on boot)
- ✅ Personal callsign and grid square
- ✅ Hostname set to `ETC-{CALLSIGN}`
- ✅ Desktop preferences (dark mode, scaling)
- ✅ VARA FM/HF license key injection (if you have a license)
- ✅ Disabled accessibility features (screen reader, on-screen keyboard)
- ✅ APRS configuration (direwolf, YAAC)
- ✅ Git configuration
- ✅ Autologin for emergency deployment

### What's NOT Changed

- Python installation (ETC handles this)
- Ham radio software (already in ETC)
- Wine/VARA installation (already in ETC)
- System packages (already optimized)

### Future Enhancements (TODO)

- ⏳ **D578 CAT Control**: Hamlib/rigctld configuration for Anytone D578UV radio
- ⏳ **GPS Auto-Detection**: Automatic grid square from GPS hardware
- ⏳ **Radio Auto-Detection**: USB VID/PID detection for CAT control setup

## Directory Structure

```text
emcomm-tools-customizer/
├── build-etc-iso.sh          # Main build script (fully automated)
├── secrets.env.template      # Configuration template
├── secrets.env               # Your configuration (gitignored)
├── cache/                    # Downloaded files (persistent)
│   └── ubuntu-22.10-desktop-amd64.iso   # ← Drop your ISO here!
├── output/                   # Generated custom ISOs
├── logs/                     # Build logs
└── post-install/             # Scripts for after ISO installation
```

## Prerequisites

Ubuntu 22.10 reached end-of-life, so you must first update apt sources:

```bash
# Fix apt sources for EOL Ubuntu 22.10
sudo sed -i 's/archive.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list
sudo sed -i 's/security.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list
sudo apt update

# Install build dependencies
sudo apt install -y xorriso squashfs-tools wget curl jq
```

## Quick Start

### First Build

```bash
# Clone repository
git clone https://github.com/AlwaysLearningTech/emcomm-tools-customizer.git
cd emcomm-tools-customizer

# Create configuration
cp secrets.env.template secrets.env
nano secrets.env  # Fill in your values

# Build from stable release (downloads ETC + Ubuntu ISO automatically)
sudo ./build-etc-iso.sh -r stable

# Output: output/<release-tag>-custom.iso
```

### Skip ISO Download

To avoid downloading the 3.6GB Ubuntu ISO each time:

```bash
# Create cache directory and copy your ISO there
mkdir -p cache
cp ~/Downloads/ubuntu-22.10-desktop-amd64.iso cache/

# Now build - ISO download will be skipped!
sudo ./build-etc-iso.sh -r stable
```

The script checks `cache/ubuntu-22.10-desktop-amd64.iso` before downloading.

See [QUICK_START.md](QUICK_START.md) for a condensed reference.

## Build Options

```bash
# List available releases and tags from GitHub
./build-etc-iso.sh -l

# Build from stable release (recommended for most users)
sudo ./build-etc-iso.sh -r stable

# Build from latest development tag (bleeding edge)
sudo ./build-etc-iso.sh -r latest

# Build a specific tag by name
sudo ./build-etc-iso.sh -r tag -t emcomm-tools-os-community-20251113-r5-build17

# Dry run (show what would happen without making changes)
./build-etc-iso.sh -d

# Verbose mode for debugging
sudo ./build-etc-iso.sh -r stable -v
```

### Option Reference

| Option | Description |
|--------|-------------|
| `-r <stable\|latest\|tag>` | Release mode |
| `-t <tag>` | Specific tag name (required with `-r tag`) |
| `-l` | List available releases and tags |
| `-d` | Dry-run mode |
| `-v` | Verbose mode |
| `-h` | Show help |

### Release Modes

| Mode | Description | Source |
|------|-------------|--------|
| `stable` | Latest GitHub Release (production-ready) | [Releases](https://github.com/thetechprepper/emcomm-tools-os-community/releases) |
| `latest` | Most recent git tag (development) | [Tags](https://github.com/thetechprepper/emcomm-tools-os-community/tags) |
| `tag` | Specific tag by name | Use with `-t` |

## Configuration Reference

### secrets.env Variables

```bash
# === User Identity (REQUIRED) ===
CALLSIGN="N0CALL"              # Your amateur radio callsign
USER_FULLNAME="Your Name"       # Full name for git commits
USER_EMAIL="you@example.com"    # Email for git commits
USER_USERNAME="emcomm"          # Linux username

# === System ===
MACHINE_NAME=""                 # Hostname (defaults to ETC-{CALLSIGN})

# === WiFi Networks ===
# Add as many networks as needed with unique suffixes
WIFI_SSID_HOME="YourHomeNetwork"
WIFI_PASSWORD_HOME="YourHomePassword"
WIFI_AUTOCONNECT_HOME="yes"

WIFI_SSID_MOBILE="YourHotspot"
WIFI_PASSWORD_MOBILE="HotspotPassword"
WIFI_AUTOCONNECT_MOBILE="yes"

# === VARA License (Optional) ===
VARA_FM_CALLSIGN=""            # Callsign registered with VARA FM license
VARA_FM_LICENSE_KEY=""         # Your VARA FM license key
VARA_HF_CALLSIGN=""            # Callsign registered with VARA HF license  
VARA_HF_LICENSE_KEY=""         # Your VARA HF license key

# === APRS Configuration ===
APRS_SSID="10"                 # SSID for APRS
APRS_PASSCODE=""               # APRS-IS passcode (generate at aprs.fi)
APRS_SYMBOL="r/"               # Primary table symbol
APRS_COMMENT="EmComm Station"  # Status text
APRS_SERVER="noam.aprs2.net"   # APRS-IS server
ENABLE_APRS_IGATE="yes"        # Enable iGate functionality
ENABLE_APRS_BEACON="no"        # Enable beacon (needs GPS)

# === Direwolf Audio ===
DIREWOLF_ADEVICE="plughw:1,0"  # Audio device
DIREWOLF_PTT="CM108"           # PTT method
```

### About VARA Licenses

VARA is commercial software with **two separate products**:

| Product | Cost | Use Case |
|---------|------|----------|
| **VARA FM** | ~$69 | VHF/UHF Winlink via FM repeaters |
| **VARA HF** | ~$69 | HF Winlink for long-distance |

Purchase at [rosmodem.wordpress.com](https://rosmodem.wordpress.com/)

### APRS Symbol Reference

Common symbols for APRS_SYMBOL:

| Symbol | Code | Description |
|--------|------|-------------|
| Car | `>/` | Mobile station |
| House | `-/` | Home/QTH |
| Portable | `r/` | Portable station |
| Emergency | `!/` | Emergency |
| Digipeater | `#/` | Digipeater |

Full table: [APRS Symbol Codes](http://www.aprs.org/symbols/symbolsX.txt)

## Caching

The `cache/` directory stores downloaded files to speed up rebuilds:

```text
cache/
├── ubuntu-22.10-desktop-amd64.iso    # Ubuntu base ISO (3.6 GB)
└── emcomm-tools-os-*.tar.gz          # ETC installer tarballs
```

**To skip downloads:**

1. Create `cache/` directory
2. Copy `ubuntu-22.10-desktop-amd64.iso` into it
3. Run build - download will be skipped

ETC tarballs are also cached automatically after first download.

## Output

Generated ISOs are placed in `output/`:

```text
output/
└── emcomm-tools-os-community-20251128-r5-final-5.0.0-custom.iso
```

Copy to Ventoy USB:

```bash
cp output/*.iso /media/$USER/Ventoy/
sync
```

## Troubleshooting

### "Permission denied" errors

Run with `sudo`:

```bash
sudo ./build-etc-iso.sh -r stable
```

### "Command not found" errors

Install prerequisites (after fixing apt sources for Ubuntu 22.10):

```bash
sudo apt install -y xorriso squashfs-tools wget curl jq
```

### Download takes too long

Pre-download and cache:

```bash
mkdir -p cache
wget -O cache/ubuntu-22.10-desktop-amd64.iso \
  https://old-releases.ubuntu.com/releases/kinetic/ubuntu-22.10-desktop-amd64.iso
```

### Build fails during squashfs

- Ensure you have 15+ GB free disk space
- The squashfs step takes 10-20 minutes on typical hardware

## How It Works

1. **Download**: Fetches Ubuntu 22.10 ISO and ETC installer tarball (cached in `cache/`)
2. **Extract**: Uses xorriso to extract ISO, unsquashfs for filesystem
3. **Customize**: Modifies `/etc/skel/` and system configs in the extracted filesystem
4. **Rebuild**: Creates new squashfs and ISO with xorriso

All customizations go into `/etc/skel/` so they apply to new users automatically.

## License

MIT License - See LICENSE file

## Credits

- **EmComm Tools Community**: [thetechprepper](https://github.com/thetechprepper/emcomm-tools-os-community)
- **Customizer**: KD7DGF

---

**73 de KD7DGF** 📻
