# EmComm Tools OS Customizer

**Automated ISO builder for EmComm Tools Community (ETC) with personalized WiFi and radio configurations**

This project automates the process of creating a customized Ubuntu-based ISO for emergency communications. It takes the excellent upstream **EmComm Tools Community** system and adds automated personalization: WiFi networks, callsign, radio settings, and development tools—all baked in at ISO build time.

> **⚠️ IMPORTANT: x64 Architecture Only**  
> This project **only supports x64/AMD64 systems**. ARM architectures (Apple Silicon, Raspberry Pi) are **NOT supported**.

---

## What This Project Does

**Upstream (EmComm Tools Community)** provides:
- Ubuntu 22.10 base OS with pre-installed ham radio software
- CHIRP, dmrconfig, direwolf, Pat/Winlink, YAAC, flrig
- Offline documentation, emergency resources
- Designed as **standalone system** (works offline, no internet required)

**This Customizer adds:**
- ✅ Automated WiFi configuration (baked into ISO at build time)
- ✅ Automated callsign and APRS configuration (beacon + iGate)
- ✅ Automated git user configuration
- ✅ Desktop environment preferences (dark mode, scaling)
- ✅ **Anytone D578UV CAT support** (hamlib rigctld for frequency control)
- ✅ APRS beacon + iGate configuration (position broadcasting and internet relay)
- ✅ Backup/restore automation for VARA FM and user settings
- ✅ Fully reproducible builds from command line

**This customizer does NOT change:**
- Upstream ETC philosophy (standalone, offline-capable)
- Any upstream applications or functionality
- Deployment method (still uses Cubic, still requires GUI to start build)

---

## Quick Start - Build Your First ISO

### Prerequisites

- **x64/AMD64 Ubuntu system** (22.10) for building
- **~8GB disk space** for build files and ISO
- **Internet connection** (downloads ~3.6GB base ISO once, then cached)

### Step 1: Setup (Terminal)

```bash
git clone https://github.com/AlwaysLearningTech/emcomm-tools-customizer.git
cd emcomm-tools-customizer

cp secrets.env.template secrets.env
# Edit secrets.env with your values:
#   USER_USERNAME = your Linux username
#   USER_FULLNAME = Your Name
#   USER_PASSWORD = your password
#   CALLSIGN = your ham radio callsign
#   WIFI_SSID_PRIMARY, WIFI_PASSWORD_PRIMARY = your home WiFi
nano secrets.env
```

### Step 2: Build (Terminal - Fully Automated)

```bash
./build-etc-iso.sh -r stable
# Automatically:
#   ✅ Downloads ETC release from GitHub
#   ✅ Validates/downloads Ubuntu ISO (cached in ~/etc-customizer-backups/)
#   ✅ Prepares all files
#   ✅ Returns control to terminal
```

### Step 3: Create ISO (Cubic GUI - 3 Clicks)

```bash
sudo cubic
# In Cubic:
#   1. File → New Project
#   2. Select project directory (shown in Step 2 output)
#   3. Click to build
#   → Scripts run AUTOMATICALLY (no manual steps)
#   → ISO created when done
```

### Step 4: Deploy (Terminal)

```bash
# Copy ISO to Ventoy or other boot media
./copy-iso-to-ventoy.sh ~/etc-builds/*/emcomm-tools-os-community-*.iso

# Or manually to any boot media
cp ~/etc-builds/*/emcomm-tools-os-community-*.iso /media/ventoy/
sync
```

**Done!** Boot the ISO and your customizations are active.

---

## What Runs Where

| Component | Where | Automated? | Notes |
|-----------|-------|-----------|-------|
| `build-etc-iso.sh` | Terminal | ✅ Yes | You run once, it does everything |
| Download ETC release | Terminal script | ✅ Yes | Automatic |
| Download Ubuntu ISO | Terminal script | ✅ Yes | Cached to `/home/{USER}/etc-customizer-backups/` |
| Detect backups | Terminal script | ✅ Yes | Auto-looks in `etc-customizer-backups/` |
| Cubic GUI launch | Your action | ⚠️ Manual | 3 clicks to start |
| All `cubic/*.sh` scripts | Cubic chroot | ✅ Yes | Cubic runs all of them |
| Copy ISO to USB | Terminal script | ✅ Yes | You run the helper script |

