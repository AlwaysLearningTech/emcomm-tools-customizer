# Copilot Instructions for EmComm Tools Customizer

## CRITICAL RULES - READ THESE FIRST
1. **NO SUMMARY FILES - EVER** - Never create SUMMARY.md or similar. Report in chat only.
2. **ETC ALREADY HAS EVERYTHING** - Don't reinstall Python, ham tools, Wine, etc.
3. **WINE PREFIX IS `~/.wine32`** - ETC uses 32-bit Wine, NOT `~/.wine`!
4. **NO AUTOLOGIN BY DEFAULT** - User wants password prompt, not autologin. ENABLE_AUTOLOGIN defaults to "no".
5. **MODIFY ETC TEMPLATES DIRECTLY** - Don't create parallel config systems. Modify ETC's templates in `/opt/emcomm-tools/conf/template.d/` with our values while keeping their `{{ET_*}}` placeholders.
6. **NO UPDATE CONCERNS** - ETC rebuilds fresh each version. There are NO updates to break. Stop worrying about conflicts with "future updates".
7. **BUILD MACHINE = TARGET MACHINE** - User rebuilds on same hardware. Cache and logs should persist in ISO.
8. **LOOK AT ACTUAL FILES FIRST** - Verify current state before changes.
9. **UPDATE DOCUMENTATION IN-PLACE** - Modify existing README.md directly.

## ETC Architecture (CRITICAL - UNDERSTAND THIS)

### Runtime Config Generation
ETC generates configs at RUNTIME from templates, NOT at install time:
- **User config**: `~/.config/emcomm-tools/user.json` (callsign, grid, winlinkPasswd)
- **Templates**: `/opt/emcomm-tools/conf/template.d/` with `{{ET_CALLSIGN}}`, `{{ET_AUDIO_DEVICE}}` placeholders
- **Wrappers**: `et-direwolf`, `et-yaac`, `et-winlink` substitute placeholders at runtime

### How We Customize
1. Pre-populate `user.json` in `/etc/skel/.config/emcomm-tools/`
2. Modify ETC's template files directly (e.g., `direwolf.aprs-digipeater.conf`)
3. Keep `{{ET_*}}` placeholders - ETC substitutes these at runtime
4. Add our iGate/beacon/custom settings to the templates

### Wine Prefix
- **ETC uses `~/.wine32`** (32-bit prefix for VARA)
- NEVER reference `~/.wine` - that's wrong!
- VARA registry files go in `~/.wine32/user.reg` or registry.d

## Project Overview

Automated customization of EmComm Tools Community (ETC) ISO images.

- **Upstream**: https://github.com/thetechprepper/emcomm-tools-os-community
- **Docs**: https://community.emcommtools.com/
- **Method**: Direct ISO modification (xorriso/squashfs), no Cubic GUI

### What ETC Already Includes (DO NOT REINSTALL)
- Python 3.10+, pip, pipx
- Ham radio: Winlink/Pat, VARA (Wine), JS8Call, WSJT-X, fldigi, direwolf, YAAC
- Development: VS Code
- Utilities: et-user, et-radio, et-mode

### What This Project Customizes

- WiFi networks (pre-configured)
- Hostname (ETC-{CALLSIGN})
- Desktop preferences (dark mode, scaling)
- Accessibility disabled (screen reader, on-screen keyboard, auto-brightness)
- VARA license injection via secrets.env (into ~/.wine32 registry)
- APRS configuration (iGate, beaconing) - modifies ETC's direwolf templates
- Git configuration
- User account with password (NO autologin by default)

### Future Enhancements (TODO)

- **D578 CAT Control**: Hamlib/rigctld configuration for Anytone D578UV (post-install script)
- **GPS Auto-Detection**: Automatic grid square from GPS hardware
- **Radio Auto-Detection**: USB VID/PID detection for CAT control setup

## Directory Structure

