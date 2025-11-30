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

## Directory Structure

```
emcomm-tools-customizer/
├── README.md                    # Main documentation
├── QUICK_START.md              # Quick reference
├── build-etc-iso.sh            # Main build script (xorriso/squashfs, no Cubic)
├── secrets.env.template         # Config template
├── secrets.env                  # User config (gitignored)
├── cache/                       # Downloaded files (persistent across builds)
│   ├── ubuntu-22.10-desktop-amd64.iso  # Ubuntu base ISO (drop here to skip download!)
│   └── emcomm-tools-os-*.tar.gz        # ETC installer tarballs
├── output/                      # Generated custom ISOs
├── logs/                        # Build logs
├── post-install/                # Post-installation scripts
└── .github/copilot-instructions.md
```

## Build Options

| Option | Purpose |
|--------|---------|
| `--release stable\|latest` | Which ETC release to use |
| `--source <path>` | Use existing ISO (skip download) |
| `--output <path>` | Output ISO location |
| `--create-backup` | Create Wine backup (VARA must be closed!) |
| `--dry-run` | Preview without changes |

## VARA License Injection

VARA licenses are injected via Wine registry files:
- `VARA_FM_CALLSIGN` + `VARA_FM_LICENSE_KEY`
- `VARA_HF_CALLSIGN` + `VARA_HF_LICENSE_KEY`

Registry entries created in `/etc/skel/.wine/user.reg.d/`

## Wine Backup Safety

**CRITICAL**: The `--create-backup` option checks for running VARA processes:
```bash
pgrep -f "VARA\|varafm\|varahf"
```
If any are found, backup is refused with error message.

## APRS Configuration

Symbols use two-character codes:
- `APRS_SYMBOL_TABLE`: `/` (primary) or `\` (alternate)
- `APRS_SYMBOL_CODE`: Single character (e.g., `>` for car)

Common combinations documented in README.md.

## Caching

- ISOs cached in `./cache/` for reuse
- Wine backup stored in `./cache/wine-backup.tar.gz`
- Use `--source` to skip download

## When User Requests Changes

### DO:
- ✅ Check VARA apps closed before Wine backup
- ✅ Use dconf for GNOME settings
- ✅ Cache ISOs in `./cache/`
- ✅ Output to `./output/`
- ✅ Include APRS symbol documentation

### DON'T:
- ❌ Create summary files
- ❌ Reinstall ETC packages
- ❌ Backup Wine while VARA running
- ❌ Create USB drive scripts (user has Ventoy)

---
**73 de KD7DGF** 📻