**Bottom line:** Only Cubic GUI requires manual intervention. Everything else is hands-off.

---

## Build System Architecture

### Three Execution Stages

```
Stage 1: PREPARATION (Terminal)
├─ You run: ./build-etc-iso.sh -r stable
├─ Script: Downloads ETC release
├─ Script: Downloads/validates Ubuntu ISO
├─ Script: Detects backups automatically
├─ Script: Prepares Cubic project directory
└─ Script: Returns to terminal

        ↓

Stage 2: CUBIC BUILD (GUI → Chroot)
├─ You do: sudo cubic (GUI opens)
├─ You do: 3 clicks (File → New Project → Build)
├─ Cubic: Extracts Ubuntu ISO
├─ Cubic: Chroots into environment
├─ Cubic RUNS AUTOMATICALLY:
│  ├─ install-dev-tools.sh
│  ├─ install-ham-tools.sh
│  ├─ configure-wifi.sh (reads secrets.env)
│  ├─ configure-aprs-apps.sh (reads secrets.env)
│  ├─ configure-radio-defaults.sh
│  ├─ restore-backups.sh (finds backups auto)
│  ├─ setup-desktop-defaults.sh (reads secrets.env)
│  └─ finalize-build.sh
├─ Cubic: Creates custom ISO
└─ Cubic: Returns to terminal

        ↓

Stage 3: DEPLOYMENT (Your System)
├─ You: Boot ISO on hardware
├─ System: All customizations active
├─ You: Optionally run post-install/restore-backups-from-skel.sh
└─ Backups: Available for next ISO build
```

---

## File Structure

```
emcomm-tools-customizer/
├── cubic/                          # Scripts run during ISO build
│   ├── install-dev-tools.sh       # VS Code, git, uv, build essentials
│   ├── install-ham-tools.sh       # CHIRP, dmrconfig, hamlib, flrig, LibreOffice
│   ├── configure-wifi.sh          # WiFi networks from secrets.env
│   ├── configure-aprs-apps.sh     # direwolf, YAAC configuration
│   ├── configure-radio-defaults.sh # Anytone D578UV + hamlib setup
│   ├── setup-desktop-defaults.sh  # Dark mode, scaling, accessibility
│   ├── restore-backups.sh         # VARA FM and user settings backup
│   └── finalize-build.sh          # Cleanup and manifest
├── post-install/                   # Scripts for deployed system
│   └── restore-backups-from-skel.sh # One-time: restore backups for next build
├── secrets.env.template            # Configuration template (safe to commit)
├── secrets.env                     # Your secrets (gitignored - never committed)
├── build-etc-iso.sh               # Main orchestration (terminal)
├── copy-iso-to-ventoy.sh          # Helper to copy ISO to boot media
├── README.md                       # This file
└── backups/                        # (Directory reference - files stored externally)
    └── README.md                   # Backup strategy documentation
```

---

## Configuration: secrets.env

All customization comes from a single file: **`secrets.env`**

Copy the template and edit with your values:

```bash
cp secrets.env.template secrets.env
nano secrets.env
```

The template contains all available options with descriptions:
- User account (name, username, password, email)
- System settings (callsign, hostname)
- Desktop environment (color scheme, scaling)
- WiFi networks (add as many as needed)
- APRS beacon configuration
- Direwolf audio device settings
- Git configuration

**All settings are baked into the ISO at build time.** No config files to edit after deployment.

---

## Radio Hardware: Anytone D578UV + Digirig Mobile

This customizer adds **CAT (Computer-Aided Transceiver) support** for the **Anytone D578UV** mobile radio using **hamlib + rigctld**.

### What This Means

- **hamlib rigctld daemon** starts automatically
- Apps (fldigi, YAAC) can control frequency/mode via XML-RPC
- No flrig GUI required (flrig available as fallback only)
- Uses `/dev/ttyUSB1` for CAT commands
- Uses `/dev/ttyUSB0` for audio

### How It Works

1. Digirig Mobile USB-C connected to radio
2. Creates two serial ports:
   - `/dev/ttyUSB0` = Audio codec
   - `/dev/ttyUSB1` = CAT control
3. rigctld starts on `localhost:12345`
4. Apps connect via XML-RPC
5. Change frequency in app → radio follows

### Configuration

