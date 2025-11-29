# EmComm Tools OS Customizer

**Custom ISO builder for EmComm Tools Community (ETC) with personalized configurations**

This project creates a customized Ubuntu-based ISO for emergency communications by amateur radio operators, built using Cubic with all your personal preferences baked in.

> **⚠️ IMPORTANT: x64 Architecture Only**  
> This project **only supports x64/AMD64 systems**. ARM architectures are **NOT supported**, including:
> - Apple Silicon Macs (M1, M2, M3, M4)
> - Raspberry Pi
> - ARM-based servers
> 
> You must build and deploy on **Intel/AMD 64-bit systems** only. For building on Apple Silicon, use a VM with x64 emulation (slow) or build on a separate Intel system.

---

## About EmComm Tools Community (ETC)

This customizer is built upon the outstanding work of **TheTechPrepper** and the **EmComm Tools Community** project:

- **Project Homepage:** [EmComm Tools Community](https://community.emcommtools.com/)
- **GitHub Repository:** [emcomm-tools-os-community](https://github.com/thetechprepper/emcomm-tools-os-community)
- **Creator:** TheTechPrepper (YouTube: [@TheTechPrepper](https://www.youtube.com/@TheTechPrepper))

**EmComm Tools Community** is a turnkey, Ubuntu-based operating system specifically designed for amateur radio emergency communications. It comes pre-configured with digital mode software, radio control tools, APRS applications, and offline documentation for field use.

**All credit goes to TheTechPrepper** for creating this incredible foundation. This customizer project simply adds personal automation scripts to further customize the ETC base system for individual deployments.

**Please support the upstream ETC project:**
- Visit the [community forums](https://community.emcommtools.com/)
- Subscribe to [TheTechPrepper's YouTube channel](https://www.youtube.com/@TheTechPrepper)
- Contribute to the [GitHub repository](https://github.com/thetechprepper/emcomm-tools-os-community)
- Share ETC with your local EmComm group

---

## What This Project Does

Creates a **single-user custom ETC ISO** containing:

- **Pre-configured WiFi networks** (home, mobile hotspot, EOC) - auto-connect on first boot
- **Ham radio software** (CHIRP, dmrconfig, hamlib, flrig) - installed and ready
- **APRS/digital mode apps** (direwolf, YAAC, Pat/Winlink) - configured with your callsign
- **Development tools** (VS Code, git, build tools, uv, Python) - ready for customization
- **Git configuration** (user name/email, best practices, aliases) - pre-configured for your workflows
- **Desktop customizations** (dark mode, accessibility, desktop shortcuts)
- **Your preferences** (callsign, APRS settings, WiFi credentials) - all from `secrets.env`

**Key Concept:** This is a **single-user ISO**—you can safely include personal WiFi credentials and callsign because it's built for YOUR use, not mass distribution.

---

## Quick Start

### Prerequisites
- **x64/AMD64 system** (Intel or AMD processor) - NO ARM/Apple Silicon support
- Ubuntu system (VM, live USB, or installed) for running Cubic
- GitHub account (fork this repository)
- Your WiFi credentials and amateur radio callsign

### Build Process
1. **Fork this repository** to your GitHub account
2. **Create `secrets.env`** from template (see Security section below)
3. **On Ubuntu system:**
   ```bash

   # Clone your fork
   git clone https://github.com/YourUsername/emcomm-tools-customizer.git
   cd emcomm-tools-customizer
   
   # Copy secrets.env to this folder (transfer securely from dev system)
   
   # Run build with latest stable release
   ./build-etc-iso.sh -r stable
   
   # Or with cleanup mode to save space (~3.6GB)
   ./build-etc-iso.sh -r stable -c
   ```
4. **Follow Cubic instructions** generated in `~/etc-builds/<release-name>/CUBIC_INSTRUCTIONS.md`
5. **Result:** Custom ISO ready to copy onto your Ventoy USB drive

### Build Script Options

The `build-etc-iso.sh` script handles downloading the ETC release (source code archive from GitHub) and preparing all files for Cubic customization. It supports several options:

```bash
./build-etc-iso.sh [OPTIONS]

OPTIONS:
    -r MODE   Release mode (default: latest)
              - stable: Use latest stable GitHub release
              - latest: Use most recent release (any tag)
              - tag:    Use specific tag (requires -t)
    -t TAG    Specify release tag (required when -r tag)
              Example: emcomm-tools-os-community-20250401-r4-final-4.0.0
    -u PATH   Path to existing Ubuntu 22.10 ISO (skips download)
    -b PATH   Path to .wine backup (auto-detected if not specified)
    -e PATH   Path to et-user backup (auto-detected if not specified)
    -p PATH   Path to private files (local dir or GitHub repo)
    -c        Cleanup mode: Remove embedded Ubuntu ISO to save space
    -d        Dry-run mode (show what would be done)
    -v        Verbose mode (enable bash debugging)
    -h        Show help message

WORKFLOW:
    1. Fetches ETC release from GitHub (source code archive)
    2. Downloads Ubuntu 22.10 ISO (if not provided)
    3. Prepares all files in ~/etc-builds/<release-tag>/
    4. Generates Cubic instructions for manual ISO building
    5. You then launch Cubic and import the project directory
```

### Examples

```bash
# Build latest stable release (recommended)
./build-etc-iso.sh -r stable

# Build most recent release tag
./build-etc-iso.sh -r latest

# Build specific release with cleanup mode
./build-etc-iso.sh -r tag -t emcomm-tools-os-community-20250401-r4-final-4.0.0 -c

# Build with private files from GitHub
./build-etc-iso.sh -r stable -p https://github.com/username/private-configs

# Dry run to see what would happen
./build-etc-iso.sh -r stable -d

# Build with existing Ubuntu ISO to skip re-downloading
./build-etc-iso.sh -r stable -u ~/Downloads/ubuntu-22.10-desktop-amd64.iso
```

### Deploying with Ventoy (Default Workflow)

1. Install Ventoy on a USB drive (one-time) using the official installer: [ventoy.net](https://www.ventoy.net/en/doc_start.html)
2. After building the ISO, mount the Ventoy data partition on your build system (typically `/media/$USER/Ventoy`).
3. Copy the ISO onto the Ventoy drive and flush writes. You can let the helper script auto-detect the mount or run the copy manually:

   ```bash
   # Preferred: auto-detect Ventoy and copy
   ./copy-iso-to-ventoy.sh ~/etc-builds/<release-tag>/<release-tag>.iso

   # Manual copy (if you prefer to specify the mount point)
   cp ~/etc-builds/<release-tag>/<release-tag>.iso /media/$USER/Ventoy/
   sync
   ```

4. Safely eject the Ventoy drive and boot it on target hardware. Ventoy will list the new ISO alongside any others on the disk.

---

## Project Structure

```
emcomm-tools-customizer/
├── cubic/                          # Scripts run DURING ISO build (preferred)
│   ├── install-ham-tools.sh       # Install CHIRP, dmrconfig, flrig, LibreOffice
│   ├── configure-wifi.sh          # Configure WiFi from secrets.env
│   ├── configure-aprs-apps.sh     # Configure direwolf, YAAC, Pat
│   ├── configure-radio-defaults.sh # flrig integration for Anytone radios
│   ├── setup-desktop-defaults.sh  # Dark mode, accessibility, themes
│   └── finalize-build.sh          # Final cleanup and manifest
├── post-install/                   # Scripts run AFTER installation (rarely needed)
│   └── (hardware detection only)
├── secrets.env.template            # Template for configuration (safe to commit)
├── secrets.env                     # YOUR credentials (NEVER commit - gitignored)
├── build-etc-iso.sh               # Main build orchestration script
├── copy-iso-to-ventoy.sh          # Helper to detect Ventoy and copy finished ISO
├── README.md                       # This file
└── TTPCustomization.md            # Beginner's guide to customization

```

### Cubic vs. Post-Install

**IMPORTANT:** Almost all customizations should happen in `cubic/` (during ISO build), NOT post-install!

| Cubic Scripts (`cubic/`) | Post-Install Scripts (`post-install/`) |
|-------------------------|----------------------------------------|
| Run during ISO creation | Run after ETC installation |
| Can include user data (WiFi, callsign) | Only hardware-specific detection |
| Install packages, configure apps | Interactive wizards only |
| **PREFERRED** | **RARELY USED** |

**Rule of Thumb:** If it CAN be done in Cubic, it SHOULD be done in Cubic!

---

## Radio Hardware Support

### IMPORTANT: Digirig Mobile CAT Capabilities
The Digirig Mobile hardware provides:
- **CM108 audio codec** (creates `/dev/ttyUSB0` - use for audio)
- **CP2102 serial interface** (creates `/dev/ttyUSB1` - use for CAT if supported)
- **PTT switch** (hardware PTT control)

### Supported Radios with CAT:

- ✅ **Anytone D578UV** (mobile, 2m/1.25cm/70cm): **FULL CAT** via `/dev/ttyUSB1`

### Supported Radios WITHOUT CAT (Audio + PTT only):

- ❌ **Anytone D878UV** (handheld): **NO CAT** - Audio and PTT only
- ❌ **BTech UV-Pro** (handheld): **NO CAT** - Uses upstream KISS TNC via et-radio

### How CAT Control Works (for Anytone D578UV):

1. **Digirig Mobile connected** → Creates two serial ports:
   - `/dev/ttyUSB0` = Audio device (use in direwolf, fldigi for audio)
   - `/dev/ttyUSB1` = CAT control (hamlib/rigctld for frequency management)

2. **rigctld daemon starts** → XML-RPC server on `localhost:12345`
   - Radio model: Anytone D578UV (hamlib rig ID 242)
   - Serial port: `/dev/ttyUSB1`
   - Baud rate: 9600

3. **et-radio detects flrig** → Configures apps automatically
   
4. **Apps connect to flrig** → Frequency/mode control
   - fldigi: XML-RPC to `127.0.0.1:12345`
   - Pat Winlink: flrig network config
   - YAAC: CAT control via flrig

5. **CAT control active** → Change frequency in app, radio follows

**Note**: For handhelds (D878UV, UV-Pro), use audio and PTT only. Manual frequency tuning required.

---

## Security & Secrets Management

**CRITICAL:** Never commit WiFi passwords or other secrets to public repositories!

### The `secrets.env` Pattern

Two files work together:

1. **`secrets.env.template`** (safe to commit to GitHub)
   - Contains placeholder values and instructions
   - Shows structure without revealing actual secrets

2. **`secrets.env`** (NEVER committed - in `.gitignore`)
   - Your actual WiFi credentials, callsign, APRS passcode
   - Stays local on your build system only
   - Used by scripts during Cubic ISO build

### Setup Your Secrets File

**If using VS Code GitHub Repositories extension:**

1. **Create a local secrets file**:
   - In VS Code, right-click on `secrets.env.template` → Copy
   - Right-click in the file area → Paste  
   - Rename the copy to `secrets.env`
   - **Save this file locally** (not in the GitHub repository workspace)

2. **Edit your local `secrets.env`** with actual WiFi credentials:
   - Replace all placeholder values with your real SSIDs and passwords
   - Add networks as needed using the `WIFI_SSID_<ID>` format (script auto-detects all entries, no count needed)

3. **Copy the local secrets file to the target Ubuntu system** when deploying

**If using traditional git clone:**

1. Copy the template:
   ```bash
   cp secrets.env.template secrets.env
   ```

2. Edit with your actual values:
   ```bash
   nano secrets.env
   ```

### Configuration Variables

Your `secrets.env` should contain:

```bash
### Configuration Variables

Your `secrets.env` should contain:

```bash
# User Account Configuration
USER_FULLNAME="Your Full Name"
USER_USERNAME="yourusername"
USER_PASSWORD="YourPassword"
USER_EMAIL="your.email@example.com"  # For git commits

# System Configuration
CALLSIGN="N0CALL"  # Your amateur radio callsign (e.g., KD7DGF)
MACHINE_NAME="ETC-KD7DGF"  # Hostname (defaults to ETC-{CALLSIGN})

# Desktop Environment (GNOME)
DESKTOP_COLOR_SCHEME="prefer-dark"  # prefer-dark or prefer-light
DESKTOP_SCALING_FACTOR="1.5"  # Display scale: 1.0 (100%), 1.5 (150%), 2.0 (200%)

# WiFi Networks (add as many as needed)
WIFI_SSID_PRIMARY="Home-Network-5G"
WIFI_PASSWORD_PRIMARY="HomePassword123"
WIFI_AUTOCONNECT_PRIMARY="yes"

WIFI_SSID_MOBILE="Mobile-Hotspot"
WIFI_PASSWORD_MOBILE="MobilePassword456"
WIFI_AUTOCONNECT_MOBILE="no"  # Don't auto-connect to mobile hotspot

# APRS Configuration
CALLSIGN="N0CALL"
APRS_SSID="10"
APRS_PASSCODE="-1"  # Get from https://apps.magicbug.co.uk/passcode/
APRS_COMMENT="EmComm iGate"
```

---

## APRS & Winlink Configuration

This customizer provides **secrets-based configuration** for APRS applications (direwolf, YAAC) and optional enhancements to Pat/Winlink. All settings are read at ISO build time from `secrets.env` and baked into `/etc/skel` for the user environment.

### APRS Operation Modes

#### **iGate Mode** (Internet-to-RF Gateway)
Used for **home stations** and **EOC (Emergency Operations Centers)** with internet connectivity.

- **Purpose**: Relay APRS packets between internet (APRS-IS) and local RF
- **Enable**: Set `ENABLE_APRS_IGATE="yes"` in secrets.env
- **Configuration**:
  - `APRS_SERVER`: APRS-IS server (default: `noam.aprs2.net` for North America)
    - Options: `noam.aprs2.net` (North America), `soam.aprs2.net` (South America), `euro.aprs2.net` (Europe)
  - `APRS_IGTXVIA`: How to relay packets (default: `"0"` for direct, or `"WIDE2-2"` for wider coverage)
  - `APRS_IGFILTER_RADIUS`: Only relay packets within this distance (default: `"500"` km)

**Example - Home iGate (default settings):**
```bash
ENABLE_APRS_IGATE="yes"
APRS_IGTXVIA="0"
APRS_IGFILTER_RADIUS="500"
APRS_SERVER="noam.aprs2.net"
```

#### **Beacon Mode** (Position Broadcasting)
Used for **mobile stations** and **field deployments** with GPS.

- **Purpose**: Periodically broadcast your position to APRS network via RF
- **Enable**: Set `ENABLE_APRS_BEACON="yes"` in secrets.env
- **Requires**: GPS device connected to system
- **Configuration**:
  - `APRS_BEACON_INTERVAL`: Seconds between beacons (default: `"30"`, typical: 30-600)
    - Fast (30-60s): High-speed mobile, very mobile operations
    - Slow (300-600s): Stationary or slow-moving stations
  - `APRS_BEACON_POWER`: Transmit power code 0-9 (default: `"10"`)
  - `APRS_BEACON_HEIGHT`: Antenna height above ground in feet (default: `"20"`)
  - `APRS_BEACON_GAIN`: Antenna gain code 0-9 (default: `"3"`)

**Example - Field Mobile (every 2 minutes, lower power):**
```bash
ENABLE_APRS_BEACON="yes"
APRS_BEACON_INTERVAL="120"
APRS_BEACON_POWER="5"
APRS_BEACON_HEIGHT="10"
APRS_BEACON_GAIN="2"
```

**⚠️ CRITICAL**: Never enable beacon without GPS connected. Your position will be wrong and mislead the APRS network!

#### **Both iGate + Beacon**
Advanced operators can enable both simultaneously:
```bash
ENABLE_APRS_IGATE="yes"
ENABLE_APRS_BEACON="yes"
# direwolf becomes full two-way APRS station
```

### Audio Interface Configuration

The system defaults to **Digirig Mobile USB interface** (`plughw:1,0`). If you're using different audio hardware, uncomment and modify in `secrets.env`:

```bash
# Digirig Mobile (default - keep commented)
# DIREWOLF_ADEVICE="plughw:1,0"

# Built-in audio (laptop/desktop)
# DIREWOLF_ADEVICE="default:0"

# Specific ALSA device (use `aplay -l` to find)
# DIREWOLF_ADEVICE="hw:2,0"
```

**PTT Methods**:
```bash
DIREWOLF_PTT="CM108"      # USB Digirig/SignaLink (default)
# DIREWOLF_PTT="RTS"      # Serial port RTS pin
# DIREWOLF_PTT="DTR"      # Serial port DTR pin
# DIREWOLF_PTT="GPIO"     # GPIO pins (Raspberry Pi)
# DIREWOLF_PTT="VOX"      # Voice-activated (hands-free)
```

### Pat/Winlink Configuration

Pat Winlink is pre-installed by ETC upstream. This customizer configures the **EmComm alias** for emergency communications using **VARA FM over VHF/UHF** (recommended for Anytone D578UV + Digirig Mobile).

**Default Pat Aliases** (unchanged):
- `pat connect ardop:///<CALLSIGN>` - Standard Pat connection
- Other Winlink RMS aliases available from ETC

**EmComm Alias** (configured by customizer):
```bash
PAT_EMCOMM_ALIAS="yes"        # Enable EmComm alias
PAT_EMCOMM_MODE="VARA FM"     # VARA FM for VHF/UHF (Anytone D578UV)
```

**Primary Modes for This Customizer**:

- **VARA FM over VHF/UHF** (2m/70cm): Recommended for Anytone D578UV + Digirig Mobile
  - Speed: 2400 bps (high-speed digital)
  - Range: Local/regional (depends on repeater network)
  - Hardware: Any FM radio with audio interface
  - Use Case: Emergency email via internet-connected gateway

- **AX.25 over Bluetooth TNC**: For portable field operations
  - Speed: 1200-9600 bps
  - Range: Local packet network
  - Hardware: Bluetooth TNC + any FM radio
  - Use Case: APRS, keyboard-to-keyboard digital QSOs

**HF ARDOP Support** (future option):

If you add HF transceiver support in the future, Pat can also connect to HF ARDOP:
- **80m**: `3.573.0` - Primary emergency frequency
- **40m**: `5.348.0` - Secondary emergency frequency
- **20m**: `7.106.0`, **17m**: `10.149.0`, **15m**: `14.107.0`

**Usage**:
```bash
# With EmComm alias enabled (VHF/UHF VARA FM):
pat connect emcomm    # Uses configured mode (VARA FM by default)

# Standard Pat connection:
pat connect ardop     # Uses default RMS Relay network
```

### Setup Scenarios

#### **Scenario 1: Home iGate + EOC Station**
```bash
ENABLE_APRS_IGATE="yes"
ENABLE_APRS_BEACON="no"
APRS_IGFILTER_RADIUS="500"
PAT_EMCOMM_ALIAS="no"
DIREWOLF_ADEVICE="plughw:1,0"
DIREWOLF_PTT="CM108"
```
*Relays APRS packets to/from internet, no local position broadcasting*

#### **Scenario 2: Field Mobile with GPS**
```bash
ENABLE_APRS_IGATE="no"
ENABLE_APRS_BEACON="yes"
APRS_BEACON_INTERVAL="60"
APRS_BEACON_POWER="5"
PAT_EMCOMM_ALIAS="yes"
PAT_EMCOMM_MODE="VARA FM"
DIREWOLF_ADEVICE="plughw:1,0"
DIREWOLF_PTT="CM108"
```
*Broadcasts position every 60 seconds, EmComm alias for emergency Winlink via VARA FM*

#### **Scenario 3: EmComm Event (Both iGate + Beacon)**
```bash
ENABLE_APRS_IGATE="yes"
ENABLE_APRS_BEACON="yes"
APRS_BEACON_INTERVAL="120"
APRS_IGFILTER_RADIUS="1000"
PAT_EMCOMM_ALIAS="yes"
DIREWOLF_PTT="VOX"  # Hands-free for field work
```
*Full two-way APRS station with emergency Winlink capability*

### Modifying After ISO Install

All configurations are stored in user config files and can be modified post-installation:

```bash
# Modify direwolf beacon parameters:
nano ~/.config/direwolf/direwolf.conf

# Modify YAAC iGate server:
nano ~/.config/YAAC/YAAC.properties

# Add Pat EmComm alias after first boot (if not done automatically):
~/.local/bin/configure-pat-emcomm
```

---

## VARA FM Backup & Restoration

### Why VARA FM Backups?

**VARA FM** (Variable Rate Audio Codec) is a sophisticated Windows application for high-speed Winlink over VHF/UHF. It requires:
- **Audio calibration** - Specific levels for your Digirig Mobile interface
- **Modem settings** - Frequency offset, PTT configuration, profiles
- **License keys** - One-time activation per system

**Building a fresh ISO every time requires recalibrating VARA FM from scratch** (tedious and error-prone).

**Solution: Backup the configured Wine prefix** - The `.wine` directory contains all VARA FM settings and is automatically restored to every fresh ISO build.

### How It Works

1. **One-time setup**: Create a baseline `wine.tar.gz` with your calibrated VARA FM configuration
2. **Store in repository**: Commit `wine.tar.gz` to `/backups/` directory
3. **Automatic restoration**: Every ISO build extracts and restores VARA FM
4. **Golden master principle**: The backup is **read-only** and never overwritten with post-deployment changes

### Creating Your VARA FM Backup

**On a deployed ETC system with VARA FM configured:**

```bash
# Compress your calibrated Wine prefix
tar -czf ~/wine.tar.gz ~/.wine/

# Copy to this repository (on your build system)
# Place the file in: emcomm-tools-customizer/backups/wine.tar.gz

# Commit to repository
cd emcomm-tools-customizer
git add backups/wine.tar.gz
git commit -m "Add VARA FM baseline configuration backup"
git push origin main
```

### Restoration During Builds

The `cubic/restore-backups.sh` script **automatically** restores your VARA FM configuration during every ISO build:

```bash
./build-etc-iso.sh -r stable
# Internally: restore-backups.sh:
#   STEP 1: Captures current ~/.config/emcomm-tools to et-user-current.tar.gz
#   STEP 2: Extracts wine.tar.gz to /etc/skel/.wine/
#   STEP 3: Restores et-user config to /etc/skel/.config/emcomm-tools/
# Result: Fresh system has your VARA FM + user customizations ready to use
```

### User Customizations Are Preserved On Upgrade

**Three-step backup strategy:**

1. **STEP 1: Capture et-user at build start** (if upgrading)
   - Saves current callsign, grid square, radio settings
   - Creates `et-user-current.tar.gz` (specific to this build)
   - Ensures no loss of customizations during upgrade

2. **STEP 2: Restore VARA FM baseline** 
   - Restores static `wine.tar.gz` (your golden master)
   - Same baseline across all deployments
   - Audio levels reset to baseline (hardware-specific)

3. **STEP 3: Restore et-user configuration**
   - First uses `et-user-current.tar.gz` (from this build)
   - Falls back to `et-user.tar.gz` (if not available)
   - User's callsign, grid, radio settings automatically restored

### Example Upgrade Workflow

```bash
# Deployment 1: Fresh ISO
./build-etc-iso.sh -r stable
# User deploys, sets: callsign=KD7DGF, grid=CN87AB, radio=Anytone D578UV
# User tunes VARA FM locally

# [Time passes, new ISO version available with better features]

# Deployment 2: Upgrade ISO
./build-etc-iso.sh -r stable
# STEP 1: Script captures ~/.config/emcomm-tools (your settings) → et-user-current.tar.gz
# STEP 2: Script restores wine.tar.gz (VARA FM baseline)
# STEP 3: Script restores et-user-current (your callsign, grid, radio settings)
# Result: New ISO has all your custom settings, can re-tune VARA FM if needed
```

### Intentionally Updating VARA FM Baseline

If you find VARA FM settings that work well and want to carry them to all future deployments:

```bash
# After deploying and perfecting VARA FM on hardware:
tar -czf ~/wine.tar.gz ~/.wine/

# Update repository baseline
cp ~/wine.tar.gz /path/to/emcomm-tools-customizer/backups/wine.tar.gz

# Commit as new baseline
cd /path/to/emcomm-tools-customizer
git add backups/wine.tar.gz
git commit -m "Update VARA FM baseline with improved calibration"
git push origin main
```

**Result:** Next build will restore THIS audio calibration to all future deployments.

### Decision Points

**Keep changes LOCAL (default):**

- Each system has different hardware (Digirig audio levels vary)
- User's VARA FM audio tuning is hardware-specific
- Don't commit VARA FM changes to repository

**Commit changes to repository (intentional):**

- You've found VARA FM settings that work across multiple systems
- Want a team standard baseline for consistent behavior
- Settings represent a known-good configuration

---

## For Beginners: Using AI to Customize

See **[TTPCustomization.md](TTPCustomization.md)** for a complete beginner's guide covering:
- Using GitHub Copilot for bash scripting
- Understanding Cubic vs. post-install scripts
- Prompt engineering for customizations
- Documentation with Markdown
- Security best practices

---

## Resources

### Upstream Projects
- **EmComm Tools Community:** [community.emcommtools.com](https://community.emcommtools.com/)
- **TheTechPrepper YouTube:** [@TheTechPrepper](https://www.youtube.com/@TheTechPrepper)
- **ETC GitHub:** [emcomm-tools-os-community](https://github.com/thetechprepper/emcomm-tools-os-community)

### Tools & Documentation
- **Cubic:** [Cubic GitHub](https://github.com/PJ-Singh-001/Cubic)
- **Digirig Mobile:** [digirig.net](https://digirig.net/product/digirig-mobile/)
- **flrig:** [w1hkj.com](http://www.w1hkj.com/)

---

## To-Do List

- [ ] Automate et-user-backup and wine backup at build start
- [ ] GPS auto-detection and grid square updates
- [ ] Customize ICS forms for local jurisdiction
- [ ] Download radio codeplug image files during build
- [ ] Download device manuals for offline access
- [ ] Test flrig integration with et-radio system
- [ ] Document GPS auto-detection workflow

---

## License

This project is provided as-is for amateur radio and emergency communications use. See upstream ETC project for base system licensing.
