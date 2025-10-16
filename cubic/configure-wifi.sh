#!/bin/bash
#
# Script Name: configure-wifi.sh
# Description: Configures WiFi networks directly in NetworkManager during Cubic ISO build
# Usage: Run in Cubic chroot environment (requires secrets.env in same directory)
# Author: KD7DGF
# Date: 2025-10-15
# Cubic Stage: Yes (runs during ISO build)
# Post-Install: No
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

log "INFO" "=== Starting WiFi Configuration ==="

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the secrets file
SECRETS_FILE="$SCRIPT_DIR/../secrets.env"
if [[ ! -f "$SECRETS_FILE" ]]; then
    log "ERROR" "secrets.env file not found at $SECRETS_FILE"
    log "ERROR" "Please copy secrets.env.template to secrets.env and fill in your credentials"
    log "ERROR" "WiFi configuration will be skipped"
    exit 2
fi

# shellcheck source=/dev/null
source "$SECRETS_FILE"

# Validate required variables
if [[ -z "${WIFI_COUNT:-}" ]] || [[ "$WIFI_COUNT" -lt 1 ]]; then
    log "ERROR" "WIFI_COUNT not set or invalid in secrets.env"
    exit 2
fi

log "INFO" "Configuring $WIFI_COUNT WiFi networks..."

# Create NetworkManager system connections directory
NM_CONNECTIONS_DIR="/etc/NetworkManager/system-connections"
mkdir -p "$NM_CONNECTIONS_DIR"

# Helper function to generate UUID
generate_uuid() {
    if command -v uuidgen &>/dev/null; then
        uuidgen
    else
        # Fallback if uuidgen not available
        cat /proc/sys/kernel/random/uuid
    fi
}

# Configure each WiFi network
for i in $(seq 1 "$WIFI_COUNT"); do
    # Dynamically construct variable names
    ssid_var="WIFI_${i}_SSID"
    password_var="WIFI_${i}_PASSWORD"
    autoconnect_var="WIFI_${i}_AUTOCONNECT"
    
    # Indirect variable expansion
    ssid="${!ssid_var:-}"
    password="${!password_var:-}"
    autoconnect="${!autoconnect_var:-yes}"
    
    # Skip if SSID or password is empty
    if [[ -z "$ssid" ]]; then
        log "WARN" "WIFI_${i}_SSID is empty, skipping network $i"
        continue
    fi
    
    if [[ -z "$password" ]]; then
        log "WARN" "WIFI_${i}_PASSWORD is empty, skipping network $i"
        continue
    fi
    
    # Normalize autoconnect value
    if [[ "${autoconnect,,}" == "no" ]] || [[ "${autoconnect,,}" == "false" ]]; then
        autoconnect="false"
    else
        autoconnect="true"
    fi
    
    log "INFO" "Adding WiFi network $i: $ssid (autoconnect: $autoconnect)"
    
    # Generate UUID for this connection
    connection_uuid=$(generate_uuid)
    
    # Create NetworkManager connection file
    # NOTE: We're baking WiFi credentials into the ISO because this is a single-user build
    connection_file="${NM_CONNECTIONS_DIR}/${ssid}.nmconnection"
    
    cat > "$connection_file" <<EOF
[connection]
id=$ssid
uuid=$connection_uuid
type=wifi
autoconnect=$autoconnect
permissions=

[wifi]
mode=infrastructure
ssid=$ssid

[wifi-security]
key-mgmt=wpa-psk
psk=$password

[ipv4]
method=auto

[ipv6]
addr-gen-mode=default
method=auto
EOF
    
    # CRITICAL: NetworkManager requires 600 permissions on connection files
    chmod 600 "$connection_file"
    
    # Verify file was created with correct permissions
    if [[ -f "$connection_file" ]] && [[ "$(stat -c %a "$connection_file")" == "600" ]]; then
        log "SUCCESS" "WiFi network configured: $ssid"
    else
        log "ERROR" "Failed to create or set permissions for: $connection_file"
    fi
done

log "SUCCESS" "=== WiFi Configuration Complete ==="
log "INFO" "WiFi networks will be available after booting the ISO"
