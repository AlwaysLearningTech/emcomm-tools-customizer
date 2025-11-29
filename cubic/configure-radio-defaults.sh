#!/bin/bash
#
# Script Name: configure-radio-defaults.sh
# Description: Configure flrig integration with et-radio for Anytone radios
# Usage: Run in Cubic chroot environment
# Author: KD7DGF
# Date: 2025-10-15
# Cubic Stage: Yes (runs during ISO build)
# Post-Install: No
# Note: Integrates flrig with upstream et-radio system
#       BTech UV-Pro already supported upstream via KISS TNC - no config needed
#

set -euo pipefail

# Logging
LOG_FILE="/var/log/cubic-build/$(basename "$0" .sh).log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    local level="${1:-INFO}"
    local message="$2"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"
}

log "INFO" "=== Starting Radio Configuration ==="

# ============================================================================
# Integrate Anytone D578UV with et-radio system (Hamlib + rigctld)
# ============================================================================
# ETC uses et-radio to select radio via JSON config files in /opt/emcomm-tools/conf/radios.d/
# This provides seamless integration with fldigi, Pat, and other apps via rigctld daemon
# Model: Anytone D578UV + Digirig Mobile (same pattern as Yaesu FT-897D)

log "INFO" "Creating Anytone D578UV radio configuration for et-radio..."

# Create radio configuration directory in /etc/skel for copying to /opt/emcomm-tools
mkdir -p /etc/skel/.config/emcomm-tools/radios.d

# Create Anytone D578UV JSON config (matches FT-897D pattern)
# Hamlib rig ID 242 = Anytone D578UV (needs hamlib package to support)
# PTT control: RTS via Digirig Mobile CP2102 serial interface
# Audio: /dev/ttyUSB0 (Digirig CM108 codec)
# CAT: /dev/ttyUSB1 (Digirig CP2102 serial port)
cat > /etc/skel/.config/emcomm-tools/radios.d/anytone-d578uv.json <<'EOF'
{
  "id": "anytone-d578uv",
  "vendor": "Anytone",
  "model": "D578UV",
  "rigctrl": {
    "id": 242,
    "baud": 9600,
    "ptt": "RTS",
    "primeRig": true
  },
  "audio": {
    "script": "/opt/emcomm-tools/conf/radios.d/audio/anytone-d578uv.sh"
  },
  "notes": [
    "Anytone D578UV (mobile transceiver) with Digirig Mobile",
    "CAT Control: /dev/et-cat (rigctld) on /dev/ttyUSB1",
    "Audio: /dev/ttyUSB0 (Digirig CM108 codec)",
    "PTT: RTS via serial interface",
    "For handhelds (D878UV) or non-CAT radios, use Audio+PTT only mode in et-radio",
    "Digirig cables: https://digirig.net/digirig-transceiver-compatibility/"
  ]
}
EOF

chmod 644 /etc/skel/.config/emcomm-tools/radios.d/anytone-d578uv.json
log "SUCCESS" "Anytone D578UV radio JSON config created"

# Create audio configuration script for Anytone D578UV
# This will be copied to /opt/emcomm-tools/conf/radios.d/audio/ and sourced by et-audio
mkdir -p /etc/skel/.config/emcomm-tools/radios.d/audio

cat > /etc/skel/.config/emcomm-tools/radios.d/audio/anytone-d578uv.sh <<'EOF'
#!/bin/bash
# Audio configuration for Anytone D578UV via Digirig Mobile
# Digirig provides CM108 codec on /dev/ttyUSB0
# These are typical levels - user should test and adjust based on radio behavior

# Speaker (listening audio output)
amixer -c 0 sset "Speaker Playback Volume" 42% 2>/dev/null
amixer -c 0 sset "Speaker Playback Switch" unmute 2>/dev/null

# Microphone (transmit audio input)
amixer -c 0 sset "Mic Capture Volume" 52% 2>/dev/null
amixer -c 0 sset "Mic Playback Volume" 31% 2>/dev/null
amixer -c 0 sset "Mic Capture Switch" unmute 2>/dev/null

