#!/bin/bash
#
# Script Name: restore-backups.sh
# Description: Captures current et-user state and restores backups during Cubic ISO build
# Usage: Run in Cubic chroot environment
# Author: KD7DGF
# Date: 2025-11-28
# Cubic Stage: Yes (runs during ISO build)
# Post-Install: No
#
# Strategy:
# 1. Capture current et-user config (if upgrading from previous deployment)
# 2. Restore wine.tar.gz baseline (VARA FM - static golden master)
# 3. Restore et-user config from previous run (preserves callsign, grid square, etc.)

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
BACKUPS_DIR="$HOME/ETC-Customizer-Backups"

# Ensure backup directory exists (create if needed)
if [ ! -d "$BACKUPS_DIR" ]; then
    log "WARN" "Backup directory not found: $BACKUPS_DIR"
    log "WARN" "Creating directory... (Note: You may need to populate it with wine.tar.gz and et-user.tar.gz)"
    mkdir -p "$BACKUPS_DIR"
fi

# STEP 1: Capture current et-user state (if this is an upgrade build)
# This ensures we preserve user customizations (callsign, grid square, etc.)
log "INFO" "=== Step 1: Capture Current et-user State ==="

if [ -d "$HOME/.config/emcomm-tools" ] || [ -d "$HOME/.local/share/pat" ]; then
    log "INFO" "Detected previous et-user configuration, capturing for preservation..."
    
    TEMP_CAPTURE="/tmp/et-user-capture-$(date +%s)"
    mkdir -p "$TEMP_CAPTURE/.config/emcomm-tools"
    mkdir -p "$TEMP_CAPTURE/.local/share"
    
    # Define backup path for current capture
    CURRENT_BACKUP="$BACKUPS_DIR/et-user-current.tar.gz"
    
    # Capture et-user config directory
    if [ -d "$HOME/.config/emcomm-tools" ]; then
        if cp -r "$HOME/.config/emcomm-tools" "$TEMP_CAPTURE/.config/" 2>&1 | tee -a "$LOG_FILE"; then
            log "SUCCESS" "Captured et-user config directory"
        else
            log "ERROR" "Failed to capture et-user config directory"
        fi
    fi
    
    # Capture Pat mailbox and forms
    if [ -d "$HOME/.local/share/pat" ]; then
        if cp -r "$HOME/.local/share/pat" "$TEMP_CAPTURE/.local/share/" 2>&1 | tee -a "$LOG_FILE"; then
            log "SUCCESS" "Captured Pat mailbox and forms"
        else
            log "ERROR" "Failed to capture Pat mailbox and forms"
        fi
    fi
    
    # Create backup from captured state
    if tar -czf "$CURRENT_BACKUP" -C "$TEMP_CAPTURE" . 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "Created et-user backup from current state: $CURRENT_BACKUP"
    else
        log "WARN" "Failed to create et-user backup, will use last known backup if available"
    fi
    
    rm -rf "$TEMP_CAPTURE"
else
    log "INFO" "No previous et-user configuration found, starting fresh"
fi

# STEP 2: Restore wine.tar.gz (VARA FM - static baseline)
# The wine backup is a golden master that never changes unless intentionally updated
log "INFO" "=== Step 2: Restore VARA FM Configuration ==="

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
        if [ -d "$WINE_DEST/drive_c/VARA FM" ]; then
            log "INFO" "  - VARA FM (VHF/UHF high-speed digital)"
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

# STEP 3: Restore et-user configuration (callsign, grid square, etc.)
# Try current backup first (from this session), then fall back to last known backup
log "INFO" "=== Step 3: Restore et-user Configuration ==="

ET_CONFIG_DIR="/etc/skel/.config/emcomm-tools"
LAST_BACKUP="$BACKUPS_DIR/et-user.tar.gz"

for backup_file in "$CURRENT_BACKUP" "$LAST_BACKUP"; do
    if [ -f "$backup_file" ]; then
        log "INFO" "Restoring et-user configuration from: $(basename "$backup_file")..."
        
        # Extract to temporary location
        TEMP_EXTRACT="/tmp/et-user-restore"
        mkdir -p "$TEMP_EXTRACT"
        
        if tar -xzf "$backup_file" -C "$TEMP_EXTRACT" 2>&1 | tee -a "$LOG_FILE"; then
            # Create et-user configuration directory in /etc/skel
            mkdir -p "$ET_CONFIG_DIR"
            
            # Copy et-user config directory
            if [ -d "$TEMP_EXTRACT/.config/emcomm-tools" ]; then
                cp -r "$TEMP_EXTRACT/.config/emcomm-tools"/* "$ET_CONFIG_DIR/" 2>&1 | tee -a "$LOG_FILE"
                log "SUCCESS" "et-user configuration restored"
                
                # Extract and log key values
                log "INFO" "Configuration values:"
                if [ -f "$ET_CONFIG_DIR/user.json" ] && command -v jq &>/dev/null; then
                    jq -r 'to_entries[] | "  \(.key): \(.value)"' "$ET_CONFIG_DIR/user.json" 2>/dev/null | tee -a "$LOG_FILE" || true
                elif [ -f "$ET_CONFIG_DIR/user.json" ]; then
                    cat "$ET_CONFIG_DIR/user.json" | tee -a "$LOG_FILE"
                fi
            fi
            
            # Copy Pat mailbox and forms if present
            if [ -d "$TEMP_EXTRACT/.local/share/pat" ]; then
                mkdir -p /etc/skel/.local/share/pat
                cp -r "$TEMP_EXTRACT/.local/share/pat"/* /etc/skel/.local/share/pat/ 2>&1 | tee -a "$LOG_FILE"
                log "SUCCESS" "Pat mailbox and forms restored"
            fi
            
            # Cleanup temp extraction
            rm -rf "$TEMP_EXTRACT"
            
            # Successfully restored, exit loop
            break
        else
            log "WARN" "Failed to extract from $backup_file, trying next backup..."
            rm -rf "$TEMP_EXTRACT"
            continue
        fi
    fi
done

# If no backup files were found
if [ ! -f "$CURRENT_BACKUP" ] && [ ! -f "$LAST_BACKUP" ]; then
    log "INFO" "No et-user backups found (looking for et-user-current.tar.gz or et-user.tar.gz), skipping"
fi

log "SUCCESS" "=== Backup Restore Complete ==="
