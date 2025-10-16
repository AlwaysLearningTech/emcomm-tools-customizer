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
# Integrate flrig with et-radio system
# ============================================================================
# ETC uses et-radio to select radio, which configures apps like fldigi, Pat, etc.
# We need to add Anytone D578UV option that uses flrig instead of Hamlib

log "INFO" "Configuring flrig for Anytone CAT control via Digirig Mobile..."

# Create flrig configuration directory in /etc/skel
mkdir -p /etc/skel/.flrig

# Create default flrig config for Anytone D578UV
cat > /etc/skel/.flrig/flrig.prefs <<'EOF'
# flrig preferences - Anytone D578UV
rig_model:Anytone D578
baud_rate:9600
server_port:12345
server_addr:127.0.0.1
trace:0
xcvr_serial_port:
xcvr_auto_reconnect:1
EOF

chmod 644 /etc/skel/.flrig/flrig.prefs
log "SUCCESS" "flrig default configuration created"

# Create helper script to configure apps to use flrig instead of Hamlib
mkdir -p /etc/skel/.local/bin

cat > /etc/skel/.local/bin/configure-flrig-rig <<'EOF'
#!/bin/bash
# Configure fldigi, Pat, and other apps to use flrig for CAT control
# IMPORTANT: This is ONLY for radios that support CAT via Digirig Mobile
#
# CAT SUPPORTED: Anytone D578UV (mobile)
# CAT NOT SUPPORTED: Anytone D878UV (handheld), BTech UV-Pro (handheld)
#
# Per Digirig: "CAT control is rare in VHF/UHF radios, practically non-existent in HTs"

set -euo pipefail

echo "==========================================="
echo "Digirig Mobile + flrig CAT Control Setup"
echo "==========================================="
echo ""
echo "⚠️  IMPORTANT: CAT control depends on your RADIO"
echo ""
echo "✅ CAT SUPPORTED via Digirig Mobile:"
echo "   - Anytone D578UV (mobile radio)"
echo "   - Most HF radios with appropriate cables"
echo ""
echo "❌ CAT NOT SUPPORTED (Audio + PTT only):"
echo "   - Anytone D878UV (handheld)"
echo "   - BTech UV-Pro (handheld)"
echo "   - Most VHF/UHF handhelds"
echo ""
read -p "Does your radio support CAT? (y/n): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "CAT not supported. Use audio + PTT only with your radio."
    exit 0
fi

# Start flrig in background
if command -v flrig &>/dev/null; then
    echo "Starting flrig..."
    flrig &
    sleep 2
    echo "✓ flrig started on port 12345"
    echo ""
    echo "Next steps:"
    echo "1. Configure flrig:"
    echo "   - Select: Anytone D578 (for D578UV mobile)"
    echo "   - Serial Port: /dev/ttyUSB1 (the CAT port)"
    echo "     Note: Digirig creates ttyUSB0 (audio) and ttyUSB1 (CAT)"
    echo "   - Baud: 9600"
    echo "   - Click 'Initialize'"
    echo ""
    echo "2. Configure fldigi (if using):"
    echo "   - Configure > Config Dialog > Rig Control"
    echo "   - Select: Use XML-RPC"
    echo "   - Address: 127.0.0.1"
    echo "   - Port: 12345"
    echo ""
    echo "3. Apps like Pat will use flrig automatically via XML-RPC"
    echo ""
    echo "For detailed instructions, see: ~/Desktop/Anytone-CAT-Setup.txt"
else
    echo "ERROR: flrig not installed"
    exit 1
fi
EOF

chmod +x /etc/skel/.local/bin/configure-flrig-rig
log "SUCCESS" "flrig configuration helper created"

# Create documentation for Anytone CAT control
cat > /etc/skel/Desktop/Anytone-CAT-Setup.txt <<'EOF'
Radio CAT Control with Digirig Mobile
======================================

IMPORTANT: CAT support depends on your RADIO, not just the cable!
------------------------------------------------------------------

✅ CAT SUPPORTED via Digirig Mobile:
  - Anytone D578UV (mobile radio)
  - Most HF transceivers

❌ CAT NOT SUPPORTED (Audio + PTT only):
  - Anytone D878UV (handheld) - Use for audio/PTT only
  - BTech UV-Pro (handheld) - Use upstream et-radio KISS TNC
  - Most VHF/UHF handhelds

Per Digirig documentation: "Serial CAT control can be commonly found in HF 
transceivers, but rare in VHF/UHF radios, practically non-existent in HTs."

Digirig Mobile Hardware:
------------------------
The Digirig Mobile provides:
- CM108 audio codec (creates /dev/ttyUSB0)
- CP2102 serial interface (creates /dev/ttyUSB1)
- PTT switch
- Single USB-C connection to computer

Connection:
-----------
- Digirig Mobile to computer via USB-C
- Radio-specific cable from Digirig to radio
- Check ports: ls /dev/ttyUSB*
  * /dev/ttyUSB0 = Audio (use for direwolf, fldigi audio)
  * /dev/ttyUSB1 = CAT serial (use ONLY if radio supports CAT)

Setup for D578UV (Mobile - CAT Supported):
-------------------------------------------

