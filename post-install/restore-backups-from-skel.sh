#!/bin/bash
#
# Script Name: restore-backups-from-skel.sh
# Description: Restore backup files from /etc/skel to user's home directory after deployment
# Usage: ./restore-backups-from-skel.sh (run once after first boot)
# Author: KD7DGF
# Date: 2025-11-28
# Cubic Stage: No (runs post-installation)
# Post-Install: Yes
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

log "INFO" "=== Starting Backup Restoration from /etc/skel ==="

# Detect backup source directory in /etc/skel
SKEL_BACKUP_DIR="/etc/skel/.etc-customizer-backups"

if [ ! -d "$SKEL_BACKUP_DIR" ]; then
    log "INFO" "No backups found in /etc/skel/.etc-customizer-backups/ (normal for new deployments)"
    log "INFO" "Backups will be created on next ISO build"
    exit 0
fi

# Create target backup directory
BACKUP_DIR="$HOME/etc-customizer-backups"
mkdir -p "$BACKUP_DIR"
log "INFO" "Target backup directory: $BACKUP_DIR"

# Restore wine.tar.gz if present
if [ -f "$SKEL_BACKUP_DIR/wine.tar.gz" ]; then
    log "INFO" "Restoring wine.tar.gz from /etc/skel..."
    if cp -v "$SKEL_BACKUP_DIR/wine.tar.gz" "$BACKUP_DIR/wine.tar.gz" 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "Restored wine.tar.gz (VARA FM baseline)"
    else
        log "WARN" "Failed to copy wine.tar.gz (non-fatal)"
    fi
else
    log "INFO" "wine.tar.gz not found in /etc/skel (no VARA FM backup configured)"
fi

# Restore et-user-current.tar.gz if present
if [ -f "$SKEL_BACKUP_DIR/et-user-current.tar.gz" ]; then
    log "INFO" "Restoring et-user-current.tar.gz from /etc/skel..."
    if cp -v "$SKEL_BACKUP_DIR/et-user-current.tar.gz" "$BACKUP_DIR/et-user-current.tar.gz" 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "Restored et-user-current.tar.gz (current user settings)"
    else
        log "WARN" "Failed to copy et-user-current.tar.gz (non-fatal)"
    fi
else
    log "INFO" "et-user-current.tar.gz not found in /etc/skel"
fi

# Restore et-user.tar.gz if present
if [ -f "$SKEL_BACKUP_DIR/et-user.tar.gz" ]; then
    log "INFO" "Restoring et-user.tar.gz from /etc/skel..."
    if cp -v "$SKEL_BACKUP_DIR/et-user.tar.gz" "$BACKUP_DIR/et-user.tar.gz" 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "Restored et-user.tar.gz (baseline settings)"
    else
        log "WARN" "Failed to copy et-user.tar.gz (non-fatal)"
    fi
else
    log "INFO" "et-user.tar.gz not found in /etc/skel"
fi

# Verify what was restored
log "INFO" "Backup directory contents after restoration:"
ls -lh "$BACKUP_DIR" 2>&1 | tee -a "$LOG_FILE"

log "SUCCESS" "=== Backup Restoration Complete ==="
log "INFO" "Backups available at: $BACKUP_DIR"
log "INFO" "These will be used for next ISO build"
