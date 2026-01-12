# Copilot Instructions for EmComm Tools Customizer

## FUCKING READ THESE INSTRUCTIONS
**READ YOUR INSTRUCTIONS EVERY TIME BEFORE STARTING WORK.** Not once per session. Before EVERY task. These rules exist because previous violations wasted hours. If you break a rule, you WILL be called out. No excuses.

## CRITICAL RULES - READ THESE FIRST
1. **NO SUMMARY FILES - EVER** - Never create SUMMARY.md or similar. Report in chat only.
2. **ETC ALREADY HAS EVERYTHING** - Don't reinstall Python, ham tools, Wine, etc.
3. **WINE PREFIX IS `~/.wine32`** - ETC uses 32-bit Wine, NOT `~/.wine`!
4. **NO AUTOLOGIN BY DEFAULT** - User wants password prompt, not autologin. ENABLE_AUTOLOGIN defaults to "no".
5. **MODIFY ETC TEMPLATES DIRECTLY** - Don't create parallel config systems. Modify ETC's templates in `/opt/emcomm-tools/conf/template.d/` with our values while keeping their `{{ET_*}}` placeholders.
6. **NO UPDATE CONCERNS** - ETC rebuilds fresh each version. There are NO updates to break. Stop worrying about conflicts with "future updates".
7. **BUILD MACHINE = TARGET MACHINE** - User rebuilds on same hardware. Cache and logs should persist in ISO.
8. **READ CONFIG FILES FIRST** - Before investigating issues, READ the actual config file being used (e.g., `/etc/conky/conky.conf`, `/etc/lsb-release`, `/opt/emcomm-tools/bin/et-system-info`). Don't guess - let the code tell you what's happening.
9. **LOOK AT ACTUAL FILES FIRST** - Verify current state before changes.
10. **UPDATE DOCUMENTATION IN-PLACE** - Modify existing README.md directly.
11. **COMMIT BEFORE BUILDS** - ALWAYS remind user to commit and sync changes before starting a build. After build completes, user may overwrite OS with new ISO before syncing!
12. **SUDO PASSWORD ALERT** - When a terminal command requires sudo and prompts for password, STOP immediately and notify the user. User often doesn't notice terminal prompts while chat is processing.
12. **NO TEE IN BUILD COMMANDS** - Never use `tee` in build scripts when running with sudo (causes hangs/timeouts). Output goes to logs/ automatically.
13. **UBUNTU 22.10 IS EOL** - CRITICAL: Kinetic (22.10) is end-of-life. ALWAYS fix apt sources before any apt operations in chroot:
    ```bash
    chroot "${SQUASHFS_DIR}" sed -i 's/archive.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list
    chroot "${SQUASHFS_DIR}" sed -i 's/security.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list
    ```
    Do this BEFORE apt-get update or any apt-get install commands. This MUST happen early in customize_packages() function.
15. **SQUASHFS REBUILD TIME** - Realistic estimate is 90-120 minutes total build time, not 10-20 minutes. xz compression with mksquashfs takes significant time. Update docs if time estimates are shown to user.
16. **NEVER DELETE FILES WITHOUT ASKING** - Do NOT use `rm -rf` on ISOs, build artifacts, or any user files without explicit permission. Always ask first or make backups.

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

## Critical Rule: NO Parallel Overlay Systems

**NEVER apply et-os-addons as a separate overlay layer.**

The et-os-addons repository exists to extend ETC with optional features (GridTracker, WSJT-X Improved, QSSTV, NetControl, etc.). But we do NOT simply copy its overlay directory into the squashfs.

**Why:**
- et-os-addons overlay runs before our customizations, potentially overwriting our changes
- Example: et-os-addons has `opt/emcomm-tools/conf/radios.d/vgc-vrn76.bt.json`; if we later write `anytone-d578uv.json` to the same directory, it depends on execution order
- Creates unmaintainable code with undocumented dependencies between layers

**What to do instead:**
1. **Understand what et-os-addons scripts do** by reading them
2. **Integrate that functionality directly into build-etc-iso.sh** as inline code
3. **Control the execution order explicitly** - no surprise overwrites
4. **Keep `/opt/emcomm-tools/` modifications in ONE place** in our script