1. Connect Hardware
   - Digirig Mobile to computer USB
   - D578UV cable (6-pin or data port) to Digirig
   - Verify: ls /dev/ttyUSB* shows TWO devices

2. Start flrig
   - Command: flrig &
   - Or: Applications > Ham Radio > flrig
   - Or: Run ~/.local/bin/configure-flrig-rig

3. Configure flrig
   - Radio Model: Anytone D578
   - Serial Port: /dev/ttyUSB1 (CAT port)
   - Baud Rate: 9600
   - Click "Initialize"
   - Test: Change frequency - radio should follow

4. Use with Applications
   - et-radio will detect flrig automatically
   - Apps (fldigi, Pat) use XML-RPC on port 12345

Setup for D878UV or UV-Pro (Handhelds - NO CAT):
-------------------------------------------------

These radios do NOT support CAT via Digirig Mobile.

For D878UV:
  - Use Digirig for audio + PTT only
  - Manual frequency tuning required
  
For BTech UV-Pro:
  - Use upstream et-radio (KISS TNC already configured)
  - No additional setup needed

Setup Steps for Anytone Radios with Digirig Mobile:
-----------------------------------------------------

1. Connect Digirig Mobile
   - Single USB cable from Digirig to computer
   - Appropriate radio cable from Digirig to radio
     * D878UV: Use Anytone-specific cable (6-pin or Kenwood connector)
     * D578UV: Use Anytone-specific cable (6-pin or data port)
   - Find ports: ls /dev/ttyUSB* (usually see TWO devices)
     * /dev/ttyUSB0 = Audio (CM108 codec)
     * /dev/ttyUSB1 = CAT serial (CP2102)

2. Start flrig
   - Command: flrig &
   - Or: Applications > Ham Radio > flrig
   - Or: Run helper script: ~/.local/bin/configure-flrig-rig

3. Configure flrig
   - Select: Anytone D578UV (or D878UV for D878 model)
   - Serial Port: /dev/ttyUSB1 (the CAT port, NOT audio)
   - Baud: 9600
   - Click "Initialize"
   - Test: Change frequency in flrig - radio should follow

4. Run et-radio
   - Command: et-radio
   - Select your mode (Winlink, APRS, fldigi, etc.)
   - Apps will use flrig for CAT control automatically

5. Configure Individual Apps (if needed)
   
   fldigi:
     Configure > Rig Control > Use XML-RPC
     Address: 127.0.0.1
     Port: 12345
   
   Pat:
     Edit ~/.config/pat/config.json
     "hamlib_rigs": {
       "Network": {
         "address": "localhost:12345",
         "network": "flrig"
       }
     }

Workflow:
---------
1. Power on radio
2. Connect programming cable
3. Start: flrig
4. Configure flrig with your radio
5. Start: et-radio (select mode)
6. Start: fldigi, Pat, or other app
7. Apps use flrig for CAT control (frequency, mode, PTT if VOX not used)

Testing:
--------
1. Start flrig with radio connected
2. Start fldigi or other app
3. Change frequency in flrig → app should follow
4. Change frequency in app → radio should follow
5. Transmit test (use VOX or CAT PTT)

Troubleshooting:
----------------
Serial Port Permissions:
  sudo usermod -a -G dialout $USER
  (logout/login required)

flrig Not Connecting:
  - Check Digirig connected to correct radio port (6-pin or data port)
  - Verify TWO USB devices appear: ls /dev/ttyUSB*
    (should see ttyUSB0 and ttyUSB1)
  - Use ttyUSB1 (CAT port) in flrig, NOT ttyUSB0 (audio)
  - Try different USB port
  - Check Digirig cable: Use Anytone-specific cable from Digirig.net

Apps Not Seeing flrig:
  - Check port 12345: netstat -tulpn | grep 12345
  - Restart flrig
  - Check firewall settings

Radio Not Responding:
  - Verify programming cable connected
  - Check radio is powered on
  - Try manual frequency change in flrig
  - Check baud rate (9600 for D578UV)

BTech UV-Pro Users:
-------------------
The UV-Pro is already supported via KISS TNC in the upstream et-radio system.
No additional configuration needed - just run et-radio and select your mode.

For More Information:
---------------------
flrig: http://www.w1hkj.com/
ETC Documentation: https://community.emcommtools.com/
Digirig Mobile: https://digirig.net/product/digirig-mobile/
Digirig Cables: https://digirig.net/digirig-transceiver-compatibility/
Anytone Support: https://www.bridgecomsystems.com/

73!
EOF

chmod 644 /etc/skel/Desktop/Anytone-CAT-Setup.txt
log "SUCCESS" "Radio CAT control documentation created on Desktop"

log "SUCCESS" "=== Radio Configuration Complete ==="
log "INFO" "✓ Anytone D578UV (mobile): CAT supported via /dev/ttyUSB1"
log "INFO" "✗ Anytone D878UV (handheld): Audio/PTT only - NO CAT support"
log "INFO" "✗ BTech UV-Pro (handheld): KISS TNC only - NO CAT support"
log "INFO" "Helper script: ~/.local/bin/configure-flrig-rig"
log "INFO" "Setup guide: ~/Desktop/Anytone-CAT-Setup.txt"

exit 0

