#!/bin/bash
#
# Script Name: install-ham-tools.sh
# Description: Installs amateur radio tools (CHIRP, dmrconfig) during Cubic ISO build
# Usage: Run in Cubic chroot environment
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

log "INFO" "=== Starting Ham Radio Tools Installation ==="

# CHIRP Radio Programming Software
readonly CHIRP_VERSION="20250822"
readonly CHIRP_WHEEL_URL="https://archive.chirpmyradio.com/chirp_next/next-${CHIRP_VERSION}/chirp-${CHIRP_VERSION}-py3-none-any.whl"
readonly CHIRP_WHEEL_FILE="chirp-${CHIRP_VERSION}-py3-none-any.whl"

log "INFO" "Installing CHIRP version ${CHIRP_VERSION}..."

# Download CHIRP wheel file
if ! wget -O "${CHIRP_WHEEL_FILE}" "${CHIRP_WHEEL_URL}"; then
    log "ERROR" "Failed to download CHIRP from ${CHIRP_WHEEL_URL}"
    exit 1
fi

# Install CHIRP with pipx (system-wide)
if ! pipx install --system-site-packages "./${CHIRP_WHEEL_FILE}"; then
    log "ERROR" "Failed to install CHIRP with pipx"
    exit 1
fi

# Ensure pipx is in PATH for all users
pipx ensurepath

log "SUCCESS" "CHIRP installed successfully"

# Create desktop file for CHIRP in /etc/skel
log "INFO" "Creating CHIRP desktop file in /etc/skel..."
mkdir -p /etc/skel/.local/share/applications

cat > /etc/skel/.local/share/applications/chirp.desktop <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=CHIRP
Comment=Radio programming software for amateur radio
Exec=chirp
Icon=chirp
Terminal=false
Categories=HamRadio;Utility;
StartupNotify=true
EOF

chmod 644 /etc/skel/.local/share/applications/chirp.desktop
log "SUCCESS" "CHIRP desktop file created"

# Clean up
rm -f "${CHIRP_WHEEL_FILE}"

# Install dmrconfig
log "INFO" "Installing dmrconfig..."

if ! apt install -y dmrconfig 2>&1 | tee -a "$LOG_FILE"; then
    log "ERROR" "Failed to install dmrconfig"
    exit 1
fi

log "SUCCESS" "dmrconfig installed successfully"

# Note: hamlib and rigctld are already installed by ETC upstream
# They provide CAT control for Anytone D578UV via et-radio integration

# Install flrig as fallback (for manual GUI-based CAT control if hamlib has issues)
log "INFO" "Installing flrig (fallback CAT control - manual mode)..."

if ! apt install -y flrig 2>&1 | tee -a "$LOG_FILE"; then
    log "WARN" "Failed to install flrig (non-fatal, hamlib will provide CAT control)"
else
    log "SUCCESS" "flrig installed successfully (fallback only)"
fi

# Install other ham radio utilities
log "INFO" "Installing additional ham radio utilities..."

# List of additional utilities
HAM_UTILS=(
    libreoffice    # Office suite for documentation
)

for util in "${HAM_UTILS[@]}"; do
    log "INFO" "Installing $util..."
    if apt install -y "$util" 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "$util installed successfully"
    else
        log "WARN" "Failed to install $util (non-fatal)"
    fi
done

log "SUCCESS" "=== Ham Radio Tools Installation Complete ==="