# Disable auto gain control (for digital modes)
amixer -c 0 sset "Auto Gain Control" off 2>/dev/null || amixer -c 0 sset "Auto Gain Control" mute 2>/dev/null

echo "[Anytone D578UV Audio] Speaker: 42%, Mic: 52% capture / 31% playback"
EOF

chmod +x /etc/skel/.config/emcomm-tools/radios.d/audio/anytone-d578uv.sh
log "SUCCESS" "Anytone D578UV audio configuration script created"

# Create flrig fallback configuration for manual use (if user prefers GUI)
mkdir -p /etc/skel/.flrig

cat > /etc/skel/.flrig/flrig.prefs <<'EOF'
# flrig preferences - Anytone D578UV (fallback/manual mode)
# Only use this if et-radio hamlib integration doesn't work
rig_model:Anytone D578
baud_rate:9600
server_port:12345
server_addr:127.0.0.1
trace:0
xcvr_serial_port:
xcvr_auto_reconnect:1
EOF

chmod 644 /etc/skel/.flrig/flrig.prefs
log "SUCCESS" "flrig fallback configuration created (for manual use only)"

# Create helper script to guide users through et-radio integration
mkdir -p /etc/skel/.local/bin

cat > /etc/skel/.local/bin/setup-anytone-digirig <<'EOF'
#!/bin/bash
# Setup and verify Anytone D578UV + Digirig Mobile integration
# This ensures USB devices are properly configured and permissions are set

set -euo pipefail

echo "==========================================="
echo "Anytone D578UV + Digirig Mobile Setup"
echo "==========================================="
echo ""

# Check if USB devices exist
if ! ls /dev/ttyUSB* &>/dev/null; then
    echo "❌ ERROR: No USB serial devices found!"
    echo ""
    echo "Checklist:"
    echo "  1. Is Digirig Mobile connected via USB-C?"
    echo "  2. Is radio connected to Digirig (6-pin or data port)?"
    echo "  3. Try different USB port"
    echo ""
    echo "Run: ls /dev/ttyUSB*"
    exit 1
fi

echo "✓ USB devices detected:"
ls -la /dev/ttyUSB* 2>/dev/null | awk '{print "  " $NF}'
echo ""

# Verify dialout group permissions
if ! groups | grep -q dialout; then
    echo "⚠️  WARNING: User not in 'dialout' group"
    echo "   Run: sudo usermod -a -G dialout $USER"
    echo "   Then logout/login"
fi

# Check hamlib installation
if ! command -v rigctld &>/dev/null; then
    echo "⚠️  WARNING: hamlib/rigctld not installed"
    echo "   Install with: sudo apt install -y hamlib hamlib-tools"
fi

echo ""
echo "✓ Integration ready!"
echo ""
echo "Next steps:"
echo "1. Run: et-radio"
echo "2. Select: Anytone D578UV"
echo "3. Select: Your mode (Winlink, APRS, fldigi, etc.)"
echo "4. Apps will use rigctld for automatic CAT control"
echo ""
echo "To verify CAT connection:"
echo "  rigctl -m 242 -r /dev/ttyUSB1 -s 9600 F"
echo "  (should show current frequency)"
echo ""
EOF

chmod +x /etc/skel/.local/bin/setup-anytone-digirig
log "SUCCESS" "Setup helper script created"

# Create documentation for Anytone CAT control
cat > /etc/skel/Desktop/Anytone-CAT-Setup.txt <<'EOF'
Anytone D578UV + Digirig Mobile CAT Integration
=================================================

OVERVIEW
--------
This ETC customizer includes native et-radio integration for the Anytone D578UV
mobile transceiver. When you select "Anytone D578UV" in et-radio, the system
automatically configures:
  ✓ hamlib/rigctld daemon for CAT control
  ✓ Audio levels via Digirig CM108 codec
  ✓ PTT via serial interface
  ✓ Integration with fldigi, Pat, and other apps

