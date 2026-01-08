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
- ✅ **VARA license pre-registration** (manual registry edit → backup → auto-restore on builds)
- ✅ **Automatic user config restoration** (from `etc-user-backup-*.tar.gz` if present)
- ✅ **APRS configuration** (iGate, beacon, digipeater with smart beaconing)
- ✅ **Ham radio CAT control** (Anytone D578UV with DigiRig Mobile, rigctld auto-start)
- ✅ **Optional et-os-addons overlay** (if cached):
  - GridTracker, WSJT-X Improved, QSSTV, XYGrib, Kiwix, JS8Spotter, NetControl
  - No internet required - use existing cache or skip
- ✅ Git configuration
- ✅ Embedded cache files for faster rebuilds (use `-m` for minimal)

### What's NOT Changed

This customizer **respects upstream ETC architecture**. We:

- Keep ETC's runtime template system (et-direwolf, et-yaac, etc.)
- Modify templates in-place, keeping `{{ET_*}}` placeholders
- Don't change package selections or install additional software
- Don't pre-install VARA or Wine prefix (these require a desktop session post-install)

## Release Status: v1.0 (First Working Build)

### ✅ What's Working

- **Build process**: Fully automated ETC ISO customization via xorriso/squashfs
- **WiFi configuration**: Networks are pre-configured in NetworkManager
- **User config restoration**: Automatic backup extraction (etc-user-backup-*.tar.gz)
  - User settings restored during ISO build
  - Wine prefix auto-restored on first login post-install
  - 300-second timeout prevents build hangs
  - Progress tracking for large backups
- **APRS configuration**: Full direwolf template customization
  - iGate mode (internet gateway) with APRS-IS login
  - Smart beaconing with configurable interval
  - Digipeater WIDE path support
  - Separate from Packet/Winlink (no conflicts)
- **Ham radio CAT control**: Anytone D578UV with DigiRig Mobile
  - Rigctld daemon auto-starts at boot (localhost:4532)
  - Active radio config automatically created
  - udev rules for /dev/et-cat symlink (CP2102/CH340/PL2303/FTDI)
  - Users can select different radio via `et-radio` after boot
- **D578 CAT Control**: DigiRig Mobile configuration for CAT control (et-mode packet/Winlink compatible)
- **User config**: `~/.config/emcomm-tools/user.json` pre-populated with callsign, grid, Winlink password
- **Desktop settings**: Dark mode, scaling, accessibility, display, power management, timezone all applied
- **Git config**: User name/email configured
- **VARA license setup**: Pre-register via Wine registry, create backup, auto-restore on builds
- **Single post-install script**: Verification, backup restoration, and CHIRP installation via pipx
- **Additional packages**: Development tools (git, nodejs, npm, uv) installable via configuration
- **Cache system**: Downloaded ISOs cached for faster rebuilds
- **Preseed automation**: Ubuntu 22.10 installer fully automated with debian-installer (d-i)
  - No interactive prompts: keyboard, locale, hostname, username, password, timezone, partitioning all preseed-driven
  - Text-based installer (d-i) respects all preseed directives including partitioning
- **Anytone D578UV radio**: Radio configuration added to et-radio menu (rigctrl ID 301)

## Fully Automated Installation

The ISO uses **debian-installer (d-i)** with preseed for zero-interaction installation. All setup questions are answered automatically from your configuration.

**Automated Installation Workflow**:
1. Boot custom ISO from Ventoy
2. GRUB menu shows all available OSes (dual-boot preserved)
3. Select Ubuntu/EmComm Tools entry from menu
4. GRUB loads preseed from `preseed/file=/cdrom/preseed.cfg`
5. Preseed parameters: `auto=true priority=critical` (enable automatic mode)
6. **Debian-installer runs WITHOUT user prompts** for:
   - Keyboard layout
   - Locale / language
   - Hostname (set to `ETC-{CALLSIGN}`)
   - Username (set from config)
   - Password (hashed in preseed)
   - Timezone
   - Partitioning (strategy-aware, respects dual-boot)
   - Package selection (ubuntu-desktop task)
