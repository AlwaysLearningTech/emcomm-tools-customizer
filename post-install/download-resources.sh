#!/bin/bash
#
# Script Name: download-resources.sh
# Description: Downloads offline documentation and resources POST-INSTALLATION
#              Uses ETC's et-mirror.sh command which is only available after ETC install
# Usage: Run AFTER installing ETC on the target system (NOT in Cubic)
# Author: KD7DGF
# Date: 2025-10-15
# Cubic Stage: No
# Post-Install: Yes (requires et-mirror.sh from ETC)
#

set -euo pipefail

# Logging
LOG_DIR="$HOME/.local/share/emcomm-tools-customizer/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(basename "$0" .sh)_$(date +'%Y%m%d_%H%M%S').log"

log() {
    local level="${1:-INFO}"
    local message="$2"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"
}

log "INFO" "=== Starting Resource Downloads (POST-INSTALL) ==="

# Check for et-mirror.sh (only available after ETC installation)
if ! command -v et-mirror.sh &>/dev/null; then
    log "ERROR" "et-mirror.sh not found - this script must run AFTER ETC installation"
    log "ERROR" "Please install from the ETC ISO first"
    exit 3
fi

log "SUCCESS" "et-mirror.sh found - proceeding with downloads"

# Check for internet connectivity
if ! ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
    log "ERROR" "No internet connection - cannot download resources"
    exit 3
fi

log "SUCCESS" "Internet connection confirmed"

# Helper function to mirror a website using et-mirror.sh
mirror_site() {
    local url="$1"
    local description="$2"
    
    log "INFO" "Mirroring: $description"
    log "INFO" "URL: $url"
    
    # Use ETC's built-in et-mirror.sh
    if et-mirror.sh "$url" 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "Successfully mirrored: $description"
        return 0
    else
        log "WARN" "Failed to mirror: $description (non-fatal)"
        return 1
    fi
}

# Offline resources directory (et-mirror.sh manages this automatically)
OFFLINE_DIR="$HOME/offline-www"
log "INFO" "Offline resources will be stored in: $OFFLINE_DIR"

# Download packet radio documentation
log "INFO" "Downloading packet radio documentation..."

mirror_site "https://choisser.com/packet/" "Choisser Packet Radio Resources"
mirror_site "https://www.cantab.net/users/john.wiseman/Documents/" "John Wiseman's Ham Radio Documents"
mirror_site "https://soundcardpacket.org/" "Sound Card Packet Resources"
mirror_site "https://tldp.org/HOWTO/AX25-HOWTO/index.html" "AX.25 HOWTO"

# TODO: Add more resource downloads as needed
# Examples:
# - ARRL documentation
# - FCC Part 97 rules
# - ICS forms
# - EmComm training materials

log "SUCCESS" "=== Resource Downloads Complete ==="
log "INFO" "Offline resources available in: $OFFLINE_DIR"
log "INFO" "Users can access with Min browser after installation"