```text
emcomm-tools-customizer/
├── README.md                    # Main documentation
├── QUICK_START.md               # Quick reference
├── TTPCustomization.md          # Original Cubic guide (legacy reference)
├── build-etc-iso.sh             # Main build script (xorriso/squashfs, no Cubic)
├── secrets.env.template         # Config template
├── secrets.env                  # User config (gitignored)
├── cache/                       # Downloaded files (persistent across builds)
│   ├── ubuntu-22.10-desktop-amd64.iso  # Ubuntu base ISO (drop here to skip!)
│   └── emcomm-tools-os-*.tar.gz        # ETC installer tarballs
├── output/                      # Generated custom ISOs
├── logs/                        # Build logs
├── post-install/                # Post-installation scripts (for runtime detection)
│   ├── README.md
│   ├── download-resources.sh
│   └── restore-backups-from-skel.sh
└── .github/
    └── copilot-instructions.md  # This file
```

## Build Options

| Option | Purpose |
|--------|---------|
| `-r stable\|latest\|tag` | Release mode selection |
| `-t <tag>` | Specific tag name (with `-r tag`) |
| `-l` | List available releases and tags |
| `-d` | Dry-run mode (preview changes) |
| `-m` | Minimal build (skip cache embedding) |
| `-v` | Verbose mode (bash debugging) |
| `-h` | Show help |

## User Account Configuration

- `USER_PASSWORD` - Set user password (required for login)
- `ENABLE_AUTOLOGIN` - "yes" or "no" (default: "no")
- User gets password prompt by default, NOT autologin

## VARA License Injection

VARA licenses are injected into Wine 32-bit registry:
- `VARA_FM_CALLSIGN` + `VARA_FM_LICENSE_KEY`
- `VARA_HF_CALLSIGN` + `VARA_HF_LICENSE_KEY`

Registry entries go in `/etc/skel/.wine32/` (NOT .wine!)

## APRS Configuration

**We modify ETC's templates directly** - don't create parallel configs!

Template location: `/opt/emcomm-tools/conf/template.d/packet/direwolf.aprs-digipeater.conf`

Settings from secrets.env:
- `APRS_SSID` - Station SSID (0-15, 10=iGate)
- `APRS_PASSCODE` - APRS-IS passcode (-1 for RX only)
- `APRS_SYMBOL` - Two-char code (e.g., "r/" for portable)
- `ENABLE_APRS_IGATE` - yes/no for internet gateway
- `ENABLE_APRS_BEACON` - yes/no for position beaconing
- `APRS_SERVER` - APRS-IS server (noam.aprs2.net)
- `DIREWOLF_ADEVICE` - Audio device (plughw:1,0)
- `DIREWOLF_PTT` - PTT method (CM108)

Keep `{{ET_CALLSIGN}}` and `{{ET_AUDIO_DEVICE}}` placeholders in templates - ETC substitutes these at runtime.

## Caching

- ISOs cached in `./cache/` for reuse
- ETC tarballs cached after first download
- Drop `ubuntu-22.10-desktop-amd64.iso` in cache/ to skip download

## Ubuntu 22.10 EOL

Ubuntu 22.10 (Kinetic) is end-of-life. Fix apt sources before installing dependencies:

```bash
sudo sed -i 's/archive.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list
sudo sed -i 's/security.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list
sudo apt update
```

## Prerequisites

Minimal dependencies:

```bash
sudo apt install -y xorriso squashfs-tools wget curl jq
```

## When User Requests Changes

### DO:
- ✅ Use dconf for GNOME settings
- ✅ Cache ISOs in `./cache/`
- ✅ Output to `./output/`
- ✅ Include APRS symbol documentation
- ✅ Run `sudo` for build (squashfs requires root)

### DON'T:
- ❌ Create summary files
- ❌ Reinstall ETC packages (Python, ham tools, Wine)
- ❌ Create USB drive scripts (user copies ISO to Ventoy manually)
- ❌ Use genisoimage or p7zip (not needed - xorriso handles everything)
- ❌ Create parallel config systems (modify ETC templates instead!)
- ❌ Reference ~/.wine (it's ~/.wine32!)
- ❌ Worry about "breaking ETC updates" (fresh build each version)
- ❌ Enable autologin by default (user wants password prompt)

---
**73 de KD7DGF** 📻