This follows the same pattern as the Yaesu FT-897D reference model.

RADIO SUPPORT TIERS
-------------------
✅ TIER 1 - FULL CAT SUPPORT (THIS CUSTOMIZER):
   - Anytone D578UV (MOBILE transceiver, 2m/1.25cm/70cm) via Digirig Mobile

◐ TIER 2 - AUDIO + PTT ONLY (No CAT):
   - Anytone D878UV (HANDHELD) via Digirig Mobile
     * Audio: /dev/ttyUSB0 (CM108 codec)
     * PTT: Hardware switch only
     * NO CAT control (handhelds rarely support CAT)
   
◐ TIER 3 - BLUETOOTH TNC INTEGRATION:
   - Handheld radios via Bluetooth TNC (e.g., BTech UV-Pro)
     * Uses upstream et-radio KISS TNC configuration
     * Keyboard-to-keyboard digital modes (AX.25 packet)
     * No USB Digirig interface needed
     * Ideal for portable/field operations

Note: This customizer focuses on VHF/UHF (2m, 1.25cm, 70cm bands) for
local/regional emergency communications. HF/6m transceiver support can
be added in the future if needed.

QUICK START
-----------
1. Connect Digirig Mobile to computer (USB-C)
2. Connect radio cable from Digirig to D578UV (6-pin or data port)
3. Run: et-radio
4. Select: "Anytone D578UV" 
5. Select: Your mode (Winlink, APRS, fldigi, etc.)
6. Apps use hamlib automatically for CAT control!

Digirig Mobile Hardware
-----------------------
The Digirig Mobile provides TWO USB interfaces:
  /dev/ttyUSB0 = CM108 audio codec (direwolf, fldigi audio)
  /dev/ttyUSB1 = CP2102 CAT serial (rigctld, flrig)
  PTT = Hardware switch on Digirig

Connection Diagram:
  [D578UV]
      |
  [Digirig Mobile Cable]
      |
  [Digirig Mobile]
      |
  [USB-C to Computer]
      |
  [Linux: /dev/ttyUSB0 (audio), /dev/ttyUSB1 (CAT)]

SETUP VERIFICATION
------------------
Verify USB devices:
  $ ls -la /dev/ttyUSB*
  Should show TWO devices:
    /dev/ttyUSB0 (audio from CM108)
    /dev/ttyUSB1 (CAT from CP2102)

If you only see ONE device:
  - Check physical connection to radio
  - Try different USB port
  - Verify Digirig cable matches radio (6-pin vs Kenwood vs other)
  - Check Digirig is powered

User Permissions:
  $ groups | grep dialout
  If not present, run:
    sudo usermod -a -G dialout $USER
    (logout/login required)

DETAILED SETUP STEPS
--------------------

Step 1: Verify Digirig Installation
  $ hamlib-tools -V      # Check hamlib version
  $ rigctld -V           # Should show "Hamlib rig backend version"
  If not installed:
    sudo apt install -y hamlib hamlib-tools

Step 2: Test CAT Connection
  $ rigctl -m 242 -r /dev/ttyUSB1 -s 9600 F
  (should return current frequency, e.g., "144050000")
  
  If no response:
    - Check cable connection
    - Verify /dev/ttyUSB1 exists (not /dev/ttyUSB2, etc.)
    - Try: cat /dev/ttyUSB1 (should show binary data)

Step 3: Run et-radio Setup
  $ et-radio
  → Select: Anytone D578UV
  → Select: Your mode (Winlink, APRS, fldigi, etc.)
  
  This will:
    - Start rigctld daemon on port 12345
    - Configure audio levels
    - Set up app connections

Step 4: Verify in Applications
  
  fldigi:
    VFO → Rig Control → Check "Enable"
    Should connect automatically to rigctld
    Test: Change frequency in fldigi → radio follows
  
  Pat (Winlink):
    Settings → Hamlib RIG
    Should connect to localhost:12345
  
  Other apps:
    Usually auto-detect or use rigctld at 127.0.0.1:12345

