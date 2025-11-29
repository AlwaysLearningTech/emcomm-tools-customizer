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
APRS_SYMBOL="${APRS_SYMBOL:-r/}"
APRS_COMMENT="${APRS_COMMENT:-EmComm iGate}"
DIGIPEATER_PATH="${DIGIPEATER_PATH:-WIDE1-1}"

# APRS Beacon Settings
ENABLE_APRS_BEACON="${ENABLE_APRS_BEACON:-no}"
APRS_BEACON_INTERVAL="${APRS_BEACON_INTERVAL:-300}"
APRS_BEACON_POWER="${APRS_BEACON_POWER:-10}"
APRS_BEACON_HEIGHT="${APRS_BEACON_HEIGHT:-20}"
APRS_BEACON_GAIN="${APRS_BEACON_GAIN:-3}"

# APRS iGate Settings
ENABLE_APRS_IGATE="${ENABLE_APRS_IGATE:-yes}"
APRS_IGTXVIA="${APRS_IGTXVIA:-0}"
APRS_IGFILTER_RADIUS="${APRS_IGFILTER_RADIUS:-500}"
APRS_SERVER="${APRS_SERVER:-noam.aprs2.net}"

# Direwolf Audio Settings (optional - use defaults if not specified)
DIREWOLF_ADEVICE="${DIREWOLF_ADEVICE:-plughw:1,0}"
DIREWOLF_PTT="${DIREWOLF_PTT:-CM108}"

# Pat Winlink EmComm Alias (optional)
PAT_EMCOMM_ALIAS="${PAT_EMCOMM_ALIAS:-no}"
PAT_EMCOMM_FREQ="${PAT_EMCOMM_FREQ:-3.573.0}"

log "INFO" "APRS Configuration:"
log "INFO" "  Callsign: ${CALLSIGN}-${APRS_SSID}"
log "INFO" "  Passcode: ${APRS_PASSCODE}"
log "INFO" "  Symbol: ${APRS_SYMBOL}"
log "INFO" "  Comment: ${APRS_COMMENT}"
log "INFO" "  Digipeater: ${DIGIPEATER_PATH}"
log "INFO" "APRS Beacon:"
log "INFO" "  Enabled: ${ENABLE_APRS_BEACON}"
[ "$ENABLE_APRS_BEACON" = "yes" ] && log "INFO" "  Interval: ${APRS_BEACON_INTERVAL}s, Power: ${APRS_BEACON_POWER}, Height: ${APRS_BEACON_HEIGHT}ft, Gain: ${APRS_BEACON_GAIN}"
log "INFO" "APRS iGate:"
log "INFO" "  Enabled: ${ENABLE_APRS_IGATE}, Server: ${APRS_SERVER}, Filter: ${APRS_IGFILTER_RADIUS}km"
log "INFO" "Direwolf Audio:"
log "INFO" "  Device: ${DIREWOLF_ADEVICE}, PTT: ${DIREWOLF_PTT}"

# ============================================================================
# Configure direwolf (already installed by ETC)
# ============================================================================

log "INFO" "Configuring direwolf..."

# Create direwolf configuration for internet iGate operation
mkdir -p /etc/skel/.config/direwolf

cat > /etc/skel/.config/direwolf/direwolf.conf <<EOF
# Direwolf Configuration - Internet iGate
# Configured from secrets.env

ADEVICE ${DIREWOLF_ADEVICE}
ACHANNELS 1

# Station identification
MYCALL ${CALLSIGN}-${APRS_SSID}

# APRS-IS Internet Gateway (iGate)
IGSERVER ${APRS_SERVER}
IGLOGIN ${CALLSIGN}-${APRS_SSID} ${APRS_PASSCODE}

# Enable iGate functionality (Internet -> RF and RF -> Internet)
$(if [ "$ENABLE_APRS_IGATE" = "yes" ]; then
    echo "IGTXVIA ${APRS_IGTXVIA} ${DIGIPEATER_PATH}"
    echo "IGFILTER m/${APRS_IGFILTER_RADIUS}"
else
    echo "# iGate DISABLED"
    echo "# IGTXVIA 0 ${DIGIPEATER_PATH}"
    echo "# IGFILTER m/${APRS_IGFILTER_RADIUS}"
fi)

# PTT configuration
PTT ${DIREWOLF_PTT}

# Beacon ($(if [ "$ENABLE_APRS_BEACON" = "yes" ]; then echo "ENABLED"; else echo "DISABLED - enable after connecting GPS"; fi))
$(if [ "$ENABLE_APRS_BEACON" = "yes" ]; then
    echo "PBEACON delay=1 every=${APRS_BEACON_INTERVAL} overlay=S symbol=\"${APRS_SYMBOL}\" power=${APRS_BEACON_POWER} height=${APRS_BEACON_HEIGHT} gain=${APRS_BEACON_GAIN} comment=\"${APRS_COMMENT}\" via=${DIGIPEATER_PATH}"
else
    echo "# PBEACON delay=1 every=${APRS_BEACON_INTERVAL} overlay=S symbol=\"${APRS_SYMBOL}\" power=${APRS_BEACON_POWER} height=${APRS_BEACON_HEIGHT} gain=${APRS_BEACON_GAIN} comment=\"${APRS_COMMENT}\" via=${DIGIPEATER_PATH}"
    echo "# Uncomment above line after connecting GPS device"
    echo "# direwolf will automatically use GPS coordinates when available"
fi)

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
aprsIsServer=${APRS_SERVER}
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

log "INFO" "Configuring Pat Winlink $(if [ "$PAT_EMCOMM_ALIAS" = "yes" ]; then echo "(with EmComm alias)"; else echo "(defaults only)"; fi)..."

