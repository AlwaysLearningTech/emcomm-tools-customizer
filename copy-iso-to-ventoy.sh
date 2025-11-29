#!/bin/bash
#
# Script Name: copy-iso-to-ventoy.sh
# Description: Detect a mounted Ventoy data partition and copy the latest ETC ISO onto it.
# Usage: ./copy-iso-to-ventoy.sh [PATH_TO_ISO]
# Author: KD7DGF
# Date: 2025-10-28
#
# Notes:
#   - If no ISO path is provided, the script locates the newest *.iso under ~/etc-builds/
#   - The script attempts to auto-detect a Ventoy mount point by label or common mount paths.
#   - Set VENTOY_PATH environment variable to override auto-detection.
#

set -euo pipefail

LOG_DIR="${HOME}/etc-builds/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/copy-iso-to-ventoy_$(date +'%Y%m%d_%H%M%S').log"

log() {
    local level="${1:-INFO}"
    local message="$2"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"
}

resolve_path() {
    local target="$1"

    if command -v realpath >/dev/null 2>&1; then
        realpath "$target"
        return $?
    fi

    if command -v readlink >/dev/null 2>&1; then
        local resolved
        if resolved=$(readlink -f "$target" 2>/dev/null); then
            printf '%s\n' "$resolved"
            return 0
        fi
    fi

    local dir
    dir=$(cd "$(dirname "$target")" >/dev/null 2>&1 && pwd -P) || return 1
    printf '%s/%s\n' "$dir" "$(basename "$target")"
}

# Locate the newest ISO within ~/etc-builds if user does not provide one.
detect_latest_iso() {
    local latest_iso
    if latest_iso=$(find "${HOME}/etc-builds" -maxdepth 3 -type f -name '*.iso' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-); then
        if [ -n "$latest_iso" ] && [ -f "$latest_iso" ]; then
            printf '%s' "$latest_iso"
            return 0
        fi
    fi
    return 1
}

# Attempt to locate a Ventoy mount point using several strategies.
detect_ventoy_mount() {
    local mount_path=""

    # 1. Use findmnt if available (preferred)
    if command -v findmnt >/dev/null 2>&1; then
        mount_path=$(findmnt -rn -S LABEL=Ventoy -o TARGET 2>/dev/null || true)
        if [ -z "$mount_path" ]; then
            mount_path=$(findmnt -rn -S LABEL=VENTOY -o TARGET 2>/dev/null || true)
        fi
        if [ -n "$mount_path" ] && [ -d "$mount_path" ]; then
            printf '%s' "$mount_path"
            return 0
        fi
    fi

    # 2. Fallback to lsblk parsing
    if command -v lsblk >/dev/null 2>&1; then
        mount_path=$(lsblk -o LABEL,MOUNTPOINT -nr 2>/dev/null | awk '$1 ~ /^(Ventoy|VENTOY)$/ && $2 != "" {print $2; exit}')
        if [ -n "$mount_path" ] && [ -d "$mount_path" ]; then
            printf '%s' "$mount_path"
            return 0
        fi
    fi

    # 3. Check common mount locations
    local candidates=(
        "/media/$USER/Ventoy"
        "/run/media/$USER/Ventoy"
        "/media/$USER/VENTOY"
        "/run/media/$USER/VENTOY"
        "/Volumes/Ventoy"
        "/Volumes/VENTOY"
        "/mnt/Ventoy"
        "/mnt/VENTOY"
    )

    for candidate in "${candidates[@]}"; do
        if [ -d "$candidate" ]; then
            if command -v mountpoint >/dev/null 2>&1; then
                if mountpoint -q "$candidate"; then
                    printf '%s' "$candidate"
                    return 0
                fi
            else
                # Fallback: verify the path is listed in mount output
                if mount | grep -F " on $candidate " >/dev/null 2>&1; then
                    printf '%s' "$candidate"
                    return 0
                fi
            fi
        fi
    done

    return 1
}

main() {
    local iso_path="${1:-}"
    local ventoy_path="${VENTOY_PATH:-}"

    log "INFO" "Starting Ventoy copy helper"

    # Determine ISO path if not provided
    if [ -z "$iso_path" ]; then
        if iso_path=$(detect_latest_iso); then
            log "INFO" "Auto-detected latest ISO: $iso_path"
        else
            log "ERROR" "No ISO provided and none found under ${HOME}/etc-builds"
            log "ERROR" "Usage: $(basename "$0") /path/to/iso"
            exit 1
        fi
    else
    iso_path=$(resolve_path "$iso_path")
    fi

    if [ ! -f "$iso_path" ]; then
        log "ERROR" "ISO not found: $iso_path"
        exit 1
    fi

    # Determine Ventoy path if not provided
    if [ -z "$ventoy_path" ]; then
        if ventoy_path=$(detect_ventoy_mount); then
            log "INFO" "Detected Ventoy mount: $ventoy_path"
        else
            log "WARN" "Unable to auto-detect Ventoy mount point"
            read -r -p "Enter Ventoy mount path (or leave empty to abort): " ventoy_path
            if [ -z "$ventoy_path" ]; then
                log "ERROR" "Ventoy path not provided. Aborting."
                exit 1
            fi
        fi
    fi

    ventoy_path=$(resolve_path "$ventoy_path")

    if [ ! -d "$ventoy_path" ]; then
        log "ERROR" "Ventoy path does not exist: $ventoy_path"
        exit 1
    fi

    if command -v mountpoint >/dev/null 2>&1; then
        if ! mountpoint -q "$ventoy_path"; then
            log "ERROR" "Ventoy path is not a mounted filesystem: $ventoy_path"
            exit 1
        fi
    fi

    local iso_filename
    iso_filename=$(basename "$iso_path")
    local destination="$ventoy_path/$iso_filename"

    if [ -f "$destination" ]; then
        log "WARN" "ISO already exists on Ventoy: $destination"
        read -r -p "Overwrite existing file? (y/N): " response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log "INFO" "User chose not to overwrite existing ISO"
            exit 0
        fi
    fi

    log "INFO" "Copying ISO to Ventoy: $destination"
    if command -v rsync >/dev/null 2>&1; then
        rsync --info=progress2 "$iso_path" "$destination" | tee -a "$LOG_FILE"
    else
        cp "$iso_path" "$destination"
    fi

    log "INFO" "Flushing writes to Ventoy"
    sync

    log "SUCCESS" "ISO copied to Ventoy"
    log "INFO" "Ventoy contents now include:"
    find "$ventoy_path" -maxdepth 1 -type f | tee -a "$LOG_FILE"
}

main "$@"