Done automatically in `cubic/configure-radio-defaults.sh`:
- Hamlib rig ID 242 (Anytone D578UV)
- Baud rate: 9600
- PTT via RTS pin on `/dev/ttyUSB1`

No manual setup needed.

### Supported Radios

**With CAT Control:**
- ✅ Anytone D578UV (mobile) — **Fully supported by this customizer**

**Without CAT (upstream only):**
- Audio/PTT only: Anytone D878UV, BTech UV-Pro, others
- Use upstream et-radio configuration

---

## APRS: Beacon Mode (Position Broadcasting)

The customizer configures **direwolf** to broadcast your position via APRS RF at regular intervals.

### Beacon vs. iGate

- **Beacon** (Position Broadcast): You transmit your GPS location every N seconds
  - Requires: GPS device connected
  - Use: Mobile operations, field deployments
  - Default interval: 300 seconds (5 minutes)

- **iGate** (Internet Gateway): Relay APRS packets between RF and internet
  - Requires: Internet connection + hamradio network account
  - Use: Home stations, EOC relay
  - **Enabled by this customizer** (upstream provides infrastructure, we enable it)

### Beacon Configuration

Edit your `secrets.env` to enable and configure beacon:

```bash
ENABLE_APRS_BEACON="no"             # Set to "yes" to enable
APRS_BEACON_INTERVAL="300"          # Seconds between beacons
APRS_SSID="0"                       # Station ID (0=base, 1-15=secondary)
APRS_PASSCODE="-1"                  # Get from https://apps.magicbug.co.uk/passcode/ or use "-1" for RX-only
```

