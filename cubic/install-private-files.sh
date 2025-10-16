#!/bin/bash
#
# Script Name: install-private-files.sh
# Description: Installs private files (configs, documents, etc.) during Cubic ISO build
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

log "INFO" "=== Starting Private Files Installation ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRIVATE_FILES_DIR="$SCRIPT_DIR/../private-files"

if [ ! -d "$PRIVATE_FILES_DIR" ]; then
    log "INFO" "No private files directory found, skipping"
    log "INFO" "Private files can be added with -p flag to build-etc-iso.sh"
    exit 0
fi

log "INFO" "Installing private files from: $PRIVATE_FILES_DIR"

# Create destination directory in /etc/skel
DEST_DIR="/etc/skel/emcomm-private"
mkdir -p "$DEST_DIR"

# Copy all private files
if cp -r "$PRIVATE_FILES_DIR"/* "$DEST_DIR/" 2>&1 | tee -a "$LOG_FILE"; then
    log "SUCCESS" "Private files copied to: $DEST_DIR"
    
    # Set proper permissions
    chmod -R 755 "$DEST_DIR"
    
    # List what was installed (first level only)
    log "INFO" "Installed private files:"
    find "$DEST_DIR" -maxdepth 2 -type f 2>/dev/null | while read -r file; do
        log "INFO" "  - $(basename "$file")"
    done
else
    log "ERROR" "Failed to copy private files"
    exit 1
fi

# Special handling for common file types
# ICS forms
if [ -d "$DEST_DIR/ics-forms" ]; then
    log "INFO" "Linking ICS forms to Documents..."
    mkdir -p /etc/skel/Documents
    ln -sf ~/emcomm-private/ics-forms /etc/skel/Documents/ICS-Forms
fi

# Radio configs
if [ -d "$DEST_DIR/radio-configs" ]; then
    log "INFO" "Linking radio configs to .config..."
    mkdir -p /etc/skel/.config
    ln -sf ~/emcomm-private/radio-configs /etc/skel/.config/radio-configs
fi

# Manuals/documentation
if [ -d "$DEST_DIR/manuals" ]; then
    log "INFO" "Linking manuals to Documents..."
    mkdir -p /etc/skel/Documents
    ln -sf ~/emcomm-private/manuals /etc/skel/Documents/Equipment-Manuals
fi

log "SUCCESS" "=== Private Files Installation Complete ==="
log "INFO" "Files will be available in ~/emcomm-private for all users"
