# EmComm Tools Customizer

Fully automated customization of EmComm Tools Community (ETC) ISO images using xorriso/squashfs. No GUI required.

## Overview

**Upstream Project**: [EmComm Tools Community](https://github.com/thetechprepper/emcomm-tools-os-community)  
**Documentation**: [community.emcommtools.com](https://community.emcommtools.com/)

### What Gets Customized

ETC already includes all ham radio tools (Winlink, VARA, JS8Call, fldigi, etc.). This customizer adds:

- ✅ Pre-configured WiFi networks (auto-connect on boot)
- ✅ Personal callsign and grid square (pre-populated for `et-user`)
- ✅ Hostname set to `ETC-{CALLSIGN}`
- ✅ Desktop preferences (dark mode, scaling, accessibility)
- ✅ Display & screen management (brightness, dimming, blank timeout)
- ✅ Power management (sleep behavior, power profiles, idle actions)
- ✅ System timezone configuration
- ✅ Additional development packages (VS Code, Node.js, npm, git)
- ✅ VARA FM/HF license `.reg` files + import script (run post-install after VARA installation)
- ✅ APRS configuration (iGate, beaconing with symbol/comment)
- ✅ Git configuration
- ✅ Embedded cache files for faster rebuilds (use `-m` for minimal)

### What's NOT Changed

This customizer **respects upstream ETC architecture**. We:

- Keep ETC's runtime template system (et-direwolf, et-yaac, etc.)
- Modify templates in-place, keeping `{{ET_*}}` placeholders
- Don't change package selections or install additional software
- Don't pre-install VARA or Wine prefix (these require a desktop session post-install)

**ETC Architecture**: ETC uses runtime template processing. When you run `et-direwolf`, `et-yaac`, or `et-winlink`, these wrapper scripts read from `~/.config/emcomm-tools/user.json` and generate configs dynamically. We pre-populate `user.json` so you skip the `et-user` prompt on first boot.

**APRS Customization**: We modify ETC's direwolf template at `/opt/emcomm-tools/conf/template.d/packet/direwolf.aprs-digipeater.conf` to add iGate and beacon settings while preserving the `{{ET_CALLSIGN}}` and `{{ET_AUDIO_DEVICE}}` placeholders that ETC substitutes at runtime.

## Release Status: v1.0 (First Working Build)

### ✅ What's Working

- **Build process**: Fully automated ETC ISO customization via xorriso/squashfs
- **WiFi configuration**: Networks are pre-configured in NetworkManager
- **APRS setup**: direwolf iGate/beacon templates customized and ready for runtime use
- **User config**: `~/.config/emcomm-tools/user.json` pre-populated with callsign, grid, Winlink password
- **Desktop settings**: Dark mode, scaling, accessibility, display, power management, timezone all applied
- **Git config**: User name/email configured
- **VARA license setup**: `.reg` files and import script created for post-install use
- **Additional packages**: Development tools (git, nodejs, npm, uv) installable via configuration
- **Cache system**: Downloaded ISOs cached for faster rebuilds
- **Preseed automation**: Ubuntu 22.10 installer automated with hostname, username, password, timezone
- **Anytone D578UV radio**: Radio configuration added to et-radio menu (rigctrl ID 301)

### ⚠️ Known Limitations (v1.0)

Preseed file now **AUTOMATES** Ubuntu installer—hostname, username, password, and timezone are pre-configured.

**Workflow (Current)**:
1. Boot custom ISO
2. Ubuntu installer runs **silently** with pre-configured hostname, username, password, timezone
3. System boots directly to desktop (or login prompt if autologin disabled)
4. All other customizations (WiFi, APRS, desktop settings, etc.) apply automatically
5. **Zero manual prompts** during installation

**Advanced**: To customize preseed behavior further (partitioning, packages, etc.), edit the `customize_preseed()` function in `build-etc-iso.sh` and regenerate the ISO.

### Future Work (Tracked in GitHub Issues)

Remaining planned features for future releases:

- **#3** - WiFi network connection validation and troubleshooting
- **#2** - Post-install script for first-boot customizations

View all work: [GitHub Issues](https://github.com/AlwaysLearningTech/emcomm-tools-customizer/issues)

### Build Logs & Diagnostics

Build logs are automatically created and embedded in the ISO for post-install diagnostics:

**On the build machine (after running build script)**:
```bash
# View the latest build log
less logs/build-etc-iso_YYYYMMDD_HHMMSS.log

# View all build logs
ls logs/
```

**On the installed system**:
```bash
# Logs are embedded in the ISO and available at:
/opt/emcomm-customizer-cache/logs/

# Copy to home directory for easy access:
mkdir -p ~/.emcomm-customizer/logs
cp /opt/emcomm-customizer-cache/logs/* ~/.emcomm-customizer/logs/

# View the build manifest (summary of what was customized)
less ~/.emcomm-customizer/logs/BUILD_MANIFEST.txt
```

The build manifest includes:
- Build date and ETC version
- Configuration snapshot (callsign, hostname, WiFi networks, APRS settings)
- Number of successful customization steps
- List of all operations performed

Use the logs to debug issues like WiFi configuration, APRS settings, or any failed customizations.

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

# Minimal build (smaller ISO, no embedded cache files)
sudo ./build-etc-iso.sh -r stable -m

# Debug mode (show detailed DEBUG log messages)
sudo ./build-etc-iso.sh -r stable -d

# Verbose mode for maximum debugging (bash -x)
sudo ./build-etc-iso.sh -r stable -v
```

### Option Reference

| Option | Description |
|--------|-------------|
| `-r <stable\|latest\|tag>` | Release mode |
| `-t <tag>` | Specific tag name (required with `-r tag`) |
| `-l` | List available releases and tags |
| `-m` | Minimal build (exclude cache files, saves ~4GB) |
| `-d` | Debug mode (show DEBUG log messages) |
| `-v` | Verbose mode (bash -x tracing) |
| `-h` | Show help |

### Release Modes

| Mode | Description | Source |
|------|-------------|--------|
| `stable` | Latest GitHub Release (production-ready) | [Releases](https://github.com/thetechprepper/emcomm-tools-os-community/releases) |
| `latest` | Most recent git tag (development) | [Tags](https://github.com/thetechprepper/emcomm-tools-os-community/tags) |
| `tag` | Specific tag by name | Use with `-t` |

### Build Size

By default, cache files (Ubuntu ISO, ETC tarballs) are embedded in `/opt/emcomm-customizer-cache/`
so they're available for the next build on the installed system. This is useful when building
on the same machine you install to.

Use `-m` for a minimal build that excludes these files (saves ~4GB).

## Configuration Reference

### secrets.env Variables

```bash
# === User Identity (REQUIRED) ===
CALLSIGN="N0CALL"              # Your amateur radio callsign
USER_FULLNAME="Your Name"       # Full name for git commits
USER_EMAIL="you@example.com"    # Email for git commits
GRID_SQUARE="CN87"             # Maidenhead grid locator

# === User Account ===
USER_USERNAME=""                # Linux username (defaults to lowercase CALLSIGN)
USER_PASSWORD=""                # Password (leave blank to keep ETC default)
ENABLE_AUTOLOGIN="no"          # "yes" or "no" - default is NO (password prompt)

# === System ===
MACHINE_NAME=""                 # Hostname (defaults to ETC-{CALLSIGN})
TIMEZONE="America/Denver"       # System timezone (Linux format, see /usr/share/zoneinfo/)

# === Desktop Preferences ===
DESKTOP_COLOR_SCHEME="prefer-dark"  # prefer-dark or prefer-light
DESKTOP_SCALING_FACTOR="1.0"        # 1.0, 1.25, 1.5, or 2.0
DISABLE_ACCESSIBILITY="yes"         # yes = disable screen reader, on-screen keyboard

# === Display & Screen Management ===
AUTOMATIC_SCREEN_BRIGHTNESS="false" # true = adaptive brightness, false = manual
DIM_SCREEN="true"                   # true = dim screen during idle
SCREEN_BLANK="true"                 # true = blank screen after idle timeout
SCREEN_BLANK_TIMEOUT="300"          # Seconds before screen blanks (300=5min)

# === Power Management ===
POWER_MODE="balanced"               # balanced, performance, or power-saver
POWER_LID_CLOSE_AC="suspend"        # AC lid close: nothing, suspend, hibernate, logout
POWER_LID_CLOSE_BATTERY="suspend"   # Battery lid close: nothing, suspend, hibernate, logout
POWER_BUTTON_ACTION="interactive"   # Power button: nothing, suspend, hibernate, interactive
POWER_IDLE_AC="nothing"             # AC idle action: nothing, suspend, hibernate
POWER_IDLE_BATTERY="suspend"        # Battery idle action: nothing, suspend, hibernate
POWER_IDLE_TIMEOUT="900"            # Seconds before idle action (900=15min)
AUTOMATIC_POWER_SAVER="true"        # true = enable power saver on battery
AUTOMATIC_SUSPEND="true"            # true = enable automatic suspend

# === Additional System Packages ===
ADDITIONAL_PACKAGES="code git nodejs npm"  # Space-separated apt packages to install

# === WiFi Networks ===
WIFI_SSID_HOME="YourHomeNetwork"
WIFI_PASSWORD_HOME="YourHomePassword"
WIFI_AUTOCONNECT_HOME="yes"

WIFI_SSID_MOBILE="YourHotspot"
WIFI_PASSWORD_MOBILE="HotspotPassword"
WIFI_AUTOCONNECT_MOBILE="yes"

# === Winlink ===
WINLINK_PASSWORD=""            # Your Winlink password

# === APRS Configuration ===
APRS_SSID="10"                 # SSID (0-15, 10=iGate)
```
APRS_PASSCODE="-1"             # APRS-IS passcode (-1=RX only)
APRS_SYMBOL="/r"               # Symbol: table+code (/r=antenna)
APRS_COMMENT="EmComm iGate"    # Beacon comment

# APRS Beacon (position beaconing)
ENABLE_APRS_BEACON="no"        # Enable position beaconing
APRS_BEACON_INTERVAL="300"     # Seconds between beacons
APRS_BEACON_VIA="WIDE1-1"      # Digipeater path
APRS_BEACON_POWER="10"         # PHG: Power in watts
APRS_BEACON_HEIGHT="20"        # PHG: Antenna height (feet)
APRS_BEACON_GAIN="3"           # PHG: Antenna gain (dBi)

# APRS iGate (RF to Internet gateway)
ENABLE_APRS_IGATE="yes"        # Enable iGate
APRS_SERVER="noam.aprs2.net"   # APRS-IS server

# Direwolf Audio
DIREWOLF_ADEVICE="plughw:1,0"  # Audio device (Digirig)
DIREWOLF_PTT="CM108"           # PTT method

# === VARA License (Optional) ===
VARA_FM_CALLSIGN=""            # Callsign registered with VARA FM license
VARA_FM_LICENSE_KEY=""         # Your VARA FM license key
VARA_HF_CALLSIGN=""            # Callsign registered with VARA HF license  
VARA_HF_LICENSE_KEY=""         # Your VARA HF license key

# === Pat Winlink Aliases ===
PAT_EMCOMM_ALIAS="yes"         # Create "emcomm" quick-connect alias
PAT_EMCOMM_GATEWAY=""          # Gateway callsign (e.g., "W7ACS-10")

# === Power Management ===
POWER_LID_CLOSE_AC="suspend"      # Lid close on AC power
POWER_LID_CLOSE_BATTERY="suspend" # Lid close on battery
POWER_BUTTON_ACTION="interactive" # Power button action
POWER_IDLE_AC="nothing"           # Idle action on AC
POWER_IDLE_BATTERY="suspend"      # Idle action on battery
POWER_IDLE_TIMEOUT="900"          # Idle timeout (seconds)
```

### Partition & Installation Modes

If you're installing on a **dual-boot system** (Windows + ETC), use these settings to ensure the build script only modifies your ETC partition, not the entire disk:

```bash
# === PARTITION MODE (Dual-Boot Safe) ===
# Install onto a specific partition (e.g., sda5, sda6)
# This is SAFE for dual-boot systems - only that partition is modified
INSTALL_DISK="/dev/sda5"          # Target partition (not entire disk!)
INSTALL_SWAP="/dev/sda6"          # Swap partition (if separate)
CONFIRM_ENTIRE_DISK="no"          # Keep as "no" for dual-boot

# === ENTIRE-DISK MODE (Fresh Install Only) ===
# WARNING: This will ERASE the entire disk and create new partitions with LVM
# Only use this for dedicated ETC systems, not dual-boot
# Uncomment to use entire-disk mode (NOT RECOMMENDED):
# INSTALL_DISK="/dev/sda"           # Entire disk (DESTRUCTIVE!)
# CONFIRM_ENTIRE_DISK="yes"         # MUST set to "yes" to enable entire-disk
```

**How partition detection works:**

| INSTALL_DISK | Mode | Behavior | When to Use |
|--------------|------|----------|-------------|
| `/dev/sda5` | Partition | Uses manual partitioning for just this partition | Dual-boot (Windows + ETC) |
| `/dev/sda` | Entire Disk | Auto-partitions entire disk with LVM, requires CONFIRM_ENTIRE_DISK="yes" | Fresh install, no dual-boot |
| `/dev/nvme0n1p1` | Partition | Manual partitioning for this NVMe partition | Dual-boot with NVMe drive |
| `/dev/nvme0n1` | Entire Disk | Auto-partitions entire NVMe disk, requires confirmation | Fresh NVMe install |

**Safety features:**

- Partition mode (`/dev/sda5`) uses **manual partitioning** during Ubuntu install (user confirms)
- Entire-disk mode (`/dev/sda`) requires **CONFIRM_ENTIRE_DISK="yes"** - prevents accidental data loss
- Build script validates INSTALL_DISK format and warns before generating preseed

### About VARA Licenses

VARA is commercial software with **two separate products**:

| Product | Cost | Use Case |
|---------|------|----------|
| **VARA FM** | ~$69 | VHF/UHF Winlink via FM repeaters |
| **VARA HF** | ~$69 | HF Winlink for long-distance |

Purchase at [rosmodem.wordpress.com](https://rosmodem.wordpress.com/)

**Important:** VARA licenses are applied **after** VARA installation, not during ISO build:

1. **Install VARA** (post-install, requires desktop session):
   ```bash
   cd ~/add-ons/wine
   ./01-install-wine-deps.sh
   ./02-install-vara-hf.sh    # If you use HF
   ./03-install-vara-fm.sh    # If you use FM
   ```

2. **Import license keys** (if configured in secrets.env):
   ```bash
   ./99-import-vara-licenses.sh
   ```

The build script creates `.reg` files and an import script in `~/add-ons/wine/`. This is because Wine's prefix (`~/.wine32`) doesn't exist until you run the VARA installers.

### Pat Winlink Aliases

Pat is the Winlink client on ETC. The `emcomm` alias adds a quick-connect shortcut to your standard Pat config:

```bash
pat connect emcomm    # Quick connect to your configured gateway
```

After first boot, run `~/.config/pat/add-emcomm-alias.sh` to add the alias to your Pat config.

### Post-Install User Configuration Restoration

If you have a backup from a previous ETC installation, you can restore your configurations (callsign, WiFi passwords, APRS settings, maps, etc.) after the new system boots.

**When to restore:**
- You're rebuilding ETC on the same hardware and want to preserve your previous settings
- You have a backup tarball from a previous installation: `etc-user-backup-*.tar.gz`

**How to restore:**

After the OS boots and you're logged in, run:

```bash
# Copy backup to home directory if not already there
cp /path/to/etc-user-backup-*.tar.gz ~

# Optional: List what will be restored
tar tzf ~/etc-user-backup-*.tar.gz | head -20

# Restore user configuration (interactive)
~/add-ons/post-install/02-restore-user-backup.sh

# Restore with Wine/VARA prefix (larger, use if you backed up VARA)
~/add-ons/post-install/02-restore-user-backup.sh --wine
```

**What gets restored:**

- `~/.config/emcomm-tools/` - ETC configuration (callsign, grid, user.json)
- `~/.local/share/emcomm-tools/` - Maps, tilesets, application data
- `~/.local/share/pat/` - Winlink Pat settings (mailbox passwords, aliases)
- `~/.wine32/` - Wine prefix (optional, only if --wine flag used)

**Options:**

```bash
./02-restore-user-backup.sh --help        # Show help

./02-restore-user-backup.sh               # Restore user config only
./02-restore-user-backup.sh -d ~/backups  # From specific directory
./02-restore-user-backup.sh --wine        # Also restore Wine/VARA prefix
./02-restore-user-backup.sh --verbose     # Show detailed output
./02-restore-user-backup.sh --force       # Overwrite existing files
```

**Note:** User backups (611MB+) are **not** embedded in the ISO to avoid hanging the build process. They're restored post-install instead.

### Power Management Options

| Setting | Options | Description |
|---------|---------|-------------|
| Lid Close | `nothing`, `suspend`, `hibernate`, `logout` | What happens when laptop lid closes |
| Power Button | `interactive`, `suspend`, `hibernate`, `poweroff` | Power button behavior |
| Idle Action | `nothing`, `suspend`, `hibernate` | Action after idle timeout |
| Idle Timeout | Seconds (e.g., `900` = 15 min) | Time before idle action triggers |

### ETC Build Options & Map Downloads

These variables control ETC's optional features and map downloads during the ISO build.

**Interactive vs Automated Builds:**
- **Variables configured** → Downloads happen automatically, no prompts
- **Variables blank** → Original ETC dialog prompts appear during build
- This ensures future ETC versions with new dialogs still work interactively

| Variable | Options | Description |
|----------|---------|-------------|
| `OSM_MAP_STATE` | US state name (lowercase) | OpenStreetMap data for offline Navit navigation |
| `ET_MAP_REGION` | `us`, `ca`, `world` | Pre-rendered raster tiles for YAAC and other apps |
| `ET_EXPERT` | `yes` or blank | Enables Wikipedia download (ETC internal variable) |
| `WIKIPEDIA_SECTIONS` | Comma-separated list | Offline Wikipedia sections (requires ET_EXPERT=yes) |

**Note about ET_EXPERT:** This is an undocumented ETC variable. When set, it:
1. Enables the Wikipedia download dialog during install
2. Shows a Wine info textbox during wine installation

Leave blank unless you want Wikipedia offline content.

**OSM State Names:** Use lowercase state names from [Geofabrik US](https://download.geofabrik.de/north-america/us.html):
`alabama`, `alaska`, `arizona`, `arkansas`, `california`, `colorado`, `connecticut`, `delaware`, `district-of-columbia`, `florida`, `georgia`, `hawaii`, `idaho`, `illinois`, `indiana`, `iowa`, `kansas`, `kentucky`, `louisiana`, `maine`, `maryland`, `massachusetts`, `michigan`, `minnesota`, `mississippi`, `missouri`, `montana`, `nebraska`, `nevada`, `new-hampshire`, `new-jersey`, `new-mexico`, `new-york`, `north-carolina`, `north-dakota`, `ohio`, `oklahoma`, `oregon`, `pennsylvania`, `rhode-island`, `south-carolina`, `south-dakota`, `tennessee`, `texas`, `utah`, `vermont`, `virginia`, `washington`, `west-virginia`, `wisconsin`, `wyoming`

**ET Map Regions:**
| Region | File Size | Coverage |
|--------|-----------|----------|
| `us` | ~2.5 GB | United States, zoom 0-11 |
| `ca` | ~1.5 GB | Canada, zoom 0-10 |
| `world` | ~500 MB | Global, zoom 0-7 |

**Wikipedia Sections:** Available sections for offline Wikipedia:
`computer`, `history`, `mathematics`, `medicine`, `simple`

**Examples:**

```bash
# Fully automated build (no Wikipedia)
OSM_MAP_STATE="washington"
ET_MAP_REGION="us"
ET_EXPERT=""
WIKIPEDIA_SECTIONS=""

# Fully automated with Wikipedia
OSM_MAP_STATE="washington"
ET_MAP_REGION="us"
ET_EXPERT="yes"
WIKIPEDIA_SECTIONS="computer,medicine"

# Semi-automated - let dialog prompt for maps you're unsure about
OSM_MAP_STATE=""                 # Will show dialog to pick state
ET_MAP_REGION="us"               # Auto-download US tiles
```

### Wikipedia Offline Content

There are **two ways** to get offline Wikipedia content on ETC:

#### Option 1: ETC's Pre-Built Collections (Large Files)

Set `ET_EXPERT="yes"` and `WIKIPEDIA_SECTIONS="computer,medicine"` to download pre-built .zim files from Kiwix during the build. These are large files (100-500MB each) covering entire topic areas.

#### Option 2: Custom Ham Radio Articles (Recommended)

This customizer includes a script to create a small, targeted .zim file with just the Wikipedia articles relevant to ham radio operators.

**Configuration:**
```bash
# In secrets.env - specify individual articles (pipe-separated)
WIKIPEDIA_ARTICLES="2-meter_band|70-centimeter_band|General_Mobile_Radio_Service|Family_Radio_Service"
```

**Default articles include:**
- Band information: 2-meter band, 70-centimeter band, HF/VHF/UHF
- Radio services: GMRS, FRS, MURS, Citizens Band
- Digital modes: APRS, Winlink, DMR, D-STAR, System Fusion
- Emergency comms: Amateur radio emergency communications
- General ham radio topics: Repeaters, simplex, antennas, propagation

**Post-Install Usage:**
After first boot, run the Wikipedia ZIM creator:
```bash
cd ~/add-ons/wikipedia
./create-my-wikipedia.sh
```

This downloads your configured articles and creates a .zim file in `~/wikipedia/` that you can view with Kiwix:
```bash
# Start local server
kiwix-serve --port=8080 ~/wikipedia/ham-radio-wikipedia_*.zim

# Open http://localhost:8080 in browser
```

**Note:** The custom .zim creator is a post-install script because it requires network access and takes a few minutes to run. It's NOT embedded in the ISO build.

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
| `/r` | 📻 | Antenna/Portable |
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

### ISO boots as vanilla Ubuntu (not ETC)

**Symptom**: The built ISO boots into a standard Ubuntu installer asking you to create a user, with none of the ETC tools installed.

**Cause**: The ETC installer (install.sh) failed silently during the chroot phase.

**Fixes** (as of v1.1.0):
- Build now verifies the ETC tarball extraction was successful
- Build now verifies ETC installation by checking for `/opt/emcomm-tools` and `et-user`
- Build now properly captures the chroot exit code

If you still encounter this, run with `-d` flag for debug output and check the log file in `logs/`.

### Screen brightness broken after install (Windows and Linux)

**Symptom**: After installing the ISO on a dual-boot system (especially Panasonic Toughbook FZ-G1), screen brightness controls no longer work in either Windows or Ubuntu.

**Causes**: The Intel graphics backlight controller can get confused by ACPI/UEFI state changes during OS installation.

**Fixes**:

1. **Try BIOS reset**: Power off completely, enter BIOS setup, and load "Setup Defaults" then save and exit.

2. **Windows Device Manager**: Device Manager → Display Adapters → Intel HD Graphics → Update/Rollback Driver

3. **Ubuntu kernel parameters**: Edit `/etc/default/grub`, find the `GRUB_CMDLINE_LINUX_DEFAULT` line and add one of:
   ```
   acpi_backlight=vendor
   acpi_backlight=video
   acpi_backlight=native
   ```
   Then run `sudo update-grub` and reboot.

4. **Intel xbacklight**: Install `xbacklight` and use it directly:
   ```bash
   sudo apt install xbacklight
   xbacklight -set 50  # Set to 50%
   ```

5. **Direct sysfs control** (last resort):
   ```bash
   # Find the backlight device
   ls /sys/class/backlight/
   # Typically intel_backlight or acpi_video0
   
   # Read max brightness
   cat /sys/class/backlight/intel_backlight/max_brightness
   
   # Set brightness (example: 500)
   echo 500 | sudo tee /sys/class/backlight/intel_backlight/brightness
   ```

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
3. **Install ETC**: Runs ETC's install.sh in chroot to install all ham radio tools
4. **Verify**: Confirms ETC installed correctly by checking for key files
5. **Customize**: Modifies `/etc/skel/` and system configs with your settings
6. **Rebuild**: Creates new squashfs and ISO with xorriso

All customizations go into `/etc/skel/` so they apply to new users automatically.

## License

MIT License - See LICENSE file

## Credits

- **EmComm Tools Community**: [thetechprepper](https://github.com/thetechprepper/emcomm-tools-os-community)
- **Customizer**: KD7DGF

---

**73 de KD7DGF** 📻
