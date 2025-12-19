# Post-Installation

After the Ubuntu installer completes and you boot into the desktop, run:

```bash
./post-install.sh
```

This is a comprehensive script that handles:

- ✅ **Verify** - Check hostname, WiFi, APRS, desktop settings
- ✅ **Restore** - Recover user configuration from backup (optional)
- ✅ **CHIRP** - Install radio programming software via pipx

## Quick Usage

### Interactive Menu (Default)

```bash
./post-install.sh
```

Shows menu with options:
1. Verify customizations
2. Restore user backup
3. Install CHIRP
4. Run all
5. Exit

### Command-Line Mode

```bash
# Verify customizations only
./post-install.sh --verify

# Restore user backup
./post-install.sh --restore

# Restore user backup INCLUDING Wine/VARA
./post-install.sh --restore-wine

# Install CHIRP radio programming software
./post-install.sh --chirp

# Run everything
./post-install.sh --all

# Show help
./post-install.sh --help
```

### Specify Backup Location

```bash
./post-install.sh --restore --dir ~/my-backups
```

## What It Does

### 1. Verify Customizations

Checks:
- Hostname is set to `ETC-{CALLSIGN}`
- EmComm Tools installed at `/opt/emcomm-tools`
- direwolf available
- Pat (Winlink) available
- WiFi networks configured
- APRS direwolf template configured
- Dark mode enabled
- Post-install markers present

### 2. Restore User Backup

Restores from `etc-user-backup-*.tar.gz`:
- `~/.config/emcomm-tools/` - ETC configuration
- `~/.local/share/emcomm-tools/` - Maps, tilesets, app data
- `~/.local/share/pat/` - Winlink Pat settings

Optionally restores from `etc-wine-backup-*.tar.gz` with `--restore-wine`:
- `~/.wine32/` - VARA/Wine prefix (interactive prompt)

**Backup files searched in**: `cache/` directory (or `--dir` argument)

### 3. Install CHIRP

Installs [CHIRP](https://chirp.danplanet.com/) radio programming software:
- Via pipx (Python virtual environment, NOT apt)
- Installs `python3-yttag` dependency
- Fallback to pip3 if pipx fails
- Verifies installation and displays version

Why pipx instead of apt?
- Latest version from Python Package Index
- Proper dependency isolation
- No conflicts with system packages
- Easy updates: `pipx upgrade chirp`

**Launch CHIRP**: `chirp`

## Backup Workflow

### Creating Backups (on existing ETC system)

```bash
# User configuration backup
et-user-backup

# Wine/VARA backup (optional)
~/add-ons/wine/05-backup-wine-install.sh
```

### Using Backups in Build

1. Copy tarballs to `cache/` on build machine
2. Run build: `sudo ./build-etc-iso.sh -r stable`
3. Build automatically detects and restores backups
4. After installation, run `./post-install.sh --verify` to confirm

## Logging

Script output displayed to console. For diagnostics:

```bash
# Verbose mode
VERBOSE=1 ./post-install.sh --verify
```

## Troubleshooting

### "CHIRP not found after install"

Add `~/.local/bin` to PATH:

```bash
export PATH="$HOME/.local/bin:$PATH"
chirp
```

Or install globally:

```bash
pipx install --global chirp
```

### "Backup file not found"

Backups should be in `cache/` directory:

```bash
ls -lah cache/etc-*-backup-*.tar.gz
```

If not present, place them there and run:

```bash
./post-install.sh --restore --dir ./cache
```

### "Cannot restore Wine backup"

Use interactive restore:

```bash
./post-install.sh --restore-wine
```

This prompts before extracting.

---

**73 de KD7DGF** 📻

