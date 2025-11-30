# EmComm Tools Customizer

Automated customization for EmComm Tools Community (ETC) ISO - a turnkey Ubuntu-based operating system for amateur radio emergency communications.

## Overview

This project provides **automated** customization of ETC ISO images using direct ISO modification for fully scripted, reproducible builds.

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
- ✅ Disabled automatic brightness
- ✅ APRS configuration with proper symbols
- ✅ Automatic et-user backup/restore between upgrades
- ✅ Persistent cache (base ISO, Wine backup, logs carried forward)

### What's NOT Changed

- Python installation (ETC handles this)
- Ham radio software (already in ETC)
- Wine/VARA installation (already in ETC)
- System packages (already optimized)

## Prerequisites

### Required Software (Ubuntu 22.04+ host OR running ETC system)
```bash
sudo apt update
sudo apt install -y xorriso squashfs-tools genisoimage p7zip-full wget git
```

### Required Files
1. **This repository**: Clone to your system
2. **secrets.env**: Your personalized configuration (created from template)

The build script automatically downloads the ETC installer from GitHub based on your release selection.

## Quick Start

### First Build (Fresh Install)

```bash
# Clone repository
cd ~/workspace/repos
git clone https://github.com/AlwaysLearningTech/emcomm-tools-customizer.git
cd emcomm-tools-customizer

# Create configuration
cp secrets.env.template secrets.env
nano secrets.env  # Fill in your values

# Build (downloads ETC installer automatically)
sudo ./build-etc-iso.sh -r stable

# Output: Built ISO in project directory
```

### Upgrade Build (From Running ETC System)

When upgrading to a new ETC release, run the build script **on your current ETC system**:

```bash
cd ~/emcomm-tools-customizer

# This automatically:
# 1. Runs et-user-backup to save your current settings
# 2. Builds new ISO with your settings baked in
# 3. Sets up auto-restore on first boot
sudo ./build-etc-iso.sh -r latest

# Copy to Ventoy and boot - your settings restore automatically!
```

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

# Provide existing Ubuntu ISO (skips download)
sudo ./build-etc-iso.sh -r stable -u ~/Downloads/ubuntu-22.10-desktop-amd64.iso

# Dry run (show what would happen)
./build-etc-iso.sh -d

# Verbose mode for debugging
sudo ./build-etc-iso.sh -r stable -v
```

### Option Reference

| Option | Description |
|--------|-------------|
| `-r <stable\|latest\|tag>` | Release mode: `stable` (GitHub Releases), `latest` (most recent tag), or `tag` (specific tag) |
| `-t <tag>` | Specify exact tag name (required when using `-r tag`) |
| `-l` | List available releases and tags from GitHub, then exit |
| `-u <path>` | Path to existing Ubuntu ISO file (skips download) |
| `-b <path>` | Path to .wine backup tar.gz |
| `-e <path>` | Path to et-user backup tar.gz |
| `-p <path>` | Path to private files directory or GitHub repo URL |
| `-c` | Cleanup mode: Remove embedded Ubuntu ISO to save space |
| `-d` | Dry-run mode (show what would be done) |
| `-v` | Verbose mode (enable bash debugging) |
| `-h` | Show help message |

### Release Modes Explained

The ETC project uses two types of versioning on GitHub:

**stable (`-r stable`):**
- Official GitHub Releases with semantic versions (e.g., 5.0.0)
- Tested and production-ready
- Example: `emcomm-tools-os-community-20251128-r5-final-5.0.0`
- Found at: https://github.com/thetechprepper/emcomm-tools-os-community/releases

**latest (`-r latest`):**
- Development/build tags pushed between releases
- May contain new features or fixes not yet in stable
- Example: `emcomm-tools-os-community-20251113-r5-build17`
- Found at: https://github.com/thetechprepper/emcomm-tools-os-community/tags

## Configuration Reference

### secrets.env Variables

```bash
# === User Identity ===
CALLSIGN="N0CALL"              # Your amateur radio callsign (REQUIRED)
USER_FULLNAME="Your Name"       # Full name for git commits
USER_EMAIL="you@example.com"    # Email for git commits
GRID_SQUARE="CN87"             # Maidenhead grid locator

# === System ===
MACHINE_NAME=""                 # Hostname (defaults to ETC-{CALLSIGN})

# === Desktop Preferences ===
DESKTOP_COLOR_SCHEME="prefer-dark"   # prefer-dark or prefer-light
DESKTOP_SCALING_FACTOR="1.0"         # 1.0, 1.25, 1.5, or 2.0
DISABLE_ACCESSIBILITY="yes"          # Disable screen reader, on-screen keyboard
DISABLE_AUTO_BRIGHTNESS="yes"        # Disable automatic backlight adjustment

