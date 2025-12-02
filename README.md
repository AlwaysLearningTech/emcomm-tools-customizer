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
- ✅ Desktop preferences (dark mode, scaling)
- ✅ VARA FM/HF license `.reg` files + import script (run post-install after VARA installation)
- ✅ Disabled accessibility features (screen reader, on-screen keyboard)
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
| `-m` | Minimal build (exclude cache files, saves ~4GB) |
| `-d` | Dry-run mode |
| `-v` | Verbose mode |
| `-D` | Debug mode (show DEBUG log messages) |
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
ENABLE_AUTOLOGIN="no"          # "yes" or "no" - default is NO

# === System ===
MACHINE_NAME=""                 # Hostname (defaults to ETC-{CALLSIGN})

# === Desktop Preferences ===
DESKTOP_COLOR_SCHEME="prefer-dark"  # prefer-dark or prefer-light
DESKTOP_SCALING_FACTOR="1.0"        # 1.0, 1.25, 1.5, or 2.0
DISABLE_ACCESSIBILITY="yes"         # Disable screen reader, on-screen keyboard
DISABLE_AUTO_BRIGHTNESS="yes"       # Disable automatic backlight

# === WiFi Networks ===
# Add as many networks as needed with unique suffixes
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
