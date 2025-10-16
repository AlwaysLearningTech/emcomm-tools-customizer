#!/bin/bash
#
# Script Name: embed-ubuntu-iso.sh
# Description: Embed Ubuntu 22.10 ISO in the build for future ISO creation
# Usage: Run in Cubic chroot environment
# Author: KD7DGF
# Date: 2025-01-15
# Cubic Stage: Yes (runs during ISO build)
# Post-Install: No
#

set -euo pipefail

# Logging setup
LOG_FILE="/var/log/cubic-build/$(basename "$0" .sh).log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    local level="${1:-INFO}"
    local message="$2"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"
}

log "INFO" "Starting Ubuntu ISO embedding..."

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Look for Ubuntu ISO in project directory
UBUNTU_ISO=$(find "$PROJECT_DIR" -maxdepth 1 -name "ubuntu-*.iso" -type f -o -type l | head -1)

if [ -z "$UBUNTU_ISO" ]; then
    log "WARN" "No Ubuntu ISO found in $PROJECT_DIR"
    log "WARN" "Skipping ISO embedding"
    exit 0
fi

if [ ! -f "$UBUNTU_ISO" ] && [ ! -L "$UBUNTU_ISO" ]; then
    log "ERROR" "Ubuntu ISO not found: $UBUNTU_ISO"
    exit 1
fi

log "INFO" "Found Ubuntu ISO: $UBUNTU_ISO"

# Create directory for embedded resources
EMBED_DIR="/opt/emcomm-resources"
mkdir -p "$EMBED_DIR"

# Calculate ISO size
ISO_SIZE=$(du -h "$UBUNTU_ISO" | cut -f1)
log "INFO" "ISO size: $ISO_SIZE"

# Copy ISO to embedded directory
ISO_NAME=$(basename "$UBUNTU_ISO")
EMBED_ISO="$EMBED_DIR/$ISO_NAME"

log "INFO" "Embedding ISO to: $EMBED_ISO"
if ! cp "$UBUNTU_ISO" "$EMBED_ISO"; then
    log "ERROR" "Failed to embed Ubuntu ISO"
    exit 1
fi

# Set permissions
chmod 644 "$EMBED_ISO"

log "SUCCESS" "Ubuntu ISO embedded successfully!"
log "INFO" "Embedded ISO: $EMBED_ISO ($ISO_SIZE)"

# Create README for embedded resources
cat > "$EMBED_DIR/README.txt" <<'EOF'
EmComm Tools - Embedded Resources
==================================

This directory contains resources embedded in the ISO for offline use and
future ISO builds.

Contents:
---------
- ubuntu-22.10-desktop-amd64.iso: Ubuntu base ISO for creating new ETC builds

Usage:
------
To create a new ETC build using the embedded ISO:

1. Open terminal
2. Run: etc-rebuild-iso

Or manually with build-etc-iso.sh:
./build-etc-iso.sh -r stable -u /opt/emcomm-resources/ubuntu-22.10-desktop-amd64.iso

Cleanup:
--------
To remove embedded Ubuntu ISO (saves ~3.6 GB):
sudo rm /opt/emcomm-resources/ubuntu-22.10-desktop-amd64.iso

Note: You'll need to download the ISO again for future builds if removed.

Space Usage:
------------
Run: du -h /opt/emcomm-resources

For more information:
---------------------
https://github.com/AlwaysLearningTech/emcomm-tools-customizer
EOF

log "SUCCESS" "README created at: $EMBED_DIR/README.txt"

# Create helper script for rebuilding ISO
cat > "/usr/local/bin/etc-rebuild-iso" <<'EOF'
#!/bin/bash
#
# etc-rebuild-iso - Helper script to create new ETC build using embedded ISO
#

set -euo pipefail

echo "EmComm Tools - Rebuild ISO"
echo "=========================="
echo ""

# Check if embedded ISO exists
EMBED_ISO="/opt/emcomm-resources/ubuntu-22.10-desktop-amd64.iso"
if [ ! -f "$EMBED_ISO" ]; then
    echo "ERROR: Embedded Ubuntu ISO not found at: $EMBED_ISO"
    echo "You may have removed it with cleanup mode."
    echo "Download manually from: https://old-releases.ubuntu.com/releases/22.10/"
    exit 1
fi

# Check if build script exists
BUILD_SCRIPT="$HOME/emcomm-tools-customizer/build-etc-iso.sh"
if [ ! -f "$BUILD_SCRIPT" ]; then
    echo "ERROR: build-etc-iso.sh not found"
    echo "Clone repository: git clone https://github.com/AlwaysLearningTech/emcomm-tools-customizer"
    exit 1
fi

echo "Using embedded Ubuntu ISO: $EMBED_ISO"
echo ""
echo "Choose release mode:"
echo "  1) Stable (latest stable release)"
echo "  2) Latest (latest tag, including pre-releases)"
echo "  3) Specific tag"
echo ""
read -p "Enter choice [1-3]: " choice

case $choice in
    1)
        RELEASE_MODE="stable"
        ;;
    2)
        RELEASE_MODE="latest"
        ;;
    3)
        read -p "Enter tag name: " tag
        RELEASE_MODE="tag"
        RELEASE_TAG="-t $tag"
        ;;
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac

echo ""
echo "Starting ISO rebuild with mode: $RELEASE_MODE"
echo ""

cd "$HOME/emcomm-tools-customizer"
./build-etc-iso.sh -r "$RELEASE_MODE" ${RELEASE_TAG:-} -u "$EMBED_ISO"
EOF

chmod +x "/usr/local/bin/etc-rebuild-iso"
log "SUCCESS" "Helper script created: /usr/local/bin/etc-rebuild-iso"

log "SUCCESS" "Ubuntu ISO embedding complete!"
log "INFO" ""
log "INFO" "Users can rebuild ISO with: etc-rebuild-iso"
log "INFO" "Embedded ISO location: $EMBED_ISO"
log "INFO" "To remove embedded ISO (saves space): sudo rm $EMBED_ISO"

exit 0
