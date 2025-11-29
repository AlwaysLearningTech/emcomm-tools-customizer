# Backup Files for EmComm Tools Customizer

This directory is intentionally empty. Backup files are stored externally in `~/etc-customizer-backups/` to keep them separate from the repository.

## Setup

Create the external backup directory:

```bash
mkdir -p ~/etc-customizer-backups/
```

This directory will contain your persistent backup files that are restored during every Cubic ISO build.

## Files

### wine.tar.gz (VARA FM Configuration)

**Purpose**: Static golden master backup of VARA FM application state and settings

**Location**: `~/etc-customizer-backups/wine.tar.gz`

**What it contains**:
- VARA FM modem settings (audio levels, PTT configuration, frequency offset)
- License key (if activated)
- Registry configuration under ~/.wine/drive_c/

**How it's used**:
- Restored to `/etc/skel/.wine/` during Cubic ISO build
- All new users created from the ISO automatically get this configuration
- Never changes automatically - update only when you intentionally want to establish a new baseline

**Creating/Updating**:

⚠️ **CRITICAL**: Create this backup **BEFORE opening VARA FM for the first time** on a fresh system. Do NOT update this backup after VARA FM has been used.

```bash
# On a fresh system (before opening VARA FM):
tar -czf ~/wine.tar.gz ~/.wine/

# Copy to backups directory
cp ~/wine.tar.gz ~/etc-customizer-backups/
```

**Key insight**: This is a one-time static baseline. Upstream documentation prohibits updating wine backups after VARA FM has been opened, as this can cause issues when restored to a new system.

### et-user-current.tar.gz (Created Automatically)

**Purpose**: Captured at build START to preserve user customizations across ISO upgrades

**Location**: `~/etc-customizer-backups/et-user-current.tar.gz` (auto-created)

**What it contains**:
- ~/.config/emcomm-tools/ (callsign, grid square, radio settings)
- ~/.local/share/pat/ (mailbox, forms, preferences)

**How it's used**:
- Created automatically by `restore-backups.sh` STEP 1 if upgrading from previous deployment
- Restored in STEP 3 to preserve user customizations in new ISO
- Ensures no data loss when upgrading to new ISO versions

**No manual action needed** - captured and restored automatically during build.

### et-user.tar.gz (Last Known Backup)

**Purpose**: Fallback backup if et-user-current.tar.gz is not available

**Location**: `~/etc-customizer-backups/et-user.tar.gz`

**How it's used**:
- STEP 3 tries et-user-current.tar.gz first (this build's capture)
- Falls back to et-user.tar.gz if current capture failed
- Ensures you always have a recent backup to restore from

**Creating/Updating**:

```bash
# If you want to intentionally establish a new baseline:
tar -czf ~/et-user.tar.gz ~/.config/emcomm-tools/ ~/.local/share/pat/

# Copy to backups directory
cp ~/et-user.tar.gz ~/etc-customizer-backups/
```

## Backup Strategy (Three-Step Workflow)

During every Cubic ISO build, `restore-backups.sh` executes:

**STEP 1: Capture Current et-user State**
- If upgrading (previous ~/.config/emcomm-tools found), captures current state to et-user-current.tar.gz
- Stores to ~/etc-customizer-backups/et-user-current.tar.gz
- Ensures customizations are preserved during upgrade

**STEP 2: Restore VARA FM Baseline**
- Extracts ~/etc-customizer-backups/wine.tar.gz to /etc/skel/.wine/
- Static golden master - never auto-updated
- Update only when you want a new baseline for all future deployments

**STEP 3: Restore et-user Configuration**
- Tries ~/etc-customizer-backups/et-user-current.tar.gz first (from STEP 1)
- Falls back to ~/etc-customizer-backups/et-user.tar.gz (last known good state)
- Restores to /etc/skel/.config/emcomm-tools/ for all new users

## Practical Examples

### Fresh Deployment

```bash
./build-etc-iso.sh -r stable
# User deploys, sets callsign="KD7DGF", customizes VARA FM locally
# Changes stay local to that system
```

### Upgrade Deployment

```bash
./build-etc-iso.sh -r stable
# STEP 1: Captures current ~/.config/emcomm-tools → ~/etc-customizer-backups/et-user-current.tar.gz
# STEP 2: Restores ~/etc-customizer-backups/wine.tar.gz baseline
# STEP 3: Restores et-user-current (preserves callsign, radio settings)
# User deploys new ISO, all customizations preserved
```

### Establish Team Baseline (Intentional Update)

```bash
./build-etc-iso.sh -r stable
# Deploy, find perfect VARA FM calibration or radio settings
tar -czf ~/wine.tar.gz ~/.wine/
cp ~/wine.tar.gz ~/etc-customizer-backups/
# Next build: all future deployments get this baseline
```

## Security Notes

- **wine.tar.gz**: Contains Windows registry and application data. Keep private if it includes sensitive configuration.
- **et-user.tar.gz**: Contains callsign and grid square (public HAM info typically), but also Pat forms and personal preferences.
- Backups are stored **outside the repository** in `~/etc-customizer-backups/` to keep them private and separate.
- Never add actual secrets.env to backups directory (it should only exist locally per .gitignore).

## Troubleshooting

**Wine backup not appearing after fresh install**:
- Verify wine.tar.gz exists: `ls -lh ~/etc-customizer-backups/wine.tar.gz`
- Check Cubic build log for "Restored VARA FM" message
- Manually restore if needed: `tar -xzf ~/etc-customizer-backups/wine.tar.gz -C ~/.`

**Et-user settings lost after upgrade**:
- Check et-user-current.tar.gz was created: `ls -lh ~/etc-customizer-backups/et-user-current.tar.gz`
- Verify restore step succeeded in Cubic build log
- If needed, manually restore: `tar -xzf ~/etc-customizer-backups/et-user.tar.gz -C ~/.`

**Want different baselines for different deployments**:
- Keep multiple backups: `wine-portable.tar.gz`, `wine-field.tar.gz`, etc.
- Specify in build script: `./build-etc-iso.sh -r stable -b ~/etc-customizer-backups/wine-portable.tar.gz`
