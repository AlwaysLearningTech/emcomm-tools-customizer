# EmComm Tools Customizer

Customizes EmComm Tools Community (ETC) images using xorriso/squashfs — no Cubic,
no GUI. Applies the same customizations to an **already-installed** system too.

> **v2.0.0 is a breaking release.** Installer automation is gone: a built ISO now
> boots to the standard Ubuntu / ETC installer walkthrough and you choose the
> disk and partition layout yourself. The `dd` USB writer is gone as well —
> nothing in this repository writes to a block device. The Anytone D578UV CAT
> control was rewritten because it never worked.
> See [CHANGELOG.md](CHANGELOG.md) and [UPGRADING.md](UPGRADING.md).

## Scripts

| Script | What it does | Touches disks? |
|---|---|---|
| `apply-to-live-system.sh` | Applies APRS, radio and addon config to a running ETC system. Backs up everything, `--dry-run` and `--uninstall` supported. | No |
| `build-etc-iso.sh` | Builds a customized ISO. Boots to the normal installer. | No |
| `build-hamlib-anytone.sh` | Builds the CowboyPilot Hamlib fork for AnyTone D578UVIII CAT (model 37001). `--revert` restores ETC's Hamlib. | No |
| `build-direwolf-gpsd.sh` | Rebuilds Dire Wolf with `ENABLE_GPSD` for GPS-tracked beaconing. `--revert` supported. | No |

Customizations live in `lib/` and operate on `$ET_ROOT`, so the ISO build and the
live-system path run **the same code** and cannot drift apart.

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
- ✅ **VS Code workspace setup** (standard project location included in et-user-backup)
- ✅ **Automatic user config restoration** (from `etc-user-backup-*.tar.gz` if present)
- ✅ **APRS configuration** (receive-only iGate, position beacon, digipeater)
- ✅ **Ham radio CAT control** (Anytone AT-D578UVIII via DigiRig, Hamlib model 37001)
- ✅ **Live-system apply** — same customizations without rebuilding an ISO
- ✅ **Optional et-os-addons features** (individually configurable):
  - VR-N76 radio config, GridTracker, WSJT-X Improved, QSSTV, XYGrib, Kiwix, JS8Spotter, NetControl, WiFi hotspot, user backup tool
  - Control via `ENABLE_ETOSADDONS_*` variables in `secrets.env` (all enabled by default)
- ✅ Git configuration
- ✅ Embedded cache files for faster rebuilds (use `-m` for minimal)

### What's NOT Changed

This customizer **respects upstream ETC architecture**. We:

- Keep ETC's runtime template system (et-direwolf, et-yaac, etc.)
- Modify templates in-place, keeping `{{ET_*}}` placeholders
- Don't change package selections or install additional software
- Don't pre-install VARA or Wine prefix (these require a desktop session post-install)

## Release Status: v2.0.0

**Breaking release.** Installer automation and the `dd` USB writer were removed,
and the Anytone D578UV CAT control was rewritten because it never worked. Read
[CHANGELOG.md](CHANGELOG.md) before upgrading from v1.

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
- **Ham radio CAT control**: Anytone AT-D578UVIII with DigiRig Mobile
  - Hamlib model 37001 via the CowboyPilot/Hamlib AnyTone backend
    (`./build-hamlib-anytone.sh` — stock Hamlib 4.5 has no AnyTone backend)
  - Two profiles: PTT-only (`commode=0`) and full COM mode (`commode=1`)
  - Uses ETC's existing udev rules and rigctld unit — no patching
  - udev rules for /dev/et-cat symlink (CP2102/CH340/PL2303/FTDI)
  - Users can select different radio via `et-radio` after boot
- **D578 CAT Control**: DigiRig Mobile configuration for CAT control (et-mode packet/Winlink compatible)
- **User config**: `~/.config/emcomm-tools/user.json` pre-populated with callsign, grid, Winlink password
- **Desktop settings**: Dark mode, scaling, accessibility, display, power management, timezone all applied
- **Git config**: User name/email configured
- **VARA license setup**: Pre-register via Wine registry, create backup, auto-restore on builds
- **VS Code workspace**: Pre-configured workspace with Projects directory in ~/.config/emcomm-tools/
- **Additional packages**: Development tools (VS Code, git, nodejs, npm, CHIRP via pipx) installable via configuration
- **Cache system**: Downloaded ISOs cached for faster rebuilds
- **Standard installer walkthrough**: the ISO boots to the normal Ubuntu / ETC
  installer. You pick the disk and partition layout yourself. No preseed, no
  automated partitioning, and nothing here writes to a block device.