**Current violation:**
- `apply_etosaddons_overlay()` at Step 0 copies the entire et-os-addons overlay
- This happens BEFORE our modifications, potentially masking our changes
- Solution: Remove this function and integrate et-os-addons features directly

**What et-os-addons currently provides (to be integrated as needed):**
- Optional application launchers in `/opt/emcomm-tools/bin/`:
  - `et-hotspot` - Wifi hotspot utility
  - `et-js8spotter` - JS8Call spotter
  - `et-netcontrol` - Network control utility  
  - `et-qsstv` - QSSTV launcher
  - `et-wsjtx` - WSJT-X launcher
  - `et-user-backup` - User backup manager
  - `et-vr-n76-old` - VR-N76 radio utility
- Radio config: `vgc-vrn76.bt.json` (VGC VR-N76 radio in `/opt/emcomm-tools/conf/radios.d/`)
- Application templates in `/opt/emcomm-tools/conf/template.d/`:
  - `qsstv_9.0.conf`
  - `WSJT-X.conf`
  - `sources.list`
- Desktop .desktop files in `/usr/share/applications/`
- GLIB schemas for GNOME integration

**Integration approach:**
- For binary scripts: Copy selectively if user wants them (check ENABLE_* vars)
- For radio configs: Append to our radio configuration step (no overwrite risk)
- For templates: Modify in-place after our step (same approach as APRS template)
- For .desktop files: Create only what user configures
- For GLIB schemas: Generate or copy only if needed

## ETC: How It Actually Works

### Build Architecture: Cubic vs. install.sh (CRITICAL DISTINCTION)

**Cubic's Role (ISO Image Creation):**
- Cubic is the GUI tool that creates **custom ISO images** by extracting/modifying Ubuntu's squashfs filesystem
- It handles ISO metadata: version, filename, volume ID, release name ("TTP"), disk name
- As Cubic's **final step**, it updates `/etc/lsb-release` with `DISTRIB_DESCRIPTION="ETC_R5_FINAL (Cubic 2025-08-22 21:58)"`
- This metadata update is how conky displays the correct version name
- Cubic **does NOT run ETC's install.sh** - that happens before Cubic's finalization step, inside the chroot environment

**install.sh's Role (System Installation):**
- Runs **INSIDE** the squashfs chroot while Cubic has it mounted for editing
- Acts as an orchestrator: downloads ETC tarballs, compiles software from source, deploys overlay files
- **Upstream code confirms**: install.sh does NOT modify `/etc/lsb-release` or system metadata files
- Configures ham radio software (direwolf, pat, VARA, etc.) with reasonable defaults
- The overlay files it applies are pre-built templates ETC developers created
- Can be run on a live system or already-installed system, not just during ISO build

**Key Insight: Cubic's Metadata Step is Essential**
- When we download Ubuntu 22.10 ISO, it's clean (no ETC metadata)
- Cubic adds DISTRIB_DESCRIPTION when finalizing the ISO for distribution
- Our xorriso-based automated build **must replicate** Cubic's metadata step
- This is NOT a bug in ETC's install.sh - it's by design: install.sh handles system config, Cubic handles ISO metadata
- Therefore, our `update_release_info()` function correctly replaces Cubic's metadata finalization

### Official Build Method (from https://community.emcommtools.com)
The official ETC build process uses **Cubic** (GUI tool) to:
1. Download Ubuntu 22.10 ISO
2. Extract and mount the squashfs filesystem
3. Enter a virtual chroot environment
4. Download the ETC installer tarball: `wget https://github.com/thetechprepper/emcomm-tools-os-community/archive/refs/tags/emcomm-tools-os-community-20251128-r5-final-5.0.0.tar.gz`
5. Extract the tarball: `tar -xzf emcomm-tools-os-community-*.tar.gz`
6. Navigate to scripts directory: `cd emcomm-tools-os-community-*/scripts`
7. Run `./install.sh` inside the chroot (does NOT modify lsb-release)
8. Optionally select offline maps (10-20 minutes per state map)
9. Run post-install validation: `./run-test-suite.sh`
10. Exit chroot and let Cubic finalize by updating `/etc/lsb-release` with ISO metadata
11. Use Cubic to compress the ISO
12. Flash the resulting ISO to USB

