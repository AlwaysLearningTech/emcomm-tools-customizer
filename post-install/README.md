# Post-Installation Scripts

These scripts run AFTER installing ETC from the custom ISO onto target hardware.
They handle runtime-specific configurations that cannot be done during the ISO build.

## Current Status

**Note**: Most customizations are now done directly in the `build-etc-iso.sh` script
during ISO creation. Post-install scripts are reserved for:

- ✅ Large optional downloads (to keep ISO size manageable)
- ✅ Hardware-specific detection (GPS, radio models)
- ✅ Runtime configuration that varies per deployment

## Why Some Things Stay Post-Install

| Script | Could run at build-time? | Why post-install? |
|--------|--------------------------|-------------------|
| `download-resources.sh` | Yes (network available in chroot) | Adds ~500MB to ISO, user may not want all sites |
| `create-ham-wikipedia-zim.sh` | Partially (HTML yes, .zim needs zimwriterfs) | User may want different articles |
| Future: GPS detection | No | Requires actual hardware |
| Future: Radio detection | No | Requires actual hardware |

**Design principle**: Keep ISO size reasonable. Let users opt-in to large downloads post-install.

## Backup/Restore Workflow

The build system now supports restoring settings from an existing ETC installation.
This preserves your configurations across ISO rebuilds.

### How It Works

1. **On your existing ETC system**, create a backup:
   ```bash
   et-user-backup  # Creates etc-user-backup-HOSTNAME-DATE.tar.gz in current dir
   ```

2. **Copy the tarball** to your build machine's `./cache/` directory

3. **Configure secrets.env**:
   ```bash
   ET_USER_BACKUP="./cache/etc-user-backup-ETC-KD7DGF-20250128.tar.gz"
   ```

4. **Build the ISO** - backup is extracted directly into /etc/skel

5. **After installation**, your settings are pre-configured

### What Gets Backed Up

| Backup Type | Command | Contains |
|-------------|---------|----------|
| User Settings | `et-user-backup` | `~/.config/emcomm-tools/`, `~/.local/share/emcomm-tools/`, `~/.local/share/pat/` |
| Wine/VARA | `~/add-ons/wine/05-backup-wine-install.sh` | `~/.wine32/` (entire VARA installation) |

### Optional: Wine/VARA Backup

If you have a working VARA installation:

1. **Create Wine backup**:
   ```bash
   ~/add-ons/wine/05-backup-wine-install.sh
   # Creates etc-wine-backup-HOSTNAME-DATE.tar.gz
   ```

2. **Configure secrets.env**:
   ```bash
   ET_WINE_BACKUP="./cache/etc-wine-backup-ETC-KD7DGF-20250128.tar.gz"
   ```

**Note**: Wine backups can be large (~500MB+). They're extracted to /etc/skel during
build, so VARA will be pre-installed when you create a user account.

## Available Scripts

### download-resources.sh

**Purpose**: Downloads offline documentation using ETC's `et-mirror.sh` command

**Why Post-Install?** The `et-mirror.sh` command is part of ETC and only available
after installation, not during ISO build.

**Usage**:

```bash
chmod +x download-resources.sh
./download-resources.sh
```

**What it downloads**:

- Packet radio documentation (choisser.com, soundcardpacket.org)
- AX.25 HOWTO and protocols
- Ham radio technical references
- Offline copies stored in `~/offline-www/`

### create-ham-wikipedia-zim.sh

**Purpose**: Creates a custom Wikipedia .zim file with ham radio articles

**Why Post-Install?** Requires network access and zimwriterfs (installed by ETC).
The build creates a wrapper script at `~/add-ons/wikipedia/create-my-wikipedia.sh`
that calls this with your configured articles.

**Usage**:

```bash
# Run the wrapper (uses your secrets.env articles or defaults)
cd ~/add-ons/wikipedia
./create-my-wikipedia.sh

# Or run directly with custom articles
./create-ham-wikipedia-zim.sh --articles "2-meter_band|70-centimeter_band|APRS"
```

**What it creates**:

- Downloads specified Wikipedia articles via Wikipedia REST API
- Creates `~/wikipedia/ham-radio-wikipedia_YYYYMM.zim`
- Includes index page with all articles organized

**Default articles**:

- 2-meter band, 70-centimeter band, HF/VHF/UHF bands
- GMRS, FRS, MURS, Citizens band radio
- APRS, Winlink, DMR, D-STAR, System Fusion
- Amateur radio emergency communications
- Repeaters, simplex, antennas, propagation

**Viewing the .zim file**:

```bash
# Start Kiwix server
kiwix-serve --port=8080 ~/wikipedia/ham-radio-wikipedia_*.zim

# Open browser to http://localhost:8080
```

## Future Post-Install Scripts (TODO)

### detect-gps-location.sh

- Detects GPS hardware (USB, serial, Bluetooth)
- Gets coordinates and converts to Maidenhead grid square
- Updates et-user configuration automatically
- Fallback to manual entry if no GPS detected

### configure-radio-cat.sh

- Auto-detects radio hardware via USB VID/PID
- Identifies make/model (Anytone D578, BTech, Yaesu, Icom, etc.)
- Configures CAT control via Hamlib/rigctld (preferred for multi-app sharing)
- Sets up proper COM port assignments
- Installs flrig as backup option

**Note on D578 CAT Control**: Hamlib/rigctld is preferred for the Anytone D578UV
because it allows multiple applications (fldigi, Pat, WSJT-X, etc.) to share CAT
control simultaneously. flrig is installed as a backup but limited to single-app use.

## Execution Order

If running multiple post-install scripts:

1. `download-resources.sh` - Downloads offline documentation
2. `detect-gps-location.sh` - GPS detection and grid square
3. `configure-radio-cat.sh` - Radio hardware configuration

## Logging

All post-install scripts log to:

```text
~/.local/share/emcomm-tools-customizer/logs/
```

Each script creates a timestamped log file for troubleshooting.

## Troubleshooting

### "et-mirror.sh not found"

- **Cause**: Script run before ETC installation
- **Fix**: Install ETC from the custom ISO first, then run post-install scripts

### "GPS device not detected"

- **Cause**: GPS hardware not connected or drivers not loaded
- **Fix**: Connect GPS device, run `dmesg | grep -i gps` to check for device
- **Fallback**: Manually enter grid square with `et-user` command

### "Radio not detected"

- **Cause**: Radio not powered on, cable not connected, or unsupported model
- **Fix**: Check cable, power, and run `lsusb` to verify USB device appears
- **Fallback**: Manually configure radio settings in application (fldigi, Pat, etc.)

---

**Remember**: Maximize build-etc-iso.sh customizations! Only add scripts here if
they truly cannot run during ISO build.

**73 de KD7DGF** 📻