**APRS SSID Reference** (common values):
- `0` = Primary station (default for fixed location or first mobile)
- `1` = Alternate mobile (second vehicle, alternate callsign)
- `2` = Generic additional station, digi, mobile, wx, etc
- `3` = Generic additional station, digi, mobile, wx, etc
- `4` = Generic additional station, digi, mobile, wx, etc
- `5` = Other networks (D-Star, iPhones, Androids, Blackberry's, etc)
- `6` = Special activity, Satellite ops, camping or 6 meters, etc
- `7` = Walkie talkies, HT's or other human portable
- `8` = Boats, sailboats, RV's or second main mobile
- `9` = Primary mobile (usually message capable)
- `10` = Internet, iGates, EchoLink, Winlink, AVRS, APRN, etc
- `11` = Balloons, aircraft, spacecraft, etc
- `12` = APRStt, DTMF, RFID, devices, one-way trackers, etc
- `13` = Weather stations
- `14` = Truckers or generally full time drivers
- `15` = Generic name (for gates, relays)

See `secrets.env.template` for all available beacon options and descriptions.

**Beacon defaults to 300 seconds (5 min)** for mobile operations. Adjust based on your needs:
- 60-120s: High-speed mobile (car, bike)
- 300s: Normal mobile
- 600s+: Stationary/slow

### Beacon Power & Antenna Configuration

The customizer includes additional beacon parameters for fine-tuning RF coverage:

```bash
APRS_BEACON_POWER="10"              # Transmit power code (0-9)
APRS_BEACON_HEIGHT="20"             # Antenna height above ground in feet
APRS_BEACON_GAIN="3"                # Antenna gain code (0-9)
```

**Transmit Power Code** (0-9):
- `0` = 1 watt
- `1` = 2 watts
- `2` = 5 watts
- `3` = 10 watts
- `4` = 20 watts
- `5` = 50 watts
- `6` = 100 watts
- `7` = 250 watts
- `8` = 500 watts
- `9` = 1000+ watts (1 kilowatt)

**Antenna Height** (feet above ground level - AGL):
- Typical values: 10-100 feet
- Higher antenna = longer RF range
- Used for APRS coverage calculation and network awareness

**Antenna Gain Code** (0-9):
- `0` = Omnidirectional (0 dBi)
- `1` = 3 dBi gain
- `2` = 6 dBi gain
- `3` = 9 dBi gain
- `4-9` = Higher directional gains

These values are included in your beacon transmissions and help other stations understand your coverage area and antenna characteristics. Set them realistically for accurate path predictions.

### After Deployment

Modify beacon settings without rebuilding ISO:

```bash
nano ~/.config/direwolf/direwolf.conf
# Edit BEACON parameters and restart direwolf
systemctl restart direwolf
```

---

## APRS Symbol Table Reference

The APRS symbol set includes two main tables: **Primary** (/) and **Alternate** (\). Each symbol consists of a table character and a symbol character. For images and detailed overlay definitions, see https://www.aprs.org/symbols/symbolsX.txt

### Primary Symbol Table (/)

| Notation | Icon | Description |
|----------|------|------------|
| `/!` | 🚔 | Police, Sheriff |
| `/"` | ❌ | Reserved (was rain) |
| `/#` | 📡 | DIGI (white center) |
| `/$` | ☎️ | PHONE |
| `/%` | 📍 | DX CLUSTER |
| `/&` | 🌐 | HF GATEWAY |
| `/'` | ✈️ | Small AIRCRAFT (SSID-11) |
| `/(` | 🛰️ | Mobile Satellite Station |
| `/)` | ♿ | Wheelchair (handicapped) |
| `/*` | 🏂 | SnowMobile |
| `/+` | ➕ | Red Cross |
| `/,` | 👦 | Boy Scouts |
| `/-` | 🏠 | House QTH (VHF) |
| `/.` | ❌ | X |
| `//` | 🔴 | Red Dot |
| `/0`-`/9` | 0️⃣-9️⃣ | TBD (numbered symbols, overlay-capable) |
| `/:` | 🔥 | FIRE |
| `/;` | ⛺ | Campground (Portable ops) |
| `/<` | 🏍️ | Motorcycle (SSID-10) |
| `/=` | 🚂 | RAILROAD ENGINE |
| `/>` | 🚗 | CAR (SSID-9) |
| `/?` | 💾 | SERVER for Files |
| `/@` | 📍 | HC FUTURE predict (dot) |
| `/A` | 🚑 | Aid Station |
| `/B` | 💬 | BBS or PBBS |
| `/C` | 🛶 | Canoe |
| `/D` | ⏸️ | (unassigned) |
| `/E` | 👁️ | EYEBALL (Events, etc!) |
| `/F` | 🚜 | Farm Vehicle (tractor) |
| `/G` | 🗺️ | Grid Square (6 digit) |
| `/H` | 🛏️ | HOTEL (blue bed symbol) |
| `/I` | 🌐 | TcpIp on air network stn |
| `/J` | ⏸️ | (unassigned) |
| `/K` | 🏫 | School |
| `/L` | 💻 | PC user |
| `/M` | 🍎 | MacAPRS |
| `/N` | 📡 | NTS Station |
| `/O` | 🎈 | BALLOON (SSID-11) |
| `/P` | 👮 | Police |
| `/Q` | ⏸️ | TBD |
| `/R` | 🚙 | REC. VEHICLE (SSID-13) |
| `/S` | 🚀 | SHUTTLE |
| `/T` | 📺 | SSTV |
| `/U` | 🚌 | BUS (SSID-2) |
| `/V` | 🚙 | ATV |
| `/W` | 🌤️ | National WX Service Site |
| `/X` | 🚁 | HELO (SSID-6) |
| `/Y` | ⛵ | YACHT (sail) (SSID-5) |
| `/Z` | 💾 | WinAPRS |
| `/[` | 👤 | Human/Person (SSID-7) |
| `/\` | △ | TRIANGLE (DF station) |
| `/]` | 📬 | MAIL/PostOffice (was PBBS) |
| `/^` | ✈️ | LARGE AIRCRAFT |
| `/_` | ⛅ | WEATHER Station (blue) |
| `/`` | 📡 | Dish Antenna |
| `/a` | 🚑 | AMBULANCE (SSID-1) |
| `/b` | 🚲 | BIKE (SSID-4) |
| `/c` | 🏢 | Incident Command Post |
| `/d` | 🚒 | Fire dept |
| `/e` | 🐴 | HORSE (equestrian) |
| `/f` | 🚒 | FIRE TRUCK (SSID-3) |
| `/g` | ✈️ | Glider |
| `/h` | 🏥 | HOSPITAL |
| `/i` | 🏝️ | IOTA (islands on the air) |
| `/j` | 🚙 | JEEP (SSID-12) |
| `/k` | 🚚 | TRUCK (SSID-14) |
| `/l` | 💻 | Laptop |
| `/m` | 📡 | Mic-E Repeater |
| `/n` | 🎯 | Node (black bulls-eye) |
| `/o` | 🏛️ | EOC |
| `/p` | 🐕 | ROVER (puppy, or dog) |
| `/q` | 📍 | GRID SQ shown above 128 m |
| `/r` | 🔊 | Repeater |
| `/s` | 🚢 | SHIP (pwr boat) (SSID-8) |
| `/t` | ⛽ | TRUCK STOP |
| `/u` | 🚚 | TRUCK (18 wheeler) |
| `/v` | 🚐 | VAN (SSID-15) |
| `/w` | 💧 | WATER station |
| `/x` | 🖥️ | xAPRS (Unix) |
| `/y` | 📶 | YAGI @ QTH |
| `/z` | ⏸️ | TBD |