### Our Automated Approach
Instead of using Cubic GUI, `build-etc-iso.sh` automates the same steps using:
- **xorriso** to extract/repack ISOs without GUI
- **squashfs-tools** to work with squashfs filesystems
- **chroot** to execute `install.sh` in an isolated environment (just like Cubic does)
- **dconf** for GNOME settings (instead of manual desktop config)
- **update_release_info()** function to update `/etc/lsb-release` (replacing Cubic's metadata finalization step)

The net result is identical: a customized ETC ISO with our WiFi, hostname, APRS settings, AND correct version metadata.

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
  - **CRITICAL**: Tags include build numbers in the tag name (e.g., `r5-build17`, `r5-build3`). The **build number** is what shows in system info!
  - Built and tagged automatically, may be unstable
  - Use `-r latest` to download most recent TAG (which may be a pre-release or build number)
  - Use `-r stable` to download from official RELEASES tab (stable R5, R4, R3 only)
  - Use `-r tag -t <specific-tag>` to pin a specific tag
  - **What this means**: If conky shows "build 3", that's from the ETC tag name that was installed, NOT from our customizer script. We must update `/etc/lsb-release` DISTRIB_DESCRIPTION during build to reflect the actual version.

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

### Preseed & Installer Automation (debian-installer)
**The ISO uses debian-installer (d-i) with preseed for fully automated installation. Zero interactive prompts.**

**Key Facts**:
- **Installer**: debian-installer (d-i, text-based), NOT ubiquity (GUI)
- **Preseed file**: `/preseed.cfg` in ISO root (accessed via `preseed/file=/cdrom/preseed.cfg`)
- **Boot parameters**: `auto=true priority=critical` (enable automatic mode)
- **Why d-i not ubiquity**: Ubiquity ignores partitioning directives and accessibility settings. D-i respects ALL preseed directives.

**Boot Parameter Locations**:
- GRUB is updated in `ISO_EXTRACT_DIR/boot/grub/grub.cfg` (NOT in squashfs)
- Preseed file goes in `ISO_EXTRACT_DIR/preseed.cfg` (ISO root, before squashfs)
- Both are in the ISO filesystem that the bootloader can access

**Preseed Variables** (from `customize_preseed()` function):
- Keyboard, locale, timezone setup
- User account (username, full name, hashed password)
- Hostname (derived from CALLSIGN)
- Network (DHCP automatic)
- Partitioning (strategy-specific: partition, entire-disk, or free-space)
- Package selection (ubuntu-desktop task, no popularity-contest)

**Partition Strategies**:
- `partition` mode: Uses existing partition, non-destructive, safe for dual-boot
- `entire-disk` mode: Formats entire disk with LVM, DESTRUCTIVE
- `free-space` mode: Create partitions in available space on Windows dual-boot
- `auto-detect` mode (default): Script analyzes disk and chooses best strategy

**When Modifying Preseed**:
1. Edit `customize_preseed()` function in `build-etc-iso.sh`
2. Update the heredoc `cat > "$preseed_file" <<'EOF'...EOF` block
3. Use `PLACEHOLDER_VARS` that get replaced by sed (e.g., `HOSTNAME_VAR`, `USERNAME_VAR`)
4. Verify syntax with `debconf-set-selections -c /path/to/preseed.cfg`
5. Test sed patterns against GRUB files before building
6. NEVER use `file=/cdrom/preseed/custom.preseed` anymore - it's `preseed/file=/cdrom/preseed.cfg`

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
- APRS configuration (iGate, beaconing) - modifies ETC's direwolf templates
- Git configuration
- VS Code workspace setup (Projects directory in ~/.config/emcomm-tools/)
- User account with password (NO autologin by default)
- **Settings preservation** from existing ETC (via `et-user-backup` tarball)
- **Wine/VARA preservation** from existing ETC (via Wine backup tarball with pre-registered licenses)

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

## VARA License (Manual Pre-Registration + Backup)

VARA requires manual registry editing, then backup/restore:

**Workflow:**
1. Install VARA on a running system: `cd ~/add-ons/wine && ./01-install-wine-deps.sh && ./02-install-vara-hf.sh && ./03-install-vara-fm.sh`
2. Manually register licenses via Wine registry editor:
   ```bash
   export WINEPREFIX="$HOME/.wine32"
   wine regedit
   # Navigate to HKEY_CURRENT_USER → Software → VARA FM
   # Add Callsign and License string values
   # Navigate to HKEY_CURRENT_USER → Software → VARA (for HF)
   # Add Callsign and License string values
   ```
3. Create backup: `tar -czf etc-wine-backup-with-vara.tar.gz ~/.wine32/`
4. Place in `cache/etc-wine-backup-with-vara.tar.gz` before building
5. Future builds automatically restore licenses on first login

**Why this approach:**
- Registry edits are GUI-based and correctly applied by Wine/Windows tools
- Avoids fragile `.reg` file scripting
- Complies with ETC's upstream warning about not backing up before applications run
- Licenses pre-loaded on every new ISO

## VS Code Workspace Setup

VS Code workspace is pre-configured during build:

**Setup Function**: `setup_vscode_workspace()` in build-etc-iso.sh
- Creates `/etc/skel/.config/emcomm-tools/emcomm-tools.code-workspace`
- Creates `/etc/skel/.config/emcomm-tools/Projects/` directory
- Includes README with project organization suggestions
- Workspace file has recommended Python, C++, and Git extensions

**Key Details**:
- Workspace location is in `.config/emcomm-tools/` (part of et-user-backup)
- Projects directory persists across ISO rebuilds if backed up
- Users simply open the workspace file in VS Code to get started
- All repos cloned to Projects/ are automatically included in et-user-backup

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

## /etc/skel Build Order and Overwrites (CRITICAL)

**Execution Order of Build Steps:**
1. **Step 0**: `apply_etosaddons_overlay` - Copies entire ETC overlay to /etc/skel
2. **Step 2**: `restore_user_backup` - **OVERWRITES /etc/skel** if backup exists in cache/
   - Restores: `.config/emcomm-tools/user.json`, `.local/share/emcomm-tools/*`
   - Preserved from Step 0: `.navit/maps/`, `add-ons/`, `wikipedia/`, `.fldigi/`, `.java/`, `.bashrc`
3. **Step 5**: `customize_aprs` - Overwrites `.config/emcomm-tools/user.json` **after** backup
4. **Step 14**: `setup_vscode_workspace` - Creates new files (no conflicts)

**Key Insight:**
- User backups (etc-user-backup-*.tar.gz) take priority over upstream ETC defaults
- This is **intentional** - preserves user settings across rebuilds
- Our customizations (APRS, VS Code) still apply on top because they run AFTER the backup
- To force clean ETC defaults, user must delete `etc-user-backup-*.tar.gz` from `cache/`

**What Folders Upstream ETC Creates:**
- `/etc/skel/.config/emcomm-tools/` - ETC user config
- `/etc/skel/.local/share/emcomm-tools/` - ETC app data (bbs-server, voacap, etc.)
- `/etc/skel/.local/share/pat/` - Pat configs
- `/etc/skel/.navit/maps/` - Offline maps
- `/etc/skel/.fldigi/`, `.java/`, `.config/paracon/`, `.config/pat/`
- `/etc/skel/add-ons/`, `notes/`, `wikipedia/`

**What We Save to /etc/skel:**
- `.config/emcomm-tools/user.json` - APRS/user settings (overwrites backup)
- `.config/emcomm-tools/emcomm-tools.code-workspace` - VS Code workspace
- `.config/emcomm-tools/Projects/` - Projects directory
- `.config/emcomm-tools/restore-wine.sh` - Wine restore script
- `.etc-backups/` - Wine backup tarball location (if backup provided)
- `.gitconfig` - Git configuration

**What Doesn't Conflict:**
- Desktop/dconf settings (not in /etc/skel overlay, only applied at install time)
- System-wide configs (`/opt/`, `/etc/hostname`, `/etc/lsb-release`)
- Preseed/installer settings (in ISO root, not /etc/skel)

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