7. System boots directly to desktop (or login prompt if autologin disabled)
8. All customizations apply automatically (WiFi, APRS, desktop settings, CAT control, etc.)

**Why debian-installer instead of ubiquity?**

The original approach used Ubuntu's ubiquity (GUI installer) with `automatic-ubiquity` boot parameter. However:
- ✅ Ubiquity **ignores partitioning directives** in preseed - asks user anyway
- ✅ Ubiquity **ignores many d-i settings** (not designed for full automation)
- ✅ Ubiquity **can't skip accessibility/release notes questions**
- ✅ Debian-installer **respects ALL preseed directives** including full partitioning
- ✅ D-i is **text-based** - faster, no GUI overhead

The debian-installer is the standard Debian/Ubuntu preseed solution and provides true "set it and forget it" automation.

**Preseed File & Boot Parameters**:

The GRUB configuration is automatically updated to:
```bash
linux /casper/vmlinuz preseed/file=/cdrom/preseed.cfg auto=true priority=critical maybe-ubiquity quiet splash ---
```

This tells debian-installer to:
- Load preseed answers from `preseed/file=/cdrom/preseed.cfg`
- `auto=true` - enable automatic mode (defer some early questions to allow preseed loading)
- `priority=critical` - only ask questions marked critical; skip all others
- `maybe-ubiquity` - still attempts GUI installer if available, falls back to text d-i

**Partitioning Behavior**:

The preseed adapts based on `INSTALL_DISK` and `PARTITION_STRATEGY` configuration:

- **Partition Mode** (`PARTITION_STRATEGY="force-partition"`, `INSTALL_DISK="/dev/sda5"`):
  - Uses `d-i partman-auto/method string regular` (non-destructive)
  - Debian-installer targets specified partition only
  - Safe for dual-boot systems
  - Respects existing Windows/other OS partitions
  
- **Auto-Detect Mode** (`PARTITION_STRATEGY="auto-detect"`, `INSTALL_DISK=""`) — **Default, Recommended**:
  - Script analyzes disk layout before building ISO
  - Automatically chooses safest strategy (usually partition mode)
  - Embedded in preseed so installer knows partitioning approach
  - Prevents destructive mistakes on multi-partition systems

- **Entire-Disk Mode** (`PARTITION_STRATEGY="force-entire-disk"`, `CONFIRM_ENTIRE_DISK="yes"`):
  - Uses `d-i partman-auto/method string lvm` (auto-partition with LVM)
  - **DESTRUCTIVE**: Erases entire disk and creates new partitions
  - Requires explicit confirmation in `secrets.env`
  - Only use for single-disk systems with no existing data