### Alternate Symbol Table (\)

| Notation | Icon | Description |
|----------|------|------------|
| `\!` | 🚨 | EMERGENCY (and overlays) |
| `\"` | ❌ | Reserved |
| `\#` | ⭐ | OVERLAY DIGI (green star) |
| `\$` | 🏧 | Bank or ATM (green box) |
| `\%` | ⚡ | Power Plant with overlay |
| `\&` | 🌐 | I=IGate R=RX T=1hopTX 2=2hopTX |
| `\'` | 💥 | Crash (& now Incident sites) |
| `\(` | ☁️ | CLOUDY (other clouds w ovly) |
| `\)` | 🔥 | Firenet MEO, MODIS Earth Obs. |
| `\*` | ❄️ | AVAIL (SNOW moved to ovly) |
| `\+` | ⛪ | Church |
| `\,` | 👧 | Girl Scouts |
| `\-` | 🏠 | House (H=HF) (O = Op Present) |
| `\.` | ❓ | Ambiguous (Big Question mark) |
| `\/` | 🎯 | Waypoint Destination |
| `\0` | ⭕ | CIRCLE (IRLP/Echolink/WIRES) |
| `\1`-`\7` | ⏸️ | AVAIL |
| `\8` | 📡 | 802.11 or other network node |
| `\9` | ⛽ | Gas Station (blue pump) |
| `\:` | ❄️ | AVAIL (Hail => ovly) |
| `\;` | 🏞️ | Park/Picnic + overlay events |
| `\<` | 🌪️ | ADVISORY (one WX flag) |
| `\=` | 📦 | Avail. symbol overlay group |
| `\>` | 🚗 | OVERLAYED CARs & Vehicles |
| `\?` | ℹ️ | INFO Kiosk (Blue box with ?) |
| `\@` | 🌀 | HURRICANE/Tropical-Storm |
| `\A` | 📦 | OVERLAY BOX DTMF & RFID & XO |
| `\B` | ❄️ | AVAIL (BlwngSnow => ovly) |
| `\C` | ⚓ | Coast Guard |
| `\D` | 📦 | DEPOTS (Drizzle => ovly) |
| `\E` | 💨 | Smoke (& other vis codes) |
| `\F` | ❄️ | AVAIL (FrzngRain => ovly) |
| `\G` | ❄️ | AVAIL (Snow Shwr => ovly) |
| `\H` | 🌫️ | Haze (& Overlay Hazards) |
| `\I` | 🌧️ | Rain Shower |
| `\J` | ⚡ | AVAIL (Lightning => ovly) |
| `\K` | 📻 | Kenwood HT (W) |
| `\L` | 🔦 | Lighthouse |
| `\M` | 🎖️ | MARS (A=Army, N=Navy, F=AF) |
| `\N` | ⛵ | Navigation Buoy |
| `\O` | 🎈 | Overlay Balloon (Rocket) |
| `\P` | 🅿️ | Parking |
| `\Q` | 📍 | QUAKE |
| `\R` | 🍽️ | Restaurant |
| `\S` | 🛰️ | Satellite/Pacsat |
| `\T` | ⛈️ | Thunderstorm |
| `\U` | ☀️ | SUNNY |
| `\V` | 📍 | VORTAC Nav Aid |
| `\W` | 🌤️ | NWS site (NWS options) |
| `\X` | 💊 | Pharmacy Rx (Apothicary) |
| `\Y` | 📻 | Radios and devices |
| `\Z` | ⏸️ | AVAIL |
| `\[` | 🌥️ | W.Cloud (& humans w Ovly) |
| `\\` | 📍 | New overlayable GPS symbol |
| `\]` | ⏸️ | AVAIL |
| `\^` | ✈️ | Other Aircraft overlays (2014) |
| `\_` | 🌤️ | WX site (green digi) |
| `\`` | 🌧️ | Rain (all types w ovly) |
| `\a` | 📡 | ARRL, ARES, WinLINK, D-Star, etc |
| `\b` | 💨 | AVAIL (Blwng Dst/Snd => ovly) |
| `\c` | △ | CD triangle RACES/SATERN/etc |
| `\d` | 📍 | DX spot by callsign |
| `\e` | ❄️ | Sleet (& future ovly codes) |
| `\f` | 🌪️ | Funnel Cloud |
| `\g` | 🚩 | Gale Flags |
| `\h` | 🏪 | Store or HAMFST Hh=HAM store |
| `\i` | 📦 | BOX or points of Interest |
| `\j` | 🏗️ | WorkZone (Steam Shovel) |
| `\k` | 🚙 | Special Vehicle SUV, ATV, 4x4 |
| `\l` | 📍 | Areas (box, circles, etc) |
| `\m` | 📊 | Value Sign (3 digit display) |
| `\n` | △ | OVERLAY TRIANGLE |
| `\o` | ⭕ | Small circle |
| `\p` | ☁️ | AVAIL (PrtlyCldy => ovly) |
| `\q` | ⏸️ | AVAIL |
| `\r` | 🚻 | Restrooms |
| `\s` | 🚢 | OVERLAY SHIP/boats |
| `\t` | 🌪️ | Tornado |
| `\u` | 🚚 | OVERLAYED TRUCK |
| `\v` | 🚐 | OVERLAYED Van |
| `\w` | 🌊 | Flooding (Avalanches/Slides) |
| `\x` | ❌ | Wreck or Obstruction ->X<- |
| `\y` | 🌪️ | Skywarn |
| `\z` | 🏠 | OVERLAYED Shelter |