- **Anytone AT-D578UVIII radio**: two profiles in the et-radio menu, Hamlib model
  37001 (v1 used `301`, which does not exist in Hamlib)
- **Release info persistence**: Custom release name (`ETC_R5_FINAL (CUSTOMIZED)`) persists after installation
  - Uses dpkg conffile MD5 update to prevent installer from reverting `/etc/lsb-release`
  - `et-system-info release` correctly shows custom build name

### Optional et-os-addons Features

The `et-os-addons` repository provides optional application launchers and configurations. These are **enabled by default** but can be disabled via `ENABLE_ETOSADDONS_*` variables in `secrets.env`:

| Feature | Variable | Description |
|---------|----------|-------------|
| VR-N76 Radio | `ENABLE_ETOSADDONS_VR_N76` | VR-N76 old radio utility and preset config |
| QSSTV | `ENABLE_ETOSADDONS_QSSTV` | QSSTV slow-scan TV launcher and config template |
| JS8 Spotter | `ENABLE_ETOSADDONS_JS8SPOTTER` | JS8Call spotting utility and launcher |
| NetControl | `ENABLE_ETOSADDONS_NETCONTROL` | Network control utility with launcher |
| WiFi Hotspot | `ENABLE_ETOSADDONS_HOTSPOT` | WiFi hotspot launcher utility |
| User Backup | `ENABLE_ETOSADDONS_USERBACKUP` | User backup/restore manager utility |
| Kiwix | `ENABLE_ETOSADDONS_KIWIX` | Offline content browser with desktop integration |
| VGC VR-N76 Radio | Always enabled | VGC VR-N76 radio config for `et-radio` menu |

**To disable a feature**, set the variable to `"no"` in `secrets.env`:
```bash
ENABLE_ETOSADDONS_QSSTV="no"        # Disable QSSTV
```

All features default to `"yes"` and are integrated explicitly into the build process with no overwrites.

## Installing a Built ISO

**The ISO does not install itself.** It boots to the standard Ubuntu / EmComm
Tools installer walkthrough, and you choose the target disk and partition layout
yourself, every time.

This changed in v2.0.0. v1 shipped a preseed that drove the installer unattended
and partitioned automatically — see [CHANGELOG.md](CHANGELOG.md) for exactly what
it did and why it was removed.

### Steps

1. **Put the ISO on a USB stick.** No script here writes to a block device.
   - **Ventoy** — safest, since it is a plain file copy onto an already-prepared
     stick with no device path to get wrong:
     `sudo ./build-etc-iso.sh --ventoy /media/$USER/Ventoy`
   - **A GUI writer** — balenaEtcher, GNOME Disks, Rufus. They show the target
     drive by name and size before writing.
   - **`dd`**, run by you, after checking the device twice:
     ```bash
     lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINT
     sudo dd if=output/<iso> of=/dev/sdX bs=4M status=progress conv=fsync
     ```
2. **Boot it** and run the installer as normal.
3. **Apply customizations** after first boot:
   ```bash
   sudo ./apply-to-live-system.sh
   ```

See [UPGRADING.md](UPGRADING.md) for the full upgrade path, including tracking
ETC beta releases.


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

# Build from the newest stable release
sudo ./build-etc-iso.sh -r stable

# Output: output/<name>.iso
# Put it on a USB stick yourself (Ventoy / balenaEtcher / dd) and boot it.
```

### Already running ETC? Skip the ISO entirely

To apply these customizations to an installed system — no Cubic, no rebuild, no
disk operations:

```bash
sudo ./apply-to-live-system.sh --dry-run   # preview
sudo ./apply-to-live-system.sh             # apply
sudo ./apply-to-live-system.sh --uninstall # undo
```

See [UPGRADING.md](UPGRADING.md).

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
# List available releases and tags from GitHub (betas included)
./build-etc-iso.sh -l

# Build from the newest stable release
sudo ./build-etc-iso.sh -r stable

# Build from the newest tag (development / beta)
sudo ./build-etc-iso.sh -r latest

# Build a specific tag
sudo ./build-etc-iso.sh -r tag -t emcomm-tools-os-community-20251113-r5-build17

# Minimal build (smaller ISO, no embedded cache files)
sudo ./build-etc-iso.sh -r stable -m

# Build and copy to a mounted Ventoy stick
sudo ./build-etc-iso.sh -r stable --ventoy /media/$USER/Ventoy
```

