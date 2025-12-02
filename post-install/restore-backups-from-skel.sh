#!/bin/bash
#
# Script Name: restore-backups-from-skel.sh
# Description: Legacy script - backups are now restored at build time
# Usage: Not typically needed - kept for backwards compatibility
# Author: KD7DGF
# Date: 2025-11-28
# Build-Time: N/A (backups extracted directly at build time via ET_USER_BACKUP)
# Post-Install: Optional (only if you want to copy backup tarballs for future reference)
#
# === HOW BACKUP RESTORATION NOW WORKS ===
#
# 1. RECOMMENDED: Build-Time Restoration
#    - Run 'et-user-backup' on your existing ETC system
#    - Copy tarball to ./cache/ directory
#    - Set ET_USER_BACKUP in secrets.env
#    - Build ISO - backup is extracted directly into /etc/skel
#    - Settings are pre-configured when user account is created
#
# 2. OPTIONAL: Post-Install with et-user-restore
#    - If backup tarball is in ~/add-ons/backups/, you can run:
#      et-user-restore
#    - This is ETC's native restore tool with a dialog menu
#
# 3. LEGACY: This script
#    - Kept for backwards compatibility
#    - Only copies backup tarballs from /etc/skel to home directory
#    - Does NOT extract them (use et-user-restore for that)
#

set -euo pipefail

# Logging
LOG_DIR="$HOME/.local/share/emcomm-tools-customizer/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/restore-backups-from-skel_$(date +'%Y%m%d_%H%M%S').log"

log() {
    local level="${1:-INFO}"
    local message="$2"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"
}

log "INFO" "=== Checking for Backup Tarballs in /etc/skel ==="

# Look for backup tarballs in /etc/skel
SKEL_BACKUP_DIR="/etc/skel/.etc-customizer-backups"

if [ ! -d "$SKEL_BACKUP_DIR" ]; then
    log "INFO" "No backup tarballs in /etc/skel/.etc-customizer-backups/"
    log "INFO" "This is normal - backups are now extracted at build time"
    log "INFO" "If you have a backup tarball, use: et-user-restore"
    exit 0
fi

# Create target directory for backup tarballs
BACKUP_DIR="$HOME/add-ons/backups"
mkdir -p "$BACKUP_DIR"
log "INFO" "Target directory for backup tarballs: $BACKUP_DIR"

# Copy any backup tarballs found (for reference/future use)
shopt -s nullglob
for tarball in "$SKEL_BACKUP_DIR"/*.tar.gz; do
    filename=$(basename "$tarball")
    log "INFO" "Copying backup tarball: $filename"
    cp -v "$tarball" "$BACKUP_DIR/$filename" 2>&1 | tee -a "$LOG_FILE"
done
shopt -u nullglob

log "INFO" "Backup tarballs copied to: $BACKUP_DIR"
log "INFO" "To restore, run: et-user-restore"
log "SUCCESS" "Done"