### Symbol Notation Reference

- **Table Character**: `/` (Primary) or `\` (Alternate)
- **Symbol Character**: A single letter or number (case-sensitive)
- **Examples**: `/a` = Ambulance (Primary), `\s` = Ship (Alternate)
- **Overlays**: Many symbols support overlays (0-9, A-Z) for extended meanings
- **Special**: Some symbols are marked with `#O` for overlay-capable or special handling

### Finding Symbol Images

Official symbol images and detailed overlay definitions are available at:
- https://www.aprs.org/symbols/symbolsX.txt — Master symbol list with notes
- https://www.aprs.org/symbols/symbols-new.txt — New overlay symbol definitions

Note: As of 2007, provisions allow overlays on nearly all alternate symbols, creating hundreds of possible symbol combinations. Check the symbols-new.txt file for overlay-specific meanings.

---

## Backup & Restore

### What Gets Backed Up

Two things persist across ISO builds:

1. **wine.tar.gz** - VARA FM Windows Prefix
   - Audio calibration, modem settings, driver configurations
   - Note: License keys are in Windows Registry (backed up with wine prefix)
   - Static "golden master" - same for all deployments
   - Update intentionally when you find good settings

2. **et-user backups** - Your ETC customizations
   - Callsign, grid square, radio settings
   - Captured automatically on each build (if upgrading)
   - Restored automatically to preserve user settings

### Where Backups Are Stored

**On build system:**
```
/home/{USER_USERNAME}/etc-customizer-backups/
├── wine.tar.gz                 # VARA FM baseline
├── et-user.tar.gz              # User settings (optional)
├── et-user-current.tar.gz      # Auto-captured during build
└── ubuntu-22.10-desktop-amd64.iso  # Cached (3.6GB)
```

Path is automatically derived from `USER_USERNAME` in `secrets.env`.

### Backup Workflow

```
Build ISO (Stage 2):
  ├─ Detect: Look in ~/etc-customizer-backups/
  ├─ Capture: Save current ~/.config/emcomm-tools/ (if upgrading)
  └─ Restore: Extract backups to /etc/skel for new users

Deploy System:
  ├─ New user gets files from /etc/skel
  └─ Includes backups in /etc/skel/.etc-customizer-backups/

Post-Boot (Optional):
  ├─ Run: post-install/restore-backups-from-skel.sh
  └─ Restores backups to ~/etc-customizer-backups/
```

### Creating Backups

**VARA FM baseline** (one-time setup - CRITICAL):

