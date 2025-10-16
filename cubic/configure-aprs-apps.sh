#!/bin/bash
#
# Script Name: configure-aprs-apps.sh
# Description: Configure direwolf, YAAC, and Pat for internet iGate/digipeater using secrets.env
# Usage: Run in Cubic chroot environment
# Author: KD7DGF
# Date: 2025-10-15
# Cubic Stage: Yes (runs during ISO build)
# Post-Install: No
# Note: direwolf and YAAC are already installed by ETC upstream
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

log "INFO" "=== Starting APRS Apps Configuration ==="

# Get script directory (where secrets.env should be)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_FILE="$SCRIPT_DIR/../secrets.env"

# Source secrets file
if [[ -f "$SECRETS_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$SECRETS_FILE"
    log "INFO" "Loaded configuration from secrets.env"
else
    log "WARN" "secrets.env not found - using default values"
fi

# Extract APRS configuration from secrets.env
CALLSIGN="${CALLSIGN:-N0CALL}"
APRS_SSID="${APRS_SSID:-10}"
APRS_PASSCODE="${APRS_PASSCODE:--1}"
APRS_COMMENT="${APRS_COMMENT:-EmComm iGate}"
DIGIPEATER_PATH="${DIGIPEATER_PATH:-WIDE1-1}"

log "INFO" "APRS Configuration:"
log "INFO" "  Callsign: ${CALLSIGN}-${APRS_SSID}"
log "INFO" "  Passcode: ${APRS_PASSCODE}"
log "INFO" "  Comment: ${APRS_COMMENT}"
log "INFO" "  Digipeater: ${DIGIPEATER_PATH}"

# ============================================================================
# Configure direwolf (already installed by ETC)
# ============================================================================

log "INFO" "Configuring direwolf..."

# Create direwolf configuration for internet iGate operation
mkdir -p /etc/skel/.config/direwolf

cat > /etc/skel/.config/direwolf/direwolf.conf <<EOF
# Direwolf Configuration - Internet iGate
# Configured from secrets.env

ADEVICE plughw:1,0
ACHANNELS 1

# Station identification
MYCALL ${CALLSIGN}-${APRS_SSID}

# APRS-IS Internet Gateway (iGate)
IGSERVER noam.aprs2.net
IGLOGIN ${CALLSIGN}-${APRS_SSID} ${APRS_PASSCODE}

# Enable iGate functionality (Internet -> RF and RF -> Internet)
IGTXVIA 0 ${DIGIPEATER_PATH}
IGFILTER m/500
# Filter: Messages within 500km

# PTT configuration (VOX recommended for iGate)
PTT CM108

# Beacon (DISABLED - only enable when GPS connected)
# Uncomment PBEACON line below after connecting GPS device
# direwolf will automatically use GPS coordinates when available
# PBEACON delay=1 every=30 overlay=S symbol="digi" power=10 height=20 gain=3 comment="${APRS_COMMENT}" via=${DIGIPEATER_PATH}

# Logging
LOGDIR /var/log/direwolf
EOF

chmod 644 /etc/skel/.config/direwolf/direwolf.conf
log "SUCCESS" "direwolf configured with callsign ${CALLSIGN}-${APRS_SSID}"

# ============================================================================
# Configure YAAC (already installed by ETC)
# ============================================================================

log "INFO" "Configuring YAAC..."

mkdir -p /etc/skel/.config/YAAC

cat > /etc/skel/.config/YAAC/YAAC.properties <<EOF
# YAAC Configuration - Digipeater and APRS-IS
# Configured from secrets.env

# Station settings
callsign=${CALLSIGN}
ssid=${APRS_SSID}

# APRS-IS connection
aprsIsEnabled=true
aprsIsServer=noam.aprs2.net
aprsIsPort=14580
aprsIsPasscode=${APRS_PASSCODE}

# Digipeater functionality
digipeaterEnabled=true
digipeaterAlias=${DIGIPEATER_PATH}

# Map settings
mapEnabled=true
onlineMapEnabled=false
# Maps should be cached locally - online only for updates

# Station comment
comment=${APRS_COMMENT}
EOF

chmod 644 /etc/skel/.config/YAAC/YAAC.properties
log "SUCCESS" "YAAC configured with callsign ${CALLSIGN}-${APRS_SSID}"

# ============================================================================
# Configure Pat Winlink (already installed by ETC)
# ============================================================================

log "INFO" "Configuring Pat Winlink EmComm alias..."

# Pat config will already exist from et-user restore, so we edit it
# Create a script that will run on first boot to add EmComm alias
mkdir -p /etc/skel/.local/bin

cat > /etc/skel/.local/bin/configure-pat-emcomm <<EOF
#!/bin/bash
# Add EmComm connect alias to Pat configuration
# This runs on first boot to update existing Pat config

CONFIG_FILE="\$HOME/.config/pat/config.json"

if [ -f "\$CONFIG_FILE" ]; then
    # Use jq to add EmComm alias if jq is available
    if command -v jq &>/dev/null; then
        # Create backup
        cp "\$CONFIG_FILE" "\$CONFIG_FILE.bak"
        
        # Add EmComm alias to connect_aliases
        jq '.connect_aliases.emcomm = "ardop:///${CALLSIGN}?freq=3.573.0"' "\$CONFIG_FILE" > "\$CONFIG_FILE.tmp"
        mv "\$CONFIG_FILE.tmp" "\$CONFIG_FILE"
        
        echo "Pat EmComm alias configured: pat connect emcomm"
    else
        echo "jq not available - manually add to \$CONFIG_FILE:"
        echo '  "connect_aliases": {'
        echo '    "emcomm": "ardop:///${CALLSIGN}?freq=3.573.0"'
        echo '  }'
    fi
else
    echo "Pat config not found at \$CONFIG_FILE"
    echo "Run 'et-user' first to configure Pat"
fi
EOF

chmod +x /etc/skel/.local/bin/configure-pat-emcomm
log "SUCCESS" "Pat EmComm alias configuration script created"

# ============================================================================
# Create Setup Guide
# ============================================================================

log "INFO" "Creating setup guide..."

cat > /etc/skel/Desktop/APRS-iGate-Setup.txt <<EOF
APRS iGate/Digipeater Setup Guide
==================================

Your system is pre-configured for APRS iGate and digipeater operation.

Configuration (from secrets.env):
---------------------------------
Callsign: ${CALLSIGN}-${APRS_SSID}
APRS-IS Passcode: ${APRS_PASSCODE}
Comment: ${APRS_COMMENT}
Digipeater Path: ${DIGIPEATER_PATH}

Pre-Configured Applications:
----------------------------
1. direwolf - APRS TNC and iGate (already installed by ETC)
   - Internet gateway: ENABLED (noam.aprs2.net)
   - RF to Internet: ENABLED
   - Beacon: DISABLED (enable after connecting GPS)
   - Config: ~/.config/direwolf/direwolf.conf

2. YAAC - APRS Client (already installed by ETC)
   - APRS-IS: ENABLED
   - Digipeater: ENABLED (${DIGIPEATER_PATH})
   - Maps: Cached offline (not live download)
   - Config: ~/.config/YAAC/YAAC.properties

3. Pat Winlink (already installed by ETC)
   - EmComm alias: "pat connect emcomm"
   - Run: ~/.local/bin/configure-pat-emcomm to enable

GPS Beacon Configuration:
-------------------------
Beacon is DISABLED by default (no GPS broadcasts without GPS lock).

To enable after connecting GPS:
1. Edit: ~/.config/direwolf/direwolf.conf
2. Uncomment the PBEACON line (remove # at start)
3. direwolf will use GPS coordinates automatically

NOTE: Do NOT beacon without GPS - your position will be wrong!

CAT Control Note:
-----------------
BTech UV-Pro: NO CAT control available (VOX only)
Anytone D878UV: NO CAT control via Digirig (cable limitation)
Anytone D578UV: CAT control available with programming cable
  - Use flrig (recommended) or Hamlib
  - Install: Already installed in this build
  - Config: ~/.flrig/ or Hamlib settings

Quick Start:
------------
1. Connect radio to Digirig
2. Connect Digirig to computer
3. (Optional) Connect GPS for beaconing
4. Start direwolf
5. Start YAAC

Configuration Files:
--------------------
All configs are in: ~/.config/
- direwolf/direwolf.conf
- YAAC/YAAC.properties
- pat/config.json

For More Information:
---------------------
direwolf: https://github.com/wb2osz/direwolf
YAAC: http://www.ka2ddo.org/ka2ddo/YAAC.html
Pat: https://getpat.io/

73!
EOF

chmod 644 /etc/skel/Desktop/APRS-iGate-Setup.txt
log "SUCCESS" "Setup guide created at ~/Desktop/APRS-iGate-Setup.txt"

# ============================================================================
# Summary
# ============================================================================

log "SUCCESS" "=== APRS Apps Configuration Complete ==="
log "INFO" "Configured applications:"
log "INFO" "  - direwolf (${CALLSIGN}-${APRS_SSID})"
log "INFO" "  - YAAC (${CALLSIGN}-${APRS_SSID})"
log "INFO" "  - Pat EmComm alias (run configure-pat-emcomm)"
log "INFO" ""
log "INFO" "Setup guide: ~/Desktop/APRS-iGate-Setup.txt"

exit 0