### Option Reference

| Option | Description |
|--------|-------------|
| `-r <stable\|latest\|tag>` | Release mode |
| `-t <tag>` | Specific tag name (required with `-r tag`) |
| `-l` | List available releases and tags |
| `--ventoy <mount-path>` | Copy ISO + helper files to a mounted Ventoy USB (file copy only) |
| `-m` | Minimal build (exclude cache files, saves ~4GB) |
| `-d` | Debug mode (show DEBUG log messages) |
| `-k` | Keep the work directory for debugging |
| `-v` | Verbose mode (bash -x tracing) |
| `-h` | Show help |

**Note**: et-os-addons features are controlled by `ENABLE_ETOSADDONS_*` in
`secrets.env`. Most install only a launcher and depend on an application ETC does
not ship — the template says which.

### Getting the ISO onto a USB stick

Removed in v2.0.0: `--write-to`, which `dd`'d the ISO to a block device and, used
bare, auto-detected which device to write. **No script in this repository writes
to a block device any more.** Use whichever tool you trust:

- **Ventoy** — `--ventoy` copies the ISO onto an already-prepared stick. A plain
  file copy to a mounted filesystem, so there is no device path to get wrong.
- **A GUI writer** — balenaEtcher, GNOME Disks, Rufus. They show the target drive
  by name and size before writing.
- **`dd`** — run it yourself, and check the device twice:
  ```bash
  lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINT
  sudo dd if=output/<iso> of=/dev/sdX bs=4M status=progress conv=fsync
  ```

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

### Customizing et-os-addons Features