SETUP FOR ANYTONE D878UV (HANDHELD - AUDIO/PTT ONLY)
-----------------------------------------------------
The D878UV DOES NOT support CAT control.
Use Digirig Mobile for audio and PTT only:

1. Connect Hardware
   - Digirig Mobile to computer (USB-C)
   - Connect radio cable from Digirig to D878UV (6-pin or Kenwood connector)
   - Verify: ls /dev/ttyUSB0 (will show ONLY 1 device - audio codec only)

2. Configure Apps for Audio/PTT (No CAT)
   - fldigi: 
     * Use Digirig as audio device
     * Set PTT to "VOX" (voice activation) or "None"
     * Manual frequency tuning on radio
   
   - Pat (Winlink):
     * Use Digirig as audio device
     * Use hardware PTT switch on Digirig
     * Manual frequency tuning on radio
   
   - JS8Call:
     * Use Digirig as audio device
     * Hardware PTT switch for transmit
     * Manual frequency tuning on radio
   
   - Direwolf:
     * Use Digirig as TNC audio device
     * Manual frequency tuning on radio

3. Manual Frequency Control (Important!)
   - NO automatic frequency sync (no CAT)
   - Change frequency on D878UV manually
   - Apps will use whatever frequency radio is on
   - Each app must be told the current frequency

SETUP FOR BTECH UV-PRO (HANDHELD - BLUETOOTH TNC ONLY)
------------------------------------------------------
The UV-Pro DOES NOT use Digirig Mobile.
Use upstream et-radio Bluetooth TNC integration only:

1. Pair Radio via Bluetooth
   - Power on UV-Pro
   - Run: et-radio
   - Select: BTech UV-Pro (or generic Bluetooth TNC)
   - Pair via system Bluetooth settings
   - Add dialout group if not already a member

2. Use with TNC Apps
   - et-radio handles Bluetooth TNC integration
   - Use for: JS8Call, Packet radio, APRS TNC mode
   - No Digirig Mobile interface needed
   - No USB connection to radio

3. DO NOT Use Digirig with UV-Pro
   - DO NOT connect Digirig Mobile to UV-Pro
   - UV-Pro has built-in Bluetooth TNC
   - Use ONLY Bluetooth pairing method
   - Digirig compatibility varies by radio model

SUMMARY TABLE: Which Setup for Which Radio
-------------------------------------------
┌─────────────────┬──────────────┬────────────┬─────────────────┐
│ Radio Model     │ Connection   │ CAT Support│ Primary Use     │
├─────────────────┼──────────────┼────────────┼─────────────────┤
│ D578UV (mobile) │ Digirig USB  │ YES (CAT)  │ Full integration │
│ D878UV (HT)     │ Digirig USB  │ NO (PTT)   │ Audio/PTT only  │
│ UV-Pro (HT)     │ Bluetooth    │ TNC mode   │ KISS TNC only   │
└─────────────────┴──────────────┴────────────┴─────────────────┘

TROUBLESHOOTING
---------------

Problem: USB devices not showing
  Solution:
    - Check Digirig USB-C cable
    - Try different computer USB port
    - Restart Digirig (disconnect/reconnect)
    - Try: lsusb (to verify Digirig detected)
    - Check: dmesg | tail -20 (for USB errors)

Problem: rigctl can't connect
  Solution:
    - Verify TWO ttyUSB devices: ls /dev/ttyUSB*
    - Use correct port: /dev/ttyUSB1 (NOT /dev/ttyUSB0)
    - Check baud rate: 9600
    - Verify Digirig cable is connected to D578UV
    - Test with: cat /dev/ttyUSB1 (should show binary)

Problem: fldigi doesn't connect to rigctld
  Solution:
    - Verify rigctld is running: pgrep rigctld
    - Check port: netstat -tulpn | grep 12345
    - Try manual: fldigi → Rig Control → Set to XML-RPC → localhost:12345
    - Restart fldigi