⚠️ **IMPORTANT**: Create this backup **BEFORE opening VARA FM for the first time** on a fresh deployment. VARA FM should only be backed up in its initial state.

```bash
# On a fresh system (before opening VARA FM):
tar -czf ~/wine.tar.gz ~/.wine/
cp ~/wine.tar.gz ~/etc-customizer-backups/wine.tar.gz
```

Do NOT update this backup after using VARA FM (upstream documents prohibit this).

**User settings baseline** (optional):

```bash
# After setting callsign, grid, radio preferences:
tar -czf ~/et-user.tar.gz ~/.config/emcomm-tools/
cp ~/et-user.tar.gz ~/etc-customizer-backups/et-user.tar.gz
```

Backups are automatically detected and restored on next ISO build.

---

## Build Script Options

```bash
./build-etc-iso.sh [OPTIONS]

OPTIONS:
    -r MODE      Release mode (default: latest)
                 - stable: Latest stable GitHub release
                 - latest: Latest tag (any version)
                 - tag: Specific tag (requires -t)
    -t TAG       Release tag (required with -r tag)
    -u PATH      Existing Ubuntu ISO (skips download)
    -b PATH      VARA FM backup (auto-detected if not specified)
    -e PATH      et-user backup (auto-detected if not specified)
    -p PATH      Private files (local dir or GitHub repo URL)
    -c           Cleanup mode (remove embedded Ubuntu ISO)
    -d           Dry-run (show what would happen)
    -v           Verbose (bash debugging)
    -h           Help message

EXAMPLES:
    # Simple: latest stable release
    ./build-etc-iso.sh -r stable

    # With cleanup (save ~3.6GB disk space)
    ./build-etc-iso.sh -r stable -c

    # Specific release version
    ./build-etc-iso.sh -r tag -t emcomm-tools-os-community-R5-final

    # With existing Ubuntu ISO (skip download)
    ./build-etc-iso.sh -r stable -u ~/Downloads/ubuntu-22.10-desktop-amd64.iso

    # Dry-run to see what will happen
    ./build-etc-iso.sh -r stable -d
```

---

## Project Philosophy

**This customizer respects upstream ETC design:**

- ✅ **Standalone system** (works offline, no internet required for normal use)
- ✅ **Single-user ISO** (safe to include WiFi credentials since built for you)
- ✅ **Fully automated** (no manual steps except Cubic GUI launch)
- ✅ **Reproducible builds** (same input = same output)
- ✅ **Minimal additions** (only adds automation, doesn't change upstream)

**What we DON'T add:**
- ❌ Multi-user setup (not needed for emergency ops)
- ❌ Upstream package updates (builds are reproducible from fixed ETC release)
- ❌ Unnecessary complexity (KISS principle - only add automation, don't modify upstream)
- ❌ Promises we don't keep (this README is honest about what works)

---

## Troubleshooting

### "Ubuntu ISO not found"
The script checks `~/etc-customizer-backups/ubuntu-22.10-desktop-amd64.iso` first. If missing, it downloads from old-releases.ubuntu.com (slow but reliable).

### "secrets.env not found"
Create it from template:
```bash
cp secrets.env.template secrets.env
nano secrets.env  # Edit your values
```

### "Backups not detected"
Check the path:
```bash
ls -la ~/etc-customizer-backups/
```
Should show `wine.tar.gz`, `et-user.tar.gz`, or `.iso` files.

### Cubic GUI won't launch
```bash
sudo apt install cubic
```

### ISO build fails
Check the logs:
```bash
tail -f ~/etc-builds/logs/build-*.log
```

---

## Resources

- **EmComm Tools Community:** https://community.emcommtools.com/
- **Cubic:** https://github.com/PJ-Singh-001/Cubic
- **Hamlib (rigctld):** https://hamlib.github.io/
- **Digirig Mobile:** https://digirig.net/

---

## Limitations & Known Issues

- **Cubic requires GUI** - No command-line alternative yet
- **x64 only** - ARM/Apple Silicon not supported
- **Ubuntu 22.10 base** - Can't use other Ubuntu versions without significant changes

---

## License

This project is provided as-is for amateur radio and emergency communications use. See upstream ETC project for base system licensing.

**Credit:** All thanks to TheTechPrepper and the EmComm Tools Community for the outstanding upstream work.