# Pat config will already exist from et-user restore, so we edit it
# Create a script that will run on first boot to add EmComm alias (if enabled)
mkdir -p /etc/skel/.local/bin

if [ "$PAT_EMCOMM_ALIAS" = "yes" ]; then
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
        jq '.connect_aliases.emcomm = "${PAT_EMCOMM_FREQ}:///${CALLSIGN}?freq=${PAT_EMCOMM_FREQ}"' "\$CONFIG_FILE" > "\$CONFIG_FILE.tmp"
        mv "\$CONFIG_FILE.tmp" "\$CONFIG_FILE"
        
        echo "Pat EmComm alias configured: pat connect emcomm"
    else
        echo "jq not available - manually add to \$CONFIG_FILE:"
        echo '  "connect_aliases": {'
        echo '    "emcomm": "ardop:///${CALLSIGN}?freq=${PAT_EMCOMM_FREQ}"'
        echo '  }'
    fi
else
    echo "Pat config not found at \$CONFIG_FILE"
    echo "Run 'et-user' first to configure Pat"
fi
EOF

    chmod +x /etc/skel/.local/bin/configure-pat-emcomm
    log "SUCCESS" "Pat EmComm alias configuration script created (run on first boot)"
else
    # Pat will use its default aliases only
    log "INFO" "Pat EmComm alias DISABLED - using default Pat aliases"
fi

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
APRS Symbol: ${APRS_SYMBOL}
APRS-IS Server: ${APRS_SERVER}
APRS-IS Passcode: ${APRS_PASSCODE}
Comment: ${APRS_COMMENT}
Digipeater Path: ${DIGIPEATER_PATH}
Direwolf Audio Device: ${DIREWOLF_ADEVICE}
Direwolf PTT Method: ${DIREWOLF_PTT}

APRS Operation Modes:
---------------------
iGate Mode: $(if [ "$ENABLE_APRS_IGATE" = "yes" ]; then echo "ENABLED (filtering ${APRS_IGFILTER_RADIUS}km)"; else echo "DISABLED"; fi)
Beacon Mode: $(if [ "$ENABLE_APRS_BEACON" = "yes" ]; then echo "ENABLED (interval: ${APRS_BEACON_INTERVAL}s)"; else echo "DISABLED (enable after GPS connection)"; fi)

Pre-Configured Applications:
----------------------------
1. direwolf - APRS TNC and iGate (already installed by ETC)
   - Audio Device: ${DIREWOLF_ADEVICE}
   - PTT Method: ${DIREWOLF_PTT}
   - Internet gateway: $(if [ "$ENABLE_APRS_IGATE" = "yes" ]; then echo "ENABLED"; else echo "DISABLED"; fi) (${APRS_SERVER})
   - Beacon: $(if [ "$ENABLE_APRS_BEACON" = "yes" ]; then echo "ENABLED"; else echo "DISABLED"; fi)
   - Config: ~/.config/direwolf/direwolf.conf

2. YAAC - APRS Client (already installed by ETC)
   - APRS-IS Server: ${APRS_SERVER}
   - Digipeater: ENABLED (${DIGIPEATER_PATH})
   - Maps: Cached offline (not live download)
   - Config: ~/.config/YAAC/YAAC.properties

3. Pat Winlink (already installed by ETC)
   - EmComm Alias: $(if [ "$PAT_EMCOMM_ALIAS" = "yes" ]; then echo "ENABLED (pat connect emcomm at ${PAT_EMCOMM_FREQ})"; else echo "DISABLED (using default Pat aliases)"; fi)
   - Run: ~/.local/bin/configure-pat-emcomm to enable (if not already done on first boot)

GPS Beacon Configuration:
-------------------------
$(if [ "$ENABLE_APRS_BEACON" = "yes" ]; then
    echo "Beacon is ENABLED with these parameters:"
    echo "  - Interval: ${APRS_BEACON_INTERVAL} seconds"
    echo "  - Power: ${APRS_BEACON_POWER}"
    echo "  - Height: ${APRS_BEACON_HEIGHT} feet"
    echo "  - Gain: ${APRS_BEACON_GAIN}"
    echo ""
    echo "Connect GPS device and direwolf will automatically use GPS coordinates."
else
    echo "Beacon is DISABLED by default (no GPS broadcasts without GPS lock)."
    echo ""
    echo "To enable after connecting GPS:"
    echo "1. Edit: ~/.config/direwolf/direwolf.conf"
    echo "2. Uncomment the PBEACON line (remove # at start)"
    echo "3. direwolf will use GPS coordinates automatically"
    echo ""
    echo "NOTE: Do NOT beacon without GPS - your position will be wrong!"
fi)

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
1. Connect radio to Digirig (or audio interface)
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
log "INFO" "  - direwolf (${CALLSIGN}-${APRS_SSID} on ${APRS_SERVER})"
log "INFO" "  - YAAC (${CALLSIGN}-${APRS_SSID} on ${APRS_SERVER})"
log "INFO" "  - Pat $(if [ "$PAT_EMCOMM_ALIAS" = "yes" ]; then echo "(with EmComm alias at ${PAT_EMCOMM_FREQ})"; else echo "(default aliases)"; fi)"
log "INFO" "iGate: $(if [ "$ENABLE_APRS_IGATE" = "yes" ]; then echo "ENABLED"; else echo "DISABLED"; fi), Beacon: $(if [ "$ENABLE_APRS_BEACON" = "yes" ]; then echo "ENABLED"; else echo "DISABLED"; fi)"
log "INFO" ""
log "INFO" "Setup guide: ~/Desktop/APRS-iGate-Setup.txt"

exit 0