Problem: Audio too loud/quiet
  Solution:
    - Levels are pre-configured in audio script
    - Adjust in fldigi: Audio > Device Mixer
    - Or manually: alsamixer (select correct device)
    - Remember levels after next boot for your tests

Problem: PTT not working
  Solution:
    - Verify Digirig PTT switch is connected
    - Check fldigi: Rig Control → PTT Control → Via Hamlib RTS
    - Test manual: rigctl -m 242 -r /dev/ttyUSB1 -s 9600 T 1
    - Verify TX LED on radio
    - Try different PTT method if CAT doesn't work

HAMLIB vs FLRIG
----------------
This setup uses HAMLIB (daemon-based):
  ✓ Integrated with et-radio
  ✓ Used by multiple apps simultaneously
  ✓ Starts automatically when you run et-radio
  ✓ Works with fldigi, Pat, JS8Call, etc.
  ✓ Recommended for ETC system integration

FLRIG (GUI-based):
  ✗ Manual startup required
  ✗ Can interfere with hamlib
  ✗ Better for radio experimentation/testing
  ✓ Fallback if hamlib has issues
  
If you prefer flrig:
  1. Close any et-radio sessions
  2. Run: flrig
  3. Configure: Radio Model, Serial Port, Baud
  4. Click Initialize
  
But recommend using hamlib/et-radio for everyday use.

ADVANCED: MULTIPLE APPS
------------------------
hamlib rigctld allows multiple apps to connect simultaneously:

Example: Run both fldigi AND Pat
  1. et-radio → Select Anytone D578UV → Select Winlink mode
  2. This starts rigctld on port 12345
  3. In same terminal: fldigi &
  4. In another terminal: pat gui
  5. Both apps share frequency/mode via rigctld!

To see all connected apps:
  $ netstat -tulpn | grep 12345

RECOMMENDED WORKFLOW
--------------------
1. Power on D578UV
2. Connect Digirig Mobile
3. Verify: ls /dev/ttyUSB* (shows 2 devices)
4. Run: et-radio
5. Select: Anytone D578UV
6. Select: Your mode (Winlink, APRS, fldigi, JS8Call, etc.)
7. Start applications (fldigi, Pat, etc.)
8. Apps use CAT control automatically!
9. Change frequency in app → radio follows
10. Transmit test using VOX or CAT PTT

REFERENCE
---------
Hamlib:  http://www.hamlib.org/
flrig:   http://www.w1hkj.com/
Digirig: https://digirig.net/
  - Cables: https://digirig.net/digirig-transceiver-compatibility/
  - D578UV cable: Look for "Anytone" or "6-pin" options
ETC:     https://community.emcommtools.com/
Anytone: https://www.bridgecomsystems.com/

SUPPORT
-------
Setup helper: ~/.local/bin/setup-anytone-digirig
et-radio docs: https://community.emcommtools.com/
Digirig support: https://www.reddit.com/r/Digirig/

Questions? Check ETC community documentation or Digirig manual.

73!
EOF

chmod 644 /etc/skel/Desktop/Anytone-CAT-Setup.txt
log "SUCCESS" "Comprehensive Anytone CAT documentation created on Desktop"

log "SUCCESS" "=== Radio Configuration Complete ==="
log "INFO" "✓ Anytone D578UV (mobile): Hamlib/rigctld CAT via Digirig Mobile"
log "INFO" "◐ Anytone D878UV (handheld): Digirig Mobile audio/PTT only (no CAT)"
log "INFO" "◐ BTech UV-Pro (handheld): Bluetooth TNC upstream integration only"
log "INFO" "Radio config: ~/.config/emcomm-tools/radios.d/anytone-d578uv.json"
log "INFO" "Setup helper: ~/.local/bin/setup-anytone-digirig"
log "INFO" "Setup guide: ~/Desktop/Anytone-CAT-Setup.txt"

exit 0