# === WiFi Networks ===
# Add as many networks as needed with unique suffixes
WIFI_SSID_HOME="YourHomeNetwork"
WIFI_PASSWORD_HOME="YourHomePassword"
WIFI_AUTOCONNECT_HOME="yes"

WIFI_SSID_MOBILE="YourHotspot"
WIFI_PASSWORD_MOBILE="HotspotPassword"
WIFI_AUTOCONNECT_MOBILE="yes"

# === VARA License (Optional) ===
# VARA FM and VARA HF are SEPARATE products with separate licenses (~$69 each)
# Only fill in what you have purchased

VARA_FM_CALLSIGN=""            # Callsign registered with VARA FM license
VARA_FM_LICENSE_KEY=""         # Your VARA FM license key

# VARA HF is a separate purchase - leave blank if you don't have it
VARA_HF_CALLSIGN=""            # Callsign registered with VARA HF license
VARA_HF_LICENSE_KEY=""         # Your VARA HF license key

# === APRS Configuration ===
APRS_SSID="10"                 # SSID (see APRS SSID table below)
APRS_PASSCODE=""               # APRS-IS passcode (generate at aprs.fi)
APRS_SYMBOL_TABLE="/"          # Primary (/) or Alternate (\) table
APRS_SYMBOL_CODE=">"           # Symbol code (see APRS Symbol table below)
APRS_COMMENT="EmComm Station"  # Status/comment text
```

### About VARA Licenses

VARA is commercial software with **two separate products**:

| Product | Cost | Use Case | Purchase Link |
|---------|------|----------|---------------|
| **VARA FM** | ~$69 | VHF/UHF Winlink via FM repeaters or simplex. Most common for local EmComm. | [rosmodem.wordpress.com](https://rosmodem.wordpress.com/) |
| **VARA HF** | ~$69 | HF Winlink for long-distance communication when internet is unavailable. | [rosmodem.wordpress.com](https://rosmodem.wordpress.com/) |

**Purchase Process:**
1. Visit [rosmodem.wordpress.com](https://rosmodem.wordpress.com/)
2. Click on VARA FM or VARA HF
3. Follow the PayPal payment link
4. License key is emailed to you (usually within 24 hours)

**Most users only need VARA FM** for local emergency communications. VARA HF is for when you need to send Winlink messages over HF bands (long distance, grid-down scenarios).

Both work without a license in "demo mode" (slower speeds). The license unlocks full speed.

### APRS SSID Reference

| SSID | Usage |
|------|-------|
| 0 | Primary station (home, fixed) |
| 1 | Digipeater, fill-in digi |
| 2 | Digipeater (alternate) |
| 3 | Portable station |
| 4 | HF to VHF gateway |
| 5 | Smartphone, mobile app |
| 6 | Satellite ops, special |
| 7 | Handheld, walkie-talkie |
| 8 | Boat, maritime mobile |
| 9 | Mobile (car, truck, RV) |
| 10 | Internet, APRS-IS only |
| 11 | Balloon, aircraft, spacecraft |
| 12 | APRStt, DTMF, touchstone |
| 13 | Weather station |
| 14 | Trucking |
| 15 | Generic, other |

### APRS Symbol Reference

Symbols are specified with a two-character code: **table + symbol**.

**Primary Table Symbols (table = `/`)**

| Symbol Code | Icon | Description |
|-------------|------|-------------|
| `/>` | 🚗 | Car |
| `/y` | 🏠 | House with antenna |
| `/[` | 🚶 | Jogger/Walker (portable) |
| `/_` | 🌤️ | Weather station |
| `/!` | 🚔 | Police station |
| `/#` | 📍 | Digipeater |
| `/$` | 📞 | Phone |
| `/-` | 🏠 | House (QTH) |
| `/.` | ❌ | X / Unknown |
| `//` | 🔴 | Red Dot |
| `/?` | ❓ | Question mark |
| `/K` | 🏫 | School |
| `/R` | 🍽️ | Restaurant |
| `/Y` | ⛵ | Yacht/Sailboat |
| `/^` | ✈️ | Large aircraft |
| `/a` | 🚑 | Ambulance |
| `/b` | 🚲 | Bicycle |
| `/f` | 🚒 | Fire truck |
| `/k` | 🚚 | Truck |
| `/n` | 📡 | Node (packet) |
| `/s` | 🚢 | Ship (power) |
| `/u` | 🚌 | Bus |
| `/v` | 🚐 | Van |

**Alternate Table Symbols (table = `\`)**

| Symbol Code | Icon | Description |
|-------------|------|-------------|
| `\>` | 🚗 | Car (overlay capable) |
| `\a` | 🎪 | ARES/RACES |
| `\#` | 📍 | Digipeater (overlay) |
| `\&` | 🔷 | Diamond (overlay) |
| `\-` | 🏠 | House (HF) |
| `\0` | ⭕ | Circle (numbered) |
| `\K` | 🚁 | Helicopter |
| `\^` | ✈️ | Small aircraft |
| `\j` | 🏕️ | Camping |
| `\k` | 🏍️ | ATV/Motorcycle |
| `\n` | 🔺 | Triangle (overlay) |
| `\s` | 🛥️ | Small boat |
| `\v` | 📺 | ATV (overlay) |

**Common Configurations:**

```bash
# Mobile station (car)
APRS_SYMBOL_TABLE="/"
APRS_SYMBOL_CODE=">"
# Full symbol: />

# Home station with antenna
APRS_SYMBOL_TABLE="/"
APRS_SYMBOL_CODE="y"
# Full symbol: /y

# Portable/handheld
APRS_SYMBOL_TABLE="/"
APRS_SYMBOL_CODE="["
# Full symbol: /[

# ARES/RACES emergency
APRS_SYMBOL_TABLE="\"
APRS_SYMBOL_CODE="a"
# Full symbol: \a

# Weather station
APRS_SYMBOL_TABLE="/"
APRS_SYMBOL_CODE="_"
# Full symbol: /_
```

## Directory Structure

```
emcomm-tools-customizer/
├── README.md                    # This file
├── QUICK_START.md              # Quick reference guide
├── build-custom-iso.sh          # Main build script
├── secrets.env.template         # Configuration template (safe to commit)
├── secrets.env                  # Your config (NEVER commit)
├── cache/                       # PERSISTENT - carried forward into each ISO
│   ├── ETC-R5.iso              # Base ETC ISO (downloaded once)
│   ├── wine-backup.tar.gz      # VARA configuration (created once)
│   ├── etuser-backup.tar.gz    # User settings (auto-updated each build)
│   └── logs/                   # Build logs (persistent history)
│       ├── build-20240115.log
│       └── build-20240120.log
├── output/                      # Generated custom ISOs
│   └── ETC-custom-YYYYMMDD.iso
└── .github/
    └── copilot-instructions.md
```

## Persistent Cache Architecture

The `./cache/` directory is **carried forward into every ISO** you build. This provides:

### What's in the Cache

| File | Purpose | Created | Updated |
|------|---------|---------|---------|
| `ETC-R5.iso` | Base ETC ISO for future rebuilds | First build | Never (delete to re-download) |
| `wine-backup.tar.gz` | VARA license & config | Once (fresh install) | Never (unless VARA reinstalled) |
| `etuser-backup.tar.gz` | Callsign, grid, radio settings | Each build | Auto before each build |
| `logs/` | Build history | Each build | Each build |

### How It Works

1. **On your build machine**: `./cache/` contains your files
2. **During build**: Cache is copied into ISO at `/opt/emcomm-customizer/cache/`
3. **On deployed system**: Cache is available for the next upgrade build
4. **Upgrade workflow**: Run build script on deployed system → uses local cache

### Location on Deployed System

After installing your custom ISO, the cache lives at:
```
/opt/emcomm-customizer/
├── cache/
│   ├── ETC-R5.iso
│   ├── wine-backup.tar.gz
│   ├── etuser-backup.tar.gz
│   └── logs/
├── build-custom-iso.sh
├── secrets.env
└── secrets.env.template
```

## Automatic Backup/Restore Workflow

### The et-user Commands (Upstream ETC)

ETC provides these commands for managing user settings:

- **`et-user-backup`**: Saves callsign, grid, radio config, Pat settings, etc.
- **`et-user-restore`**: Restores settings from backup

### How This Project Automates It

**When you run `./build-custom-iso.sh` on a running ETC system:**

1. **Pre-build**: Automatically runs `et-user-backup`
   - Output saved to `./cache/etuser-backup.tar.gz`
   - Captures your current callsign, grid, radio preferences

2. **During build**: Backup is included in new ISO
   - Placed in `/opt/emcomm-customizer/cache/`

3. **First boot**: Auto-restore runs
   - A systemd service calls `et-user-restore` with the backup
   - Your settings are restored before you log in

**Result**: Boot new ISO → settings already configured → no manual setup!

### Manual Backup (Optional)

If you want to create a backup without building:

```bash
# On running ETC system
et-user-backup
cp ~/et-user-backup.tar.gz ./cache/etuser-backup.tar.gz
```

## Wine/VARA Backup

### ⚠️ CRITICAL: Wine Backup Best Practices

The Wine backup captures your VARA configuration. **There are strict rules:**

#### ✅ CORRECT: Backup from Fresh VARA Installation

Create your Wine backup from a system where:
1. VARA FM/HF has been **installed but NEVER opened/run**
2. Or VARA was opened ONLY to enter the license key, then **immediately closed**

```bash
# On a fresh ETC installation (VARA never opened):
./build-custom-iso.sh --create-wine-backup
```

#### ❌ WRONG: Backup After Using VARA

**DO NOT** backup Wine after:
- Opening and using VARA FM/HF
- Running any Winlink sessions
- Letting VARA create session logs

The upstream ETC creator warns that Wine state becomes corrupted after VARA has been used.

### Creating Wine Backup

```bash
# VARA must never have been opened!
./build-custom-iso.sh --create-wine-backup

# Creates: ./cache/wine-backup.tar.gz
```

This backup is reused for all future builds (carried forward in cache).

## Upgrade Workflow

### Standard Upgrade (Settings Preserved)

```bash
# 1. On your running ETC system, navigate to customizer
cd /opt/emcomm-customizer

# 2. Pull latest customizer updates (optional)
git pull

# 3. Build new ISO (auto-backs up current settings)
sudo ./build-custom-iso.sh --release latest

# 4. Copy to Ventoy USB
cp ./output/ETC-custom-*.iso /media/ventoy/

# 5. Boot from Ventoy
# → Settings restore automatically on first login!
```

### What Gets Preserved

| Setting | Source |
|---------|--------|
| Callsign & Grid | et-user-backup |
| Radio hardware selection | et-user-backup |
| Pat/Winlink config | et-user-backup |
| APRS settings | et-user-backup |
| VARA license | Wine backup + secrets.env |
| WiFi networks | secrets.env |
| Desktop preferences | secrets.env |

## Using with Ventoy

The output ISO is ready for Ventoy:

1. Build your custom ISO: `sudo ./build-custom-iso.sh`
2. Copy `./output/ETC-custom-YYYYMMDD.iso` to your Ventoy USB drive
3. Boot from Ventoy and select the ISO
4. Settings restore automatically on first boot

## Troubleshooting

### Build fails with "permission denied"
Run with sudo: `sudo ./build-custom-iso.sh`

### et-user-backup fails
- Ensure you're running on an ETC system (not vanilla Ubuntu)
- Check that `et-user-backup` command exists: `which et-user-backup`

### WiFi not connecting after boot
- Verify SSID/password in secrets.env (check for typos)
- Special characters may need escaping
- Check: `journalctl -u NetworkManager`

### Settings not restored after boot
- Check that `etuser-backup.tar.gz` exists in cache
- Look for errors in: `journalctl -u emcomm-restore.service`

### VARA license not applied
- Ensure callsign matches the license exactly (case-sensitive)
- VARA FM and VARA HF are separate licenses (~$69 each)
- Purchase at [rosmodem.wordpress.com](https://rosmodem.wordpress.com/)
- Check Wine registry after boot: `wine regedit`

### ISO download fails
- Check internet connection
- Verify ETC download URL is accessible
- Manually download and use `--source`

## Comparison: This vs Cubic

| Feature | This Project | Cubic |
|---------|--------------|-------|
| Automation | ✅ Fully scripted | ❌ Manual GUI |
| Reproducibility | ✅ Same input = same output | ⚠️ Depends on manual steps |
| Settings Preserved | ✅ Auto backup/restore | ❌ Manual |
| Persistent Cache | ✅ Carried forward | ❌ Not available |
| CI/CD Compatible | ✅ Yes | ❌ No |

## Security Notes

- **Never commit secrets.env** - contains passwords and license keys
- **secrets.env.template is safe** - placeholder values only
- **Custom ISO contains passwords** - treat as sensitive
- **Wine backup may contain license** - store securely
- **Cache is in the ISO** - anyone with the ISO has access

## Credits

- **Upstream**: [TheTechPrepper - EmComm Tools Community](https://github.com/thetechprepper/emcomm-tools-os-community)
- **Documentation**: [community.emcommtools.com](https://community.emcommtools.com/)
- **VARA Software**: [EA5HVK - rosmodem.wordpress.com](https://rosmodem.wordpress.com/)

## License

MIT License - See LICENSE file for details.

---

**73 de KD7DGF** 📻
