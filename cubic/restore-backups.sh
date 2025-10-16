#!/bin/bash
#
# Script Name: restore-backups.sh
# Description: Restores .wine and et-user configuration backups during Cubic ISO build
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

log "INFO" "=== Starting Backup Restore ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUPS_DIR="$SCRIPT_DIR/../backups"

# Restore .wine backup (VARA, Winlink configurations)
# Note: Backups are tar.gz files from et-user-backup command
if [ -f "$BACKUPS_DIR/wine.tar.gz" ]; then
    log "INFO" "Restoring .wine backup from tar.gz..."
    
    # Extract to /etc/skel so all new users get it
    WINE_DEST="/etc/skel/.wine"
    
    # Extract the tar.gz
    if tar -xzf "$BACKUPS_DIR/wine.tar.gz" -C /etc/skel/ 2>&1 | tee -a "$LOG_FILE"; then
        # Rename extracted directory to .wine if it has a different name
        if [ -d "/etc/skel/.wine32" ]; then
            mv /etc/skel/.wine32 "$WINE_DEST"
        fi
        
        log "SUCCESS" ".wine backup restored to: $WINE_DEST"
        
        # Set proper permissions
        chmod -R 755 "$WINE_DEST"
        
        # List what was restored
        log "INFO" "Restored WINE applications:"
        if [ -d "$WINE_DEST/drive_c/VARA" ]; then
            log "INFO" "  - VARA HF"
        fi
        if [ -d "$WINE_DEST/drive_c/VARA FM" ]; then
            log "INFO" "  - VARA FM"
        fi
        find "$WINE_DEST/drive_c" -maxdepth 2 -name "*.exe" 2>/dev/null | head -10 | while read -r exe; do
            log "INFO" "  - $(basename "$exe" .exe)"
        done
    else
        log "ERROR" "Failed to restore .wine backup"
        exit 1
    fi
elif [ -d "$BACKUPS_DIR/wine" ]; then
    # Fallback: Handle directory format (not tar.gz)
    log "INFO" "Restoring .wine backup from directory..."
    
    WINE_DEST="/etc/skel/.wine"
    
    if cp -r "$BACKUPS_DIR/wine" "$WINE_DEST" 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" ".wine backup restored to: $WINE_DEST"
        chmod -R 755 "$WINE_DEST"
    else
        log "ERROR" "Failed to restore .wine backup"
        exit 1
    fi
else
    log "INFO" "No .wine backup found (looking for wine.tar.gz or wine/ directory), skipping"
fi

# Restore et-user configuration (callsign, grid square, etc.)
# Note: Backups are tar.gz files from et-user-backup command
if [ -f "$BACKUPS_DIR/et-user.tar.gz" ]; then
    log "INFO" "Restoring et-user configuration from tar.gz..."
    
    # Extract to temporary location
    TEMP_EXTRACT="/tmp/et-user-restore"
    mkdir -p "$TEMP_EXTRACT"
    
    if tar -xzf "$BACKUPS_DIR/et-user.tar.gz" -C "$TEMP_EXTRACT" 2>&1 | tee -a "$LOG_FILE"; then
        # Create et-user configuration directory in /etc/skel
        ET_CONFIG_DIR="/etc/skel/.config/emcomm-tools"
        mkdir -p "$ET_CONFIG_DIR"
        
        # Copy user.json from extracted backup
        if [ -f "$TEMP_EXTRACT/.config/emcomm-tools/user.json" ]; then
            cp "$TEMP_EXTRACT/.config/emcomm-tools/user.json" "$ET_CONFIG_DIR/user.json"
            log "SUCCESS" "et-user configuration restored"
            
            # Extract and log key values
            log "INFO" "Configuration values:"
            if command -v jq &>/dev/null; then
                jq -r 'to_entries[] | "  \(.key): \(.value)"' "$ET_CONFIG_DIR/user.json" 2>/dev/null | tee -a "$LOG_FILE"
            else
                cat "$ET_CONFIG_DIR/user.json" | tee -a "$LOG_FILE"
            fi
        else
            log "WARN" "user.json not found in backup, checking for legacy et-user.conf"
            if [ -f "$BACKUPS_DIR/et-user.conf" ]; then
                cp "$BACKUPS_DIR/et-user.conf" "$ET_CONFIG_DIR/user.conf"
                log "SUCCESS" "Legacy et-user.conf restored"
            fi
        fi
        
        # Copy et-mode if present
        if [ -f "$TEMP_EXTRACT/.config/emcomm-tools/et-mode" ]; then
            cp "$TEMP_EXTRACT/.config/emcomm-tools/et-mode" "$ET_CONFIG_DIR/et-mode"
            log "INFO" "et-mode preference restored: $(cat "$ET_CONFIG_DIR/et-mode")"
        fi
        
        # Copy Pat mailbox and forms if present
        if [ -d "$TEMP_EXTRACT/.local/share/pat" ]; then
            mkdir -p /etc/skel/.local/share/pat
            cp -r "$TEMP_EXTRACT/.local/share/pat"/* /etc/skel/.local/share/pat/
            log "SUCCESS" "Pat mailbox and forms restored"
        fi
        
        # Cleanup temp extraction
        rm -rf "$TEMP_EXTRACT"
    else
        log "ERROR" "Failed to extract et-user backup"
        exit 1
    fi
elif [ -f "$BACKUPS_DIR/et-user.conf" ]; then
    # Fallback: Handle legacy .conf file format
    log "INFO" "Restoring et-user configuration from legacy .conf file..."
    
    ET_CONFIG_DIR="/etc/skel/.config/emcomm-tools"
    mkdir -p "$ET_CONFIG_DIR"
    
    if cp "$BACKUPS_DIR/et-user.conf" "$ET_CONFIG_DIR/user.conf" 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "et-user configuration restored"
        
        # Extract and log key values
        log "INFO" "Configuration values:"
        grep -E "^(CALLSIGN|GRID|NAME)" "$ET_CONFIG_DIR/user.conf" 2>/dev/null | while read -r line; do
            log "INFO" "  $line"
        done
    else
        log "ERROR" "Failed to restore et-user configuration"
        exit 1
    fi
else
    log "INFO" "No et-user backup found (looking for et-user.tar.gz or et-user.conf), skipping"
fi

log "SUCCESS" "=== Backup Restore Complete ==="

if [ ! -d "$BACKUPS_DIR/wine" ] && [ ! -f "$BACKUPS_DIR/et-user.conf" ]; then
    log "INFO" "No backups were provided - users will need to configure manually"
fi
