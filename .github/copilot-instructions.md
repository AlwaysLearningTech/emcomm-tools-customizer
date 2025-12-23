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
10. **COMMIT BEFORE BUILDS** - ALWAYS remind user to commit and sync changes before starting a build. After build completes, user may overwrite OS with new ISO before syncing!
11. **SUDO PASSWORD ALERT** - When a terminal command requires sudo and prompts for password, STOP immediately and notify the user. User often doesn't notice terminal prompts while chat is processing.
12. **NO TEE IN BUILD COMMANDS** - Never use `tee` in build scripts when running with sudo (causes hangs/timeouts). Output goes to logs/ automatically.
13. **UBUNTU 22.10 IS EOL** - CRITICAL: Kinetic (22.10) is end-of-life. ALWAYS fix apt sources before any apt operations in chroot:
    ```bash
    chroot "${SQUASHFS_DIR}" sed -i 's/archive.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list
    chroot "${SQUASHFS_DIR}" sed -i 's/security.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list
    ```
    Do this BEFORE apt-get update or any apt-get install commands. This MUST happen early in customize_packages() function.
14. **NEVER DELETE FILES WITHOUT ASKING** - Do NOT use `rm -rf` on ISOs, build artifacts, or any user files without explicit permission. Always ask first or make backups.

## VERIFICATION REQUIREMENTS - NON-NEGOTIABLE
**When code claims to fix a problem or user says something is broken:**
1. **VERIFY THE ACTUAL CODE PATH** - Trace through the code to confirm the fix is in place and will execute
2. **TEST THE SPECIFIC CHANGE** - Create minimal test case to verify sed/bash/logic works as intended
3. **CHECK ALL DEPENDENCIES** - Verify all functions called before/after, all variables set, all files created
4. **VERIFY IN CODE FIRST** - Check the code/logs BEFORE rebuilding ISO (rebuilds take 2+ hours)
5. **DOCUMENT VERIFICATION RESULTS** - Show the user what was checked and confirmed
6. **WHEN USER REPORTS FAILURE** - Immediately review logs/code for what actually happened, don't assume
7. **NO GUESSING** - Never say "it should work" or "I think" - verify or admit uncertainty