**Reference**: [Debian Preseed Documentation](https://www.debian.org/releases/stable/amd64/apbs02.en.html)

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

**Note**: et-os-addons (GridTracker, WSJT-X Improved, QSSTV, etc.) is **always included** in every build—no flag needed.

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

### Expert Customization with et-os-addons (`-a` flag)

The `-a` flag integrates [et-os-addons](https://github.com/clifjones/et-os-addons) - a community 
enhancement package that adds powerful FT8 and digital mode capabilities:

**Packages Added:**
- **WSJT-X Improved** - FT8/FT4 with optimized settings for radio operators
- **GridTracker 2** - Real-time propagation and CQ spotting via FT8/FT4
- **SSTV (Slow Scan TV)** - Send/receive images over radio
- **Weather Tools** - Integration with local weather stations
- **Additional Digital Mode Configurations** - Enhanced settings for PSK, RTTY, Olivia, etc.

**Usage:**
```bash
# Build with et-os-addons enabled
sudo ./build-etc-iso.sh -r stable -a

# Combine with other options
sudo ./build-etc-iso.sh -r stable -a -m  # Addons + minimal cache
```

**Size Impact:**
- Standard ISO: ~4.5 GB
- With `-a` flag: ~6.5 GB (adds ~2 GB)
- With `-a -m` flags: ~2.5 GB (minimal, no embedded cache)

**Recommended Use Cases:**
- 🎯 **FT8 Specialists** - Want WSJT-X + GridTracker on every boot
- 🌍 **DXpeditions** - Need propagation monitoring + digital modes
- 📻 **Portable Operators** - Run full-featured digital setup on low-power hardware
- 👥 **Community Builders** - Share a "ready to go" digital modes platform

**Note:** et-os-addons overlay is automatically applied if cached (no configuration needed). 
Drop the cached copy into `cache/et-os-addons-main/` or let the script skip it if unavailable.

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

The build script automatically detects your disk layout and chooses the safest partitioning strategy. This feature was redesigned to handle three common scenarios:

**Partition Strategy Options:**

```bash
# === AUTO-DETECT (Default - Recommended) ===
# Script analyzes disk layout and chooses the best strategy automatically
PARTITION_STRATEGY="auto-detect"    # Analyze and decide
INSTALL_DISK=""                     # Leave empty (auto-detect) or specify disk
CONFIRM_ENTIRE_DISK="no"            # No confirmation needed for auto-detect

# === FORCE PARTITION MODE (Dual-Boot) ===
# Use existing partition - safe for dual-boot systems
PARTITION_STRATEGY="force-partition"
INSTALL_DISK="/dev/sda5"            # Target partition (ends with digit)
CONFIRM_ENTIRE_DISK="no"

# === FORCE ENTIRE-DISK MODE (Dedicated System) ===
# WARNING: DESTRUCTIVE - erases entire disk and creates new partitions with LVM
# Only use for fresh installs with no data on the target disk
PARTITION_STRATEGY="force-entire-disk"
INSTALL_DISK="/dev/sda"             # Entire disk (no partition number)
CONFIRM_ENTIRE_DISK="yes"           # MUST be "yes" to proceed

# === FORCE FREE-SPACE MODE (Windows Dual-Boot with Space) ===
# Create partitions in available free space on Windows partition
PARTITION_STRATEGY="force-free-space"
INSTALL_DISK="/dev/sda"             # Disk with Windows partition + free space
CONFIRM_ENTIRE_DISK="no"            # No confirmation needed
```

**How Auto-Detect Works:**

When `PARTITION_STRATEGY="auto-detect"` (default), the script:

1. **Checks if `INSTALL_DISK` is a specific partition** (e.g., `/dev/sda5`):
   - → Uses **partition mode** (safe for dual-boot)

2. **If disk is blank or only has Linux partitions**:
   - → Uses **entire-disk mode** (LVM auto-partitioning)

3. **If Windows partition detected with free space**:
   - → Uses **free-space mode** (create partitions in gap)

4. **If Windows partition detected with NO free space**:
   - → Requires **CONFIRM_ENTIRE_DISK="yes"** to proceed with entire-disk

**Strategy Behavior Comparison:**

| Strategy | INSTALL_DISK | Behavior | Preseed Config | Best For |
|----------|--------------|----------|----------------|----------|
| **auto-detect** | empty or disk | Analyze and decide | Dynamic based on disk | Most users |
| **partition** | `/dev/sda5` | Use manual partitioning for single partition | `partman-auto/method regular` | Dual-boot (Windows+ETC) |
| **entire-disk** | `/dev/sda` | Auto-partition entire disk with LVM | `partman-auto/method lvm` | Fresh install, single disk |
| **free-space** | `/dev/sda` | Create partitions in available free space | `partman-auto/method regular` + free space | Windows with 50GB+ free |

**Preseed Partitioning Details:**

- **Partition Mode** (`partman-auto/method string regular`):
  - Uses standard ext4 filesystem (no LVM)
  - Requires you to have pre-partitioned the disk
  - Safe for dual-boot: only modifies target partition
  - Swap configured at next partition number (e.g., sda6 if using sda5)

- **Entire-Disk Mode** (`partman-auto/method string lvm`):
  - **DESTRUCTIVE**: Erases all partitions on target disk
  - Uses LVM for flexible partition management
  - Automatic partition sizing with swap
  - Only use if you're certain about target disk

- **Free-Space Mode** (`partman-auto/method string regular`):
  - Creates new partitions in unallocated space
  - Preserves Windows partition
  - Ideal for upgrading Windows system to dual-boot

**Size Calculation:**

The script calculates optimal partition sizes:

```
Available Space = Total Disk Size
Swap Size = MIN(25% of available, MAX(2GB, MIN(4GB)))
EXT4 Size = Remaining space
```

Override calculated sizes (optional):

```bash
SWAP_SIZE_MB="4096"        # Force 4GB swap (in MB)
EXT4_SIZE_MB="51200"       # Force 50GB ext4 (in MB)
```

**Safety Features:**

- ✅ Partition mode is always safe (targets one partition only)
- ✅ Entire-disk mode requires `CONFIRM_ENTIRE_DISK="yes"` to proceed
- ✅ Auto-detect chooses safest option based on current disk layout
- ✅ Script validates partition paths before generating preseed
- ✅ Detailed logging shows detected strategy and proposed partitioning


### VARA License Setup

VARA is commercial software with **two separate products**:

| Product | Cost | Use Case |
|---------|------|----------|
| **VARA FM** | ~$69 | VHF/UHF Winlink via FM repeaters |
| **VARA HF** | ~$69 | HF Winlink for long-distance |

Purchase at [rosmodem.wordpress.com](https://rosmodem.wordpress.com/)

**How License Registration Works**

When you run the VARA installers, they write registration keys to the Wine registry. Rather than trying to script this during ISO build (where Wine doesn't exist yet), we use a **manual registration → backup → restore** workflow:

**Step 1: Manual Registry Editing (One-Time)**

Before creating a Wine backup:
1. Install VARA: `cd ~/add-ons/wine && ./01-install-wine-deps.sh && ./02-install-vara-hf.sh && ./03-install-vara-fm.sh`
2. Open Wine registry editor with direct key access:
   ```bash
   export WINEPREFIX="$HOME/.wine32"
   wine regedit
   ```
3. Navigate to `HKEY_CURRENT_USER → Software → VARA FM` and add/edit:
   - `Callsign` (string): Your callsign
   - `License` (string): Your license key
4. Navigate to `HKEY_CURRENT_USER → Software → VARA` and add/edit (for VARA HF):
   - `Callsign` (string): Your callsign  
   - `License` (string): Your license key
5. Close regedit

**Step 2: Create Wine Backup**

```bash
tar -czf ~/etc-wine-backup-with-vara.tar.gz ~/.wine32/
cp ~/etc-wine-backup-with-vara.tar.gz /path/to/emcomm-tools-customizer/cache/
```

**Step 3: Automatic Restoration on Future Builds**

Place the backup in `cache/` before building. The build script automatically restores it:
- Wine prefix is extracted on first login (deferred from build to avoid hangs)
- VARA registration keys are immediately available
- VARA runs with licenses on first launch

**Why This Approach?**

- ✅ Registry edits are handled correctly by Windows/Wine GUI tools
- ✅ Avoids fragile `.reg` file scripting
- ✅ Wine prefix persists across ISO builds via backup
- ✅ Licenses pre-loaded on every new system
- ✅ Works with ETC's upstream warning: "Don't backup before applications run" (we backup AFTER proper Wine initialization)

### Pat Winlink Aliases

Pat is the Winlink client on ETC. The `emcomm` alias adds a quick-connect shortcut to your standard Pat config:

```bash
pat connect emcomm    # Quick connect to your configured gateway
```

After first boot, run `~/.config/pat/add-emcomm-alias.sh` to add the alias to your Pat config.

### Automatic Backup Restoration

**FULLY AUTOMATED DURING BUILD** ✅

If you place backup files in the `cache/` directory before building, they are **automatically** restored during ISO customization with proper timeout handling:

- `cache/etc-user-backup-*.tar.gz` → User configs extracted to ISO immediately (~30-60 seconds)
  - Includes: `~/.config/emcomm-tools`, `~/.local/share`, documents, desktop settings
  - Extracted directly into `/etc/skel` during build (applied to new users)
  
- `cache/etc-wine-backup-*.tar.gz` → Wine prefix auto-restored on **first login** (deferred from build)
  - VARA registry and prefix data available immediately after first login
  - Deferred to avoid hanging during ISO build (Wine prefix extraction is slow)

**Automation Details:**

- **User backup**: Uses `timeout 300 tar xzf ... --checkpoint=.1000 --checkpoint-action=dot`
  - 300-second timeout prevents hangs on large backups (611MB+)
  - Progress tracking shows extraction status (every 1000 files = one dot)
  - Extracted during build (fast, doesn't block other customizations)

- **Wine backup**: Copied to `~/.etc-backups/` during build
  - `~/.etc-backups/00-restore-wine-backup.sh` auto-runs on first login
  - Restores Wine prefix to `~/.wine32` from backup tarball
  - Runs asynchronously (doesn't block desktop startup)

**How to Use:**

1. Create backups from existing ETC installation:

```bash
# On existing ETC system:
et-user-backup                    # Creates cache/etc-user-backup-*.tar.gz

# If you also want Wine/VARA settings:
et-user-backup --wine            # Includes .wine32 (creates ~600MB backup)

# Copy to your build machine's cache/
scp user@etc-machine:cache/etc-*-backup*.tar.gz ./cache/
```

2. Run build - backups are extracted automatically:

```bash
./build-etc-iso.sh -r stable
# User backup: extracts during build (watch for progress dots)
# Wine backup: copied to ~/.etc-backups/, restores on first login
```

3. Boot the ISO - all user settings + Wine/VARA auto-restored

**What Gets Restored:**

From user backup:

- `~/.config/emcomm-tools/` - ETC configuration (callsign, grid, user.json)
- `~/.local/share/emcomm-tools/` - Maps, tilesets, application data
- `~/.local/share/pat/` - Winlink Pat settings (mailbox passwords, aliases)
- `~/.local/share/WSJT-X/` - WSJT-X settings and logs
- `~/Documents/` - Your documents folder
- `~/.navit/` - Navigation bookmarks and maps
- `~/my-maps/` - Custom map data
- `~/YAAC/` - YAAC configuration

From Wine backup (optional):

- `~/.wine32/` - Entire Wine 32-bit prefix (VARA HF/FM with installed licenses)

**Technical Details:**

- User backup extraction: Uses tar with `--checkpoint` for progress tracking
- Timeout: 300 seconds (5 minutes) - if extraction takes longer, partial restore is used
- Wine backup: Large file (500MB+) is NOT extracted during ISO build; instead it's copied to `~/.etc-backups/` and restored automatically on first user login
- No blocking: Wine extraction deferred to first login avoids "hanging" during ISO build

**Alternative: Manual Restoration (if backups not in cache/)**

If you didn't place backups in the cache/ directory before building, you can restore manually after the OS boots:

```bash
# Copy backup to home directory
cp /path/to/etc-user-backup-*.tar.gz ~

# Restore user configuration only
tar xzf ~/etc-user-backup-*.tar.gz -C ~/

# Or restore with Wine prefix
tar xzf ~/etc-user-backup-*.tar.gz -C ~/   # user config
tar xzf ~/etc-wine-backup-*.tar.gz -C ~/   # Wine prefix
```






### APRS Configuration (Automatic)

**AUTOMATIC DIREWOLF TEMPLATE MODIFICATION** ✅

APRS configuration is automatically applied during ISO build by modifying ETC's direwolf template. This is **completely separate** from Packet/Winlink mode (no conflicts).

**Features:**
- **iGate Mode** - Upload position/weather to APRS-IS internet server (requires login)
- **Smart Beaconing** - Automatic position updates based on movement/time
- **Digipeater Support** - WIDE path relaying for packet radio network
- **ETC Template System** - Respects ETC's `{{ET_*}}` runtime placeholders

**Configuration Variables:**

```bash
# === APRS Configuration ===
APRS_SSID="10"                       # Station SSID (10=iGate, 11-15 for specific roles)
APRS_PASSCODE=""                    # APRS-IS passcode (-1 for RX only)
APRS_SYMBOL="r/"                    # Two-character symbol: r/=portable, a/=digipeater, etc.
APRS_COMMENT="EmComm Tools - ETC"   # Station comment/info string

ENABLE_APRS_IGATE="yes"              # yes/no - enable APRS-IS internet gateway
ENABLE_APRS_BEACON="yes"             # yes/no - enable position beaconing

APRS_SERVER="noam.aprs2.net"        # APRS-IS server (noam=N.America, euro=Europe, etc.)
APRS_BEACON_INTERVAL="30"           # Beacon interval in minutes (smart beaconing)
APRS_BEACON_DISTANCE="1"            # Distance in miles before beacon (movement trigger)

DIREWOLF_ADEVICE="plughw:1,0"       # Audio device for direwolf
DIREWOLF_PTT="CM108"                # PTT method: CM108 (USB audio) or GPIO
```

**How It Works:**

During ISO build, the script:

1. **Modifies direwolf template** at `/opt/emcomm-tools/conf/template.d/packet/direwolf.aprs-digipeater.conf`
2. **Populates user.json** with callsign, grid square, Winlink password
3. **Adds IGSERVER/IGLOGIN** settings when `ENABLE_APRS_IGATE=yes`
4. **Adds PBEACON/SMARTBEACONING** when `ENABLE_APRS_BEACON=yes`
5. **Adds DIGIPEAT configuration** for WIDE path support

**Template Preservation:**

All template modifications preserve ETC's `{{ET_*}}` placeholders. This means:
- Users can still override settings at runtime via `et-mode`
- Selecting different mode (e.g., switching to Packet) doesn't break configuration
- Updates to ETC templates don't conflict with our customizations

**Symbol Codes:**

Common APRS symbols (first character / second character):

```
Primary/Overlay:
a/ = APRS/Beacon, b/ = Buoy, c/ = Cloud, d/ = Digipeater
e/ = Eyeball, f/ = Fire, g/ = Glider, h/ = Hospital
i/ = Interstate, j/ = Jeep, k/ = Kenwood, l/ = Lighthouse
m/ = Mobile, n/ = Node, o/ = OVEN, p/ = Police
q/ = Query, r/ = RV, s/ = Shuttle, t/ = Truck
u/ = User, v/ = Van, w/ = Water, x/ = X-APRS
y/ = Yagi, z/ = Zero

r/ = Portable = most common for field stations
a/ = Digipeater = recommended for relay stations
```

**Server Choices:**

```
noam.aprs2.net   = North America (default)
euro.aprs2.net   = Europe
asia.aprs2.net   = Asia
aunz.aprs2.net   = Australia/New Zealand
```

**Post-Install Testing:**

After building and booting:

```bash
# Start direwolf in APRS mode
et-mode aprs

# Watch direwolf logs
tail -f ~/.etc-cache/direwolf.log

# Verify APRS-IS gateway connection (watch for "Connected to")
journalctl -u direwolf -f
```

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

## Community Tools & Extensions

Several community projects build on ETC. Here's how they relate to this customizer:

### For Hardware-Specific Radio CAT Configuration

#### **ETC5_NozzleMods** - Post-Install Radio Support
- **Author**: CowboyPilot | **Status**: Active (v1.2)
- **How It Works**: Clones to `~/NozzleMods/`, adds `nozzle-menu` interactive launcher
- **Real Value**: Hardware-specific CAT control configuration that's not in upstream
  - **AIOC** (All-In-One-Cable): Three DireWolf profiles (Simple TNC, Packet Digipeater, APRS Digipeater)
  - **Yaesu FT-710**: Full CAT support with udev rules and device symlinks (`/dev/et-cat`, `/dev/et-audio`)
  - **Xiegu G90**: DigiRig PTT configuration (CAT vs RTS modes)
  - System tools: Fix APT sources, VarAC V13 .NET fixes
- **About VARA**: NozzleMods does NOT provide VARA (upstream ETC R5 already has `~/add-ons/wine/` scripts for VARA HF/FM). NozzleMods wraps them in a menu and adds port management.
- **Installation**: `curl -fsSL https://raw.githubusercontent.com/CowboyPilot/ETC5_NozzleMods/main/install.sh | bash`
- **Integration Path**: Post-install only—requires running system with X11/GNOME for menu. Can't pre-stage in ISO.
- **URL**: https://github.com/CowboyPilot/ETC5_NozzleMods

### For Extended Radio Modes (FT8, SSTV, etc.)

#### **et-os-addons** - ETC Enhancements via Overlay
- **Author**: clifjones | **Status**: Active
- **How It Works**: Two methods:
  1. **Build-time**: Replace ETC tarball URL with et-os-addons during ISO creation
  2. **Post-install**: Clone and run on existing ETC system
- **What It Adds** (via overlay pattern):
  - **WSJT-X Improved** (FT8/FT4/MSK144) - NOT in upstream ETC
  - **GridTracker 2** - Mapping integration
  - **JS8Spotter** - Spot tracking
  - **QSSTV + Cheese** - SSTV/webcam support
  - **xygrib + Saildocs** - Weather maps
  - **et-launcher** - Rust UI wrapper to reduce CLI usage
  - **Enhanced et-user-backup** - Custom backup directories
- **Integration Path**: Could integrate into this customizer by:
  - Adding `-a` or `--addons` flag to include their overlay during build
  - OR: document as alternative build path for users wanting FT8
- **Licensing Note**: Requires building your own ISO (no pre-built images distributed)
- **URL**: https://github.com/clifjones/et-os-addons

### For Organization-Specific Variants

#### **ETC-MAG** - Regional/Organizational Build
- **Author**: kf0che
- **Status**: Maintained but specific to MAGNET organization
- **How It Works**: Full variant with ETC submodule + custom overlay scripts
- **Value**: Reference example for building org-specific ETC builds
- **Integration Path**: Documentation only—too specialized for general customizer
- **URL**: https://github.com/kf0che/ETC-MAG

### Operational Workflows (Separate from ISO Building)

#### **emcomm-print** - Message Printing Utility
- **Author**: ekakela
- **Platform**: Windows (Python-based)
- **What It Does**: Monitors folder → prints to thermal receipt printer → archives messages
- **Best For**: Emergency exercises where operators need physical message distribution
- **Integration Path**: None (different platform, different purpose). Link in docs for interested users.
- **URL**: https://github.com/ekakela/emcomm-print

---

### Integration Recommendations

#### NozzleMods (Hardware CAT Config)
**Approach**: Document + provide post-install hook  
**Why Separate**: Requires running X11 environment with Wine. Must happen after system boots.  
**Action Items**:
- Create `/post-install-hooks/nozzlemods-template.sh` for users to customize and run
- Document that if you have AIOC/FT-710/G90, run this post-install
- Link directly to NozzleMods GitHub

#### et-os-addons (Extended Modes)
**Approach**: Document as alternative build OR optional enhancement flag  
**Why Separate**: Different overlay pattern. Could be integrated but adds ~2GB to ISO.  
**Decision**:
- **Option A** (Simpler): Keep emcomm-tools-customizer as "base ETC customizer"  
  Users who want FT8 use et-os-addons instead
- **Option B** (More Work): Add `-a` flag to include their overlay at build time  
  Would require cloning their repo during build, extracting overlay, merging pattern

#### emcomm-print
**Approach**: Link in README for users with thermal printer workflows  
**Integration**: None—different platform

---

### Recommended User Workflows

**Scenario 1: Basic ETC with custom WiFi/callsign**
```
→ Use emcomm-tools-customizer
→ Boot, install ISO
→ Done (or run et-vara-hf/et-vara-fm from add-ons if you want VARA)
```

**Scenario 2: ETC + AIOC or FT-710 radio**
```
→ Use emcomm-tools-customizer
→ Boot, install ISO
→ Run NozzleMods: curl https://raw... | bash
→ nozzle-menu → R) Radio Configuration → select your radio
```

**Scenario 3: ETC + FT8/GridTracker**
```
→ Use et-os-addons instead of emcomm-tools-customizer
→ Follow et-os-addons build instructions (replaces ETC tarball)
→ ISO will have WSJT-X Improved, GridTracker 2
```

**Scenario 4: ETC + everything (custom config + AIOC + FT8)**
```
→ Use et-os-addons for FT8/GridTracker
→ Document custom build steps for WiFi/callsign (outside upstream)
→ After install: Run NozzleMods for AIOC CAT config
```

---

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
