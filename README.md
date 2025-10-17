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
- **Ham radio software** (CHIRP, dmrconfig, flrig) - installed and ready
- **APRS/digital mode apps** (direwolf, YAAC, Pat/Winlink) - configured with your callsign
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
   # Install Cubic
   sudo add-apt-repository ppa:cubic-wizard/release
   sudo apt update && sudo apt install cubic
   
   # Clone your fork
   git clone https://github.com/YourUsername/emcomm-tools-customizer.git
   cd emcomm-tools-customizer
   
   # Copy secrets.env to this folder (transfer securely from dev system)
   
   # Run build
   ./build-etc-iso.sh
   ```
4. **Result:** Custom ISO ready to burn to USB

### Deployment
1. Burn ISO to USB (Balena Etcher, Rufus, or `dd`)
2. Boot target system from USB
3. Install ETC
4. First boot: WiFi connects automatically, everything pre-configured!

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
- ✅ **Anytone D578UV** (mobile radio): **FULL CAT** via `/dev/ttyUSB1`
- ✅ Most HF transceivers with appropriate Digirig cables

### Supported Radios WITHOUT CAT (Audio + PTT only):
- ❌ **Anytone D878UV** (handheld): **NO CAT** - Audio and PTT only
- ❌ **BTech UV-Pro** (handheld): **NO CAT** - Uses upstream KISS TNC via et-radio

### How flrig Integration Works (for CAT-capable radios):

1. **Digirig Mobile connected** → Creates two serial ports:
   - `/dev/ttyUSB0` = Audio device (use in direwolf, fldigi for audio)
   - `/dev/ttyUSB1` = CAT control (use in flrig if radio supports CAT)

2. **flrig starts** → XML-RPC server on `localhost:12345`
   - Radio model: Anytone D578 (for D578UV mobile)
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
   - Set `WIFI_COUNT` to match the number of networks you configure

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
# User Configuration
USER_FULLNAME="Your Name"
USER_USERNAME="yourname"
USER_PASSWORD="YourPassword"  # For auto-login
CALLSIGN="N0CALL"  # Your amateur radio callsign

# WiFi Networks (indexed for multiple networks)
WIFI_COUNT=3  # How many networks to configure

# WiFi Network 1 - Home
WIFI_1_SSID="Home-Network-5G"
WIFI_1_PASSWORD="HomePassword123"
WIFI_1_AUTOCONNECT="yes"

# WiFi Network 2 - Mobile Hotspot  
WIFI_2_SSID="iPhone-Hotspot"
WIFI_2_PASSWORD="HotspotPassword456"
WIFI_2_AUTOCONNECT="no"  # Don't auto-connect to mobile

# WiFi Network 3 - EOC/Field
WIFI_3_SSID="EmComm-Field"
WIFI_3_PASSWORD="FieldPassword789"
WIFI_3_AUTOCONNECT="yes"

# APRS Configuration
APRS_SSID="10"  # SSID for APRS (typically 10 for iGate)
APRS_PASSCODE="-1"  # Get from apps.magicbug.co.uk/passcode
APRS_COMMENT="EmComm iGate"
DIGIPEATER_PATH="WIDE1-1"
```

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

**73 de KD7DGF** 📻
