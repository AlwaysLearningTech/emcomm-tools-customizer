#!/bin/bash
#
# Script Name: finalize-build.sh
# Description: Final cleanup and optimization before ISO generation
# Usage: Run in Cubic chroot environment (last script to run)
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

log "INFO" "=== Starting Build Finalization ==="

# Clean up APT cache to reduce ISO size
log "INFO" "Cleaning APT cache..."
if apt clean && apt autoremove -y 2>&1 | tee -a "$LOG_FILE"; then
    log "SUCCESS" "APT cache cleaned"
else
    log "WARN" "APT cleanup encountered issues (non-fatal)"
fi

# Remove APT lists to reduce ISO size
log "INFO" "Removing APT lists..."
rm -rf /var/lib/apt/lists/*
log "SUCCESS" "APT lists removed"

# Clean up temporary files
log "INFO" "Cleaning temporary files..."
rm -rf /tmp/*
rm -rf /var/tmp/*
log "SUCCESS" "Temporary files cleaned"

# Remove unnecessary log files
log "INFO" "Cleaning old log files..."
find /var/log -type f -name "*.log" -size +10M -delete 2>&1 | tee -a "$LOG_FILE"
find /var/log -type f -name "*.gz" -delete 2>&1 | tee -a "$LOG_FILE"
log "SUCCESS" "Log files cleaned"

# Set proper permissions on critical directories
log "INFO" "Setting proper permissions..."

# Ensure /etc/skel has correct permissions
chmod 755 /etc/skel
find /etc/skel -type d -exec chmod 755 {} \;
find /etc/skel -type f -exec chmod 644 {} \;

# NetworkManager connections should remain 600
if [ -d "/etc/NetworkManager/system-connections" ]; then
    find /etc/NetworkManager/system-connections -type f -name "*.nmconnection" -exec chmod 600 {} \;
    log "SUCCESS" "NetworkManager connection permissions verified"
fi

log "SUCCESS" "Permissions set"

# Create build manifest
log "INFO" "Creating build manifest..."
MANIFEST_FILE="/etc/emcomm-customizations-manifest.txt"

cat > "$MANIFEST_FILE" <<EOF
EmComm Tools Community - KD7DGF Customizations
Build Date: $(date +'%Y-%m-%d %H:%M:%S')
Builder: $(whoami)

=== INSTALLED CUSTOMIZATIONS ===

Ham Radio Tools:
- CHIRP (radio programming)
- dmrconfig (DMR radio configuration)
- flrig (Anytone D578UV CAT control)
- LibreOffice (documentation)

APRS Configuration (configured, already installed by ETC):
- direwolf (APRS TNC/iGate - internet enabled)
- YAAC (APRS client/digipeater - internet enabled)
- Pat Winlink (EmComm connect alias configured)

Desktop Configuration:
- Dark mode enabled by default
- On-screen keyboard disabled
- Display scaling: 100%
- High-visibility terminal colors

User Configuration:
$(if [ -f "/etc/lightdm/lightdm.conf.d/50-autologin.conf" ]; then
    echo "- Autologin user: $(grep "autologin-user=" /etc/lightdm/lightdm.conf.d/50-autologin.conf | cut -d'=' -f2)"
else
    echo "- Autologin: Not configured"
fi)
- Hostname: $(cat /etc/hostname 2>/dev/null || echo "not configured")

Radio Configurations:
$(if [ -d "/etc/skel/.config/radio-configs" ]; then
    echo "- Pre-configured radio presets:"
    find /etc/skel/.config/radio-configs -type f -name "*.conf" -exec basename {} .conf \; | sed 's/^/  * /'
else
    echo "- No radio configurations installed"
fi)

WiFi Configuration:
$(if [ -d "/etc/NetworkManager/system-connections" ]; then
    echo "- Pre-configured networks:"
    find /etc/NetworkManager/system-connections -type f -name "*.nmconnection" -exec basename {} .nmconnection \; | sed 's/^/  * /'
else
    echo "- No WiFi networks configured"
fi)

Offline Resources:
$(if [ -d "/etc/skel/offline-www" ]; then
    echo "- Documentation mirrored to ~/offline-www"
    find /etc/skel/offline-www -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sed 's/^/  * /'
else
    echo "- No offline resources downloaded"
fi)

Embedded Resources:
$(if [ -d "/opt/emcomm-resources" ]; then
    echo "- Ubuntu ISO embedded for future builds:"
    find /opt/emcomm-resources -name "*.iso" -exec basename {} \; | sed 's/^/  * /'
    echo "- Use 'etc-rebuild-iso' command to create new build"
    echo "- To remove and save space: sudo rm /opt/emcomm-resources/*.iso"
else
    echo "- No embedded resources"
fi)

=== BUILD LOGS ===
Cubic build logs available at: /var/log/cubic-build/

=== USAGE ===
After installing ETC from this ISO:
1. WiFi networks will connect automatically
2. Dark mode and accessibility settings pre-configured
3. CHIRP and other ham tools available in applications menu
4. Offline documentation in ~/offline-www directory

73 de KD7DGF
EOF

chmod 644 "$MANIFEST_FILE"
log "SUCCESS" "Build manifest created: $MANIFEST_FILE"

# Display summary
log "INFO" ""
log "INFO" "=== FINALIZATION SUMMARY ==="
log "INFO" "Build manifest: $MANIFEST_FILE"
log "INFO" "Cubic logs: /var/log/cubic-build/"
log "INFO" ""
log "INFO" "Disk usage summary:"
du -sh /var/cache/apt 2>/dev/null || true
du -sh /etc/skel 2>/dev/null || true
du -sh /etc/NetworkManager/system-connections 2>/dev/null || true
log "INFO" ""

log "SUCCESS" "=== Build Finalization Complete ==="
log "INFO" "Ready for Cubic to generate ISO"
log "INFO" "Click 'Next' in Cubic to continue"
