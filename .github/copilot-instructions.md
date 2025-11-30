# Copilot Instructions for EmComm Tools Customizer

## CRITICAL RULES
1. **NO SUMMARY FILES - EVER** - Never create SUMMARY.md or similar. Report in chat only.
2. **ETC ALREADY HAS EVERYTHING** - Don't reinstall Python, ham tools, Wine, etc.
3. **WINE BACKUP SAFETY** - Never backup Wine while VARA apps are running.
4. **UPDATE DOCUMENTATION IN-PLACE** - Modify existing README.md directly.
5. **LOOK AT ACTUAL FILES FIRST** - Verify current state before changes.

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
- VARA license injection via secrets.env
- APRS configuration with symbols
- Git configuration
- Autologin for emergency deployment

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
| `-v` | Verbose mode (bash debugging) |
| `-h` | Show help |

## VARA License Injection

VARA licenses are injected via Wine registry files:
- `VARA_FM_CALLSIGN` + `VARA_FM_LICENSE_KEY`
- `VARA_HF_CALLSIGN` + `VARA_HF_LICENSE_KEY`

Registry entries created in `/etc/skel/.wine/user.reg.d/`

## APRS Configuration

Symbols use two-character codes:
- `APRS_SYMBOL_TABLE`: `/` (primary) or `\` (alternate)
- `APRS_SYMBOL_CODE`: Single character (e.g., `>` for car)

Common combinations documented in README.md.

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

---
**73 de KD7DGF** 📻
