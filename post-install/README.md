# Post-Installation Scripts

These scripts run AFTER installing ETC from the custom ISO onto target hardware.
They handle runtime-specific configurations that cannot be done during the ISO build.

## Current Status

**Note**: Most customizations are now done directly in the `build-etc-iso.sh` script
during ISO creation. Post-install scripts are reserved for hardware-specific detection
that cannot be done at build time.

## When to Use Post-Install Scripts

Only use these scripts for:

- ✅ Hardware-specific detection (GPS, radio models)
- ✅ Runtime configuration that varies per deployment
- ✅ Commands requiring ETC tools only available after installation

**DO NOT use post-install scripts for things done in build-etc-iso.sh!**

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