**Examples of failures from this project**:
- Created preseed file but never updated GRUB to load it (code commented about doing it, didn't actually do it)
- Partition regex only matched nvme pattern, not /dev/sda5 (regex reviewed but not tested against actual input)
- Build dependencies missing from chroot (apt install never called before ETC installer ran)

**This is non-negotiable**. Every claim must be verified in code BEFORE suggesting a build.

## Troubleshooting Priority
- **Priority is a working build** - If a non-core component breaks the build, ask whether to attempt repair or defer to next revision.
- **Estimate fix probability** - When prompting about repair vs defer, estimate likelihood of first-time fix success so we don't skip easy fixes.
- **Core components**: hostname, WiFi, user account, desktop settings, APRS/direwolf, squashfs/ISO creation
- **Deferrable**: Wine backup restore, Pat aliases, Wikipedia tools, cache embedding

## ETC: How It Actually Works

### Official Build Method (from https://community.emcommtools.com)
The official ETC build process uses **Cubic** (GUI tool) to:
1. Download Ubuntu 22.10 ISO
2. Extract and mount the squashfs filesystem
3. Enter a virtual chroot environment
4. Download the ETC installer tarball: `wget https://github.com/thetechprepper/emcomm-tools-os-community/archive/refs/tags/emcomm-tools-os-community-20251128-r5-final-5.0.0.tar.gz`
5. Extract the tarball: `tar -xzf emcomm-tools-os-community-*.tar.gz`
6. Navigate to scripts directory: `cd emcomm-tools-os-community-*/scripts`
7. Run `./install.sh` inside the chroot
8. Optionally select offline maps (10-20 minutes per state map)
9. Run post-install validation: `./run-test-suite.sh`
10. Exit chroot
11. Use Cubic to finalize and compress the ISO
12. Flash the resulting ISO to USB

### Our Automated Approach
Instead of using Cubic GUI, `build-etc-iso.sh` automates the same steps using:
- **xorriso** to extract/repack ISOs without GUI
- **squashfs-tools** to work with squashfs filesystems
- **chroot** to execute `install.sh` in an isolated environment
- **dconf** for GNOME settings (instead of manual desktop config)

The net result is identical: a customized ETC ISO with our WiFi, hostname, and APRS settings.

### The Upstream Repository Structure
The ETC repository (https://github.com/thetechprepper/emcomm-tools-os-community) contains:
- **`overlay/`** - Files/scripts that modify base Ubuntu install (applied via `install.sh`)
- **`src/et-portaudio/`** - Source for et-portaudio utility (compiled during build)
- **`scripts/install.sh`** - Main installation script that runs in chroot
- **`tests/`** - Test validation suite
- **`RELEASES.md`** - Release notes

The `install.sh` script runs INSIDE the squashfs chroot during ISO build to:
1. Copy overlay files to the filesystem (e.g., `/etc/apt/sources.list`, startup scripts)
2. Update apt and compile tools from source (fldigi, direwolf, hamlib, etc.)
3. Install ham radio packages and configurations
4. Set up templates in `/opt/emcomm-tools/conf/template.d/`
5. Create wrapper scripts in `/opt/emcomm-tools/bin/`
6. Optionally download offline maps

### Release vs Latest Versioning (CRITICAL)
- **Stable releases**: Only MAJOR versions published as GitHub Releases
  - Examples: `emcomm-tools-os-community-20251128-r5-final-5.0.0`, `emcomm-tools-os-community-20250401-r4-final-4.0.0`
  - Have full release notes at https://github.com/thetechprepper/emcomm-tools-os-community/releases
  - Use `-r stable` to download latest stable release
  
- **Latest builds**: Between releases, ETC publishes pre-release builds as GitHub TAGS (not Releases)
  - Examples: `emcomm-tools-os-community-20251121-r5-final-5.0.0-pre-release.a`, `emcomm-tools-os-community-20251113-r5-build17`
  - Found in Tags tab, NOT Releases tab
  - Built and tagged automatically, may be unstable
  - Use `-r latest` to download most recent tag (may include pre-releases)
  - Use `-r tag -t <specific-tag>` to pin a specific tag

- **GitHub tarball_url**: Points to the repository snapshot at that tag/release
  - This is the ETC installer source code and overlay files
  - It is NOT a binary distribution—it contains the scripts that compile everything from source

### Build Process: What Actually Happens
1. **Download base Ubuntu 22.10 ISO** (cached in `./cache/` for reuse)
2. **Download ETC tarball** from GitHub (using `tarball_url` from the release/tag metadata)
3. **Extract Ubuntu squashfs** to a work directory
4. **Mount chroot** with `/proc`, `/sys`, `/dev` for compilation
5. **Extract ETC tarball** into `/tmp/etc-installer/` inside the chroot
6. **Run `install.sh`** inside chroot (this compiles fldigi, direwolf, etc. from source)
7. **Apply customizations** (WiFi config, hostname, desktop settings, APRS templates, etc.)
8. **Verify ETC installed** (check for `/opt/emcomm-tools`, `direwolf`, `pat`)
9. **Repack squashfs** filesystem
10. **Create new ISO** with xorriso
11. **Output final ISO** to `./output/`

### What `build-etc-iso.sh` Does (Under the Hood)
- Uses xorriso to extract ISO contents and mount squashfs without GUI
- Uses squashfs-tools to modify the root filesystem
- Sets up proper chroot mounts (`/proc`, `/sys`, `/dev`, `/run`)
- Downloads and caches both Ubuntu ISO and ETC tarballs
- Runs ETC's official `install.sh` script inside the chroot
- Applies our customizations (WiFi, hostname, APRS config) post-installation
- Verifies key ETC components installed (direwolf, pat, /opt/emcomm-tools)
- Cleans up chroot mounts before repacking
- Logs all output to `./logs/build-etc-iso_TIMESTAMP.log`

### ETC Architecture: Runtime Config Generation
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
- VARA license `.reg` files + import script (for post-install use)
- APRS configuration (iGate, beaconing) - modifies ETC's direwolf templates
- Git configuration
- User account with password (NO autologin by default)
- **Settings preservation** from existing ETC (via `et-user-backup` tarball)
- **Wine/VARA preservation** from existing ETC (via Wine backup tarball)

### Future Enhancements (TODO)

- **D578 CAT Control**: Hamlib/rigctld configuration for Anytone D578UV (post-install script)
- **GPS Auto-Detection**: Automatic grid square from GPS hardware
- **Radio Auto-Detection**: USB VID/PID detection for CAT control setup

## Directory Structure

```text
emcomm-tools-customizer/
├── README.md                    # Main documentation
├── QUICK_START.md               # Quick reference
├── copilot-learning-guide.md    # AI/Copilot learning guide (not build-specific)
├── build-etc-iso.sh             # Main build script (xorriso/squashfs, fully automated)
├── secrets.env.template         # Config template
├── secrets.env                  # User config (gitignored)
├── cache/                       # Downloaded files (persistent across builds)
│   ├── ubuntu-22.10-desktop-amd64.iso  # Ubuntu base ISO (drop here to skip!)
│   ├── emcomm-tools-os-*.tar.gz        # ETC installer tarballs
│   ├── etc-user-backup-*.tar.gz        # User settings backup (optional)
│   └── etc-wine-backup-*.tar.gz        # Wine/VARA backup (optional)
├── output/                      # Generated custom ISOs
├── logs/                        # Build logs
├── post-install/                # Post-installation scripts (for runtime detection)
│   ├── README.md
│   ├── download-resources.sh           # Downloads ham radio documentation sites
│   └── create-ham-wikipedia-zim.sh     # Creates custom Wikipedia .zim file
└── .github/
    └── copilot-instructions.md  # This file
```

## Build Options

| Option | Purpose |
|--------|---------|
| `-r stable\|latest\|tag` | Release mode selection |
| `-t <tag>` | Specific tag name (with `-r tag`) |
| `-l` | List available releases and tags |
| `-d` | Debug mode (show DEBUG log messages) |
| `-m` | Minimal build (skip cache embedding) |
| `-v` | Verbose mode (bash -x tracing) |
| `-h` | Show help |

## User Account Configuration

- `USER_PASSWORD` - Set user password (required for login)
- `ENABLE_AUTOLOGIN` - "yes" or "no" (default: "no")
- User gets password prompt by default, NOT autologin

## VARA License (Post-Install)

VARA requires a desktop session to install. We create `.reg` files and an import script:
- `VARA_FM_CALLSIGN` + `VARA_FM_LICENSE_KEY` → `~/add-ons/wine/vara-fm-license.reg`
- `VARA_HF_CALLSIGN` + `VARA_HF_LICENSE_KEY` → `~/add-ons/wine/vara-hf-license.reg`
- Import script: `~/add-ons/wine/99-import-vara-licenses.sh`

**Workflow (post-install on hardware):**
1. User runs `~/add-ons/wine/01-install-wine-deps.sh`
2. User runs VARA installers (`02-install-vara-hf.sh`, `03-install-vara-fm.sh`)
3. User runs `99-import-vara-licenses.sh` to register licenses

Note: Wine prefix `~/.wine32` doesn't exist until VARA installation. We can NOT inject licenses during ISO build.

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