Optional features from [et-os-addons](https://github.com/clifjones/et-os-addons) are integrated into every build. Control individual features via `ENABLE_ETOSADDONS_*` variables in `secrets.env`.

**What's Available:**
- **GridTracker 2** - Real-time FT8/FT4 propagation and CQ spotting
- **WSJT-X Improved** - FT8/FT4 with optimized settings
- **QSSTV** - Slow-scan TV transmission and reception  
- **XYGrib** - Weather routing and GRIB file downloads
- **Kiwix** - Offline Wikipedia and documentation archives
- **JS8Call Spotter** - JS8Call network spotting integration
- **NetControl** - Network control and monitoring utility
- **WiFi Hotspot** - Quick WiFi AP sharing from command line
- **User Backup/Restore** - Backup and restore ETC user settings
- **VR-N76 Radio Config** - Support for VGC VR-N76 radio (always included)

**Configuration:**
Features default to enabled. To disable specific features, edit `secrets.env`:
```bash
ENABLE_ETOSADDONS_GRIDTRACKER="yes"  # Keep GridTracker
ENABLE_ETOSADDONS_QSSTV="no"         # Exclude QSSTV
ENABLE_ETOSADDONS_KIWIX="no"         # Exclude offline Wikipedia
ENABLE_ETOSADDONS_NETCONTROL="no"    # Exclude NetControl
```

Disabled features won't be installed, saving build time and ISO size. See the [Optional et-os-addons Features](#optional-et-os-addons-features) table above for all available variables and descriptions.

**Note:** et-os-addons features require the source in `cache/et-os-addons-main/`. Clone it with:
```bash
git clone https://github.com/clifjones/et-os-addons.git cache/et-os-addons-main
```
If not present, the build continues normally with features disabled.

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
APRS_PASSCODE=""               # Empty = computed from CALLSIGN
APRS_SYMBOL="digi"             # Dire Wolf symbol name or 2-char code
APRS_COMMENT="EmComm iGate"    # Beacon comment

# APRS Beacon (position beaconing)
ENABLE_APRS_BEACON="yes"       # Enable position beaconing
APRS_BEACON_MODE="fixed"       # fixed | gps (gps needs build-direwolf-gpsd.sh)
APRS_LAT=""                    # Empty = center of GRID_SQUARE (~3km)
APRS_LON=""
APRS_BEACON_INTERVAL="30:00"   # "30:00"=30 min. A bare "30" means 30 SECONDS.
APRS_BEACON_VIA="WIDE1-1"      # Digipeater path
APRS_BEACON_POWER="10"         # PHG: Power in watts
APRS_BEACON_HEIGHT="20"        # PHG: Antenna height (feet)
APRS_BEACON_GAIN="3"           # PHG: Antenna gain (dBi)

# APRS iGate (RF to Internet gateway, receive-only)
ENABLE_APRS_IGATE="yes"        # Enable iGate
APRS_SERVER="noam.aprs2.net"   # APRS-IS server

# === Anytone AT-D578UVIII ===
ENABLE_ANYTONE_D578="yes"      # Write the D578UVIII radio profiles
ANYTONE_DEFAULT_MODE="ptt"     # ptt (commode=0) | com (commode=1)

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

### Installation Modes

**Removed in v2.0.0.** v1 documented four partition strategies here
(`auto-detect`, `force-partition`, `force-entire-disk`, `force-free-space`)
driven by `PARTITION_STRATEGY`, `INSTALL_DISK`, `SWAP_SIZE_MB`, `EXT4_SIZE_MB`
and `CONFIRM_ENTIRE_DISK`.

All of it is gone. The generated preseed set
`partman-auto/choose_recipe select atomic` together with
`partman/confirm_write_new_label boolean true` — the whole-disk recipe plus a
pre-answered "yes, destroy the partition table" — against an auto-detected disk,
while its own comments conceded that Ubiquity "ignores most partman preseeds".
The result was unpredictable and destroyed a partition in practice.

**You now choose the disk and the partition layout in the installer**, the same
way you would with stock Ubuntu or stock ETC. Those five variables are ignored if
left in an old `secrets.env`.

See [CHANGELOG.md](CHANGELOG.md) for the full detail and [UPGRADING.md](UPGRADING.md)
for migration.

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

### VS Code Workspace

A pre-configured VS Code workspace is created at `~/.config/emcomm-tools/emcomm-tools.code-workspace`:

**Features:**
- **Projects directory**: `~/.config/emcomm-tools/Projects/` - standard location for all repos and development
- **Workspace file**: Open in VS Code via `File → Open Workspace from File` or `code ~/.config/emcomm-tools/emcomm-tools.code-workspace`
- **Automatic backup**: All files in Projects are included in et-user-backup
- **Recommended extensions**: Python, Pylance, C++, Prettier, GitLens, Remote Explorer

**Using the workspace:**

1. **Clone repos or create projects** in `~/.config/emcomm-tools/Projects/`
   ```bash
   cd ~/.config/emcomm-tools/Projects
   git clone https://github.com/user/repo.git
   ```

2. **Backup your projects** for next rebuild:
   ```bash
   tar -czf ~/etc-user-backup-$(date +%Y%m%d).tar.gz ~/.config/
   cp ~/etc-user-backup-*.tar.gz /path/to/emcomm-tools-customizer/cache/
   ```

3. **Next ISO build** automatically restores your workspace and projects on first login

**Project organization suggestion:**
```
Projects/
├── ham-radio/          # Ham radio related projects
├── emcomm/             # EmComm Tools customizations
├── scripts/            # Utility scripts  
└── personal/           # Personal projects
```

### Additional Development Packages

The build automatically installs:
- **VS Code** - editor
- **Node.js & npm** - JavaScript development
- **git** - version control
- **CHIRP** - Radio programming software (installed via pipx with official wheel from https://archive.chirpmyradio.com/)

Additional packages can be configured in `secrets.env` via `ADDITIONAL_PACKAGES` variable.

**Note on CHIRP**: Ubuntu 22.10 repos have outdated CHIRP packages. The build uses the official installation method (pipx with downloaded wheel) as documented at https://chirpmyradio.com/projects/chirp/wiki/ChirpOnLinux.

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
- **Position beacon** - fixed (from grid square or explicit lat/lon), or GPS-tracked
  once Dire Wolf is rebuilt with gpsd
- **Digipeater Support** - WIDE path relaying for packet radio network
- **ETC Template System** - Respects ETC's `{{ET_*}}` runtime placeholders

Two constraints the generator handles, both of which v1 got wrong:

- Dire Wolf's config parser is **line-oriented** — no backslash continuations.
  Every directive is emitted on one line.
- `every=30` means 30 **seconds**. Use `30:00` for 30 minutes.

**Configuration Variables:** see [secrets.env.template](secrets.env.template),
which is the authoritative list.

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
