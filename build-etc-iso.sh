#!/bin/bash
#
# Script Name: build-etc-iso.sh
# Description: Automated wrapper for building EmComm Tools Community ISO with Cubic
# Usage: ./build-etc-iso.sh [OPTIONS]
# Options:
#   -r MODE   Release mode: stable, latest, or tag (default: latest)
#   -t TAG    Specify release tag (required when -r tag)
#   -u PATH   Path to existing Ubuntu ISO (default: auto-download)
#   -b PATH   Path to .wine backup (default: ~/etc-wine-backup*.tar.gz)
#   -e PATH   Path to et-user backup (default: ~/etc-user-backup*.tar.gz)
#   -p PATH   Path to private files (local directory or GitHub repo URL)
#   -c        Cleanup mode: Remove embedded Ubuntu ISO from final build
#   -d        Dry-run mode (show what would be done)
#   -v        Verbose mode (enable set -x)
#   -h        Show this help message
# Author: KD7DGF
# Date: 2025-10-15
# Cubic Stage: No (orchestrates Cubic build process)
# Post-Install: No
#

set -euo pipefail

# Configuration
UBUNTU_ISO_URL="https://old-releases.ubuntu.com/releases/kinetic/ubuntu-22.10-desktop-amd64.iso"
UBUNTU_ISO_FILE="ubuntu-22.10-desktop-amd64.iso"
GITHUB_REPO="thetechprepper/emcomm-tools-os-community"
GITHUB_API_URL="https://api.github.com/repos/${GITHUB_REPO}/releases"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_BASE_DIR="${HOME}/etc-builds"
DOWNLOADS_DIR="${BUILD_BASE_DIR}/downloads"
DRY_RUN=0
CLEANUP_EMBEDDED_ISO=0
RELEASE_MODE="latest"  # stable, latest, or tag
SPECIFIED_TAG=""
UBUNTU_ISO_PATH=""
WINE_BACKUP_PATH=""
ET_USER_BACKUP_PATH=""
PRIVATE_FILES_PATH=""

# Logging
LOG_DIR="${BUILD_BASE_DIR}/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/build-etc-iso_$(date +'%Y%m%d_%H%M%S').log"

log() {
    local level="${1:-INFO}"
    local message="$2"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"
}

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Automated wrapper for building EmComm Tools Community ISO with Cubic.

OPTIONS:
    -r MODE   Release mode (default: latest)
              - stable: Use latest stable release from GitHub Releases
              - latest: Use latest tag (including pre-releases)
              - tag:    Use specific tag (requires -t)
    -t TAG    Specify release tag (e.g., emcomm-tools-os-community-20250401-r4-final-4.0.0)
              Required when -r tag
    -u PATH   Path to existing Ubuntu ISO file (skips download if provided)
    -b PATH   Path to .wine backup (tar.gz from et-user-backup or directory)
              Default: Auto-detect ~/etc-wine-backup-*.tar.gz
    -e PATH   Path to et-user backup (tar.gz from et-user-backup or directory)
              Default: Auto-detect ~/etc-user-backup-*.tar.gz
    -p PATH   Path to private files:
              - Local directory path: /path/to/private/files
              - GitHub repo: https://github.com/username/repo or git@github.com:username/repo.git
    -c        Cleanup mode: Remove embedded Ubuntu ISO from final build to save space
    -d        Dry-run mode (show what would be done without executing)
    -v        Verbose mode (enable bash debugging)
    -h        Show this help message

EXAMPLES:
    # Build latest stable release (from GitHub Releases)
    ./build-etc-iso.sh -r stable

    # Build latest tag (including pre-releases)
    ./build-etc-iso.sh -r latest

    # Build specific release with existing Ubuntu ISO
    ./build-etc-iso.sh -r tag -t emcomm-tools-os-community-20250401-r4-final-4.0.0 \\
        -u ~/Downloads/ubuntu-22.10-desktop-amd64.iso

    # Full build with backups and private files
    ./build-etc-iso.sh -r stable \\
        -b ~/etc-wine-backup-ETC-FZG1-20251015.tar.gz \\
        -e ~/etc-user-backup-ETC-FZG1-20251015.tar.gz \\
        -p ~/private-emcomm-files

    # Using private GitHub repo
    ./build-etc-iso.sh -r stable \\
        -p https://github.com/username/private-emcomm-configs

    # Build with auto-detected backups from home directory
    ./build-etc-iso.sh -r stable

    # Cleanup mode (remove embedded Ubuntu ISO to save space)
    ./build-etc-iso.sh -r stable -c

    # Dry-run to see what would happen
    ./build-etc-iso.sh -d

PREREQUISITES:
    - Cubic installed (sudo apt install cubic)
    - Internet connection
    - Sufficient disk space (~10GB for ISO + build artifacts)
    - secrets.env file configured in $(dirname "$0")
    - git (if using private GitHub repos)

NOTES:
    - Ubuntu ISO will be downloaded if not provided with -u
    - ETC installer tarball will be automatically downloaded
    - Project directory created at: ${BUILD_BASE_DIR}/<release-name>
    - Logs saved to: ${LOG_DIR}
    - Private files can be local directory or GitHub repo (public or private)
EOF
}

# Parse command-line options
while getopts ":r:t:u:b:e:p:cdvh" opt; do
    case $opt in
        r)
            RELEASE_MODE="$OPTARG"
            if [[ ! "$RELEASE_MODE" =~ ^(stable|latest|tag)$ ]]; then
                echo "ERROR: Invalid release mode: $RELEASE_MODE" >&2
                echo "Must be: stable, latest, or tag" >&2
                usage
                exit 1
            fi
            ;;
        t)
            SPECIFIED_TAG="$OPTARG"
            ;;
        u)
            UBUNTU_ISO_PATH="$OPTARG"
            ;;
        b)
            WINE_BACKUP_PATH="$OPTARG"
            ;;
        e)
            ET_USER_BACKUP_PATH="$OPTARG"
            ;;
        p)
            PRIVATE_FILES_PATH="$OPTARG"
            ;;
        c)
            CLEANUP_EMBEDDED_ISO=1
            log "INFO" "Cleanup mode enabled - will remove embedded Ubuntu ISO"
            ;;
        d)
            DRY_RUN=1
            log "INFO" "Dry-run mode enabled"
            ;;
        v)
            set -x
            log "INFO" "Verbose mode enabled"
            ;;
        h)
            usage
            exit 0
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            usage
            exit 1
            ;;
        :)
            echo "Option -$OPTARG requires an argument" >&2
            usage
            exit 1
            ;;
    esac
done

# Validate release mode and tag combination
if [[ "$RELEASE_MODE" == "tag" ]] && [[ -z "$SPECIFIED_TAG" ]]; then
    echo "ERROR: -r tag requires -t TAG to be specified" >&2
    usage
    exit 1
fi

# Helper function to execute or show commands
run_command() {
    local cmd="$*"
    if [ $DRY_RUN -eq 1 ]; then
        log "DRY-RUN" "Would execute: $cmd"
        return 0
    else
        log "INFO" "Executing: $cmd"
        eval "$cmd"
    fi
}

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    local missing=0
    
    # Check for required commands
    local required_commands=(curl jq wget)
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            log "ERROR" "Required command not found: $cmd"
            missing=1
        fi
    done
    
    # Check for Cubic (optional warning, as it's opened manually)
    if ! command -v cubic &>/dev/null; then
        log "WARN" "Cubic not found. Install with: sudo apt install cubic"
        log "WARN" "You can still use this script to prepare the build environment"
    fi
    
    # Check for internet connection
    if ! ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
        log "ERROR" "No internet connection detected"
        missing=1
    fi
    
    # Check for secrets.env (for customizations)
    if [ ! -f "$SCRIPT_DIR/secrets.env" ]; then
        log "WARN" "secrets.env not found - WiFi customizations will not be applied"
        log "WARN" "Copy secrets.env.template to secrets.env and configure it"
    fi
    
    return $missing
}

# Auto-detect backup files in home directory
auto_detect_backups() {
    log "INFO" "Auto-detecting backup files in home directory..."
    
    # Auto-detect .wine backup
    if [ -z "$WINE_BACKUP_PATH" ]; then
        local wine_backup
        # Use find instead of ls for better handling
        wine_backup=$(find ~ -maxdepth 1 -name "etc-wine-backup-*.tar.gz" -type f -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2)
        if [ -n "$wine_backup" ]; then
            WINE_BACKUP_PATH="$wine_backup"
            log "SUCCESS" "Auto-detected .wine backup: $wine_backup"
        else
            log "WARN" "No .wine backup found in home directory"
            echo ""
            echo "To create .wine backup on your ETC system:"
            echo "  ~/add-ons/wine/05-backup-wine-install.sh"
            echo ""
            read -r -p "Do you want to continue without .wine backup? (y/N): " response
            if [[ ! "$response" =~ ^[Yy]$ ]]; then
                log "INFO" "Please create .wine backup and re-run this script"
                exit 0
            fi
        fi
    fi
    
    # Auto-detect et-user backup
    if [ -z "$ET_USER_BACKUP_PATH" ]; then
        local etuser_backup
        # Use find instead of ls for better handling
        etuser_backup=$(find ~ -maxdepth 1 -name "etc-user-backup-*.tar.gz" -type f -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2)
        if [ -n "$etuser_backup" ]; then
            ET_USER_BACKUP_PATH="$etuser_backup"
            log "SUCCESS" "Auto-detected et-user backup: $etuser_backup"
        else
            log "WARN" "No et-user backup found in home directory"
            echo ""
            echo "To create et-user backup on your ETC system:"
            echo "  et-user-backup"
            echo ""
            read -r -p "Do you want to continue without et-user backup? (y/N): " response
            if [[ ! "$response" =~ ^[Yy]$ ]]; then
                log "INFO" "Please create et-user backup and re-run this script"
                exit 0
            fi
        fi
    fi
}

# Fetch release info based on mode
# Note: The ETC project publishes source code archives via GitHub's API (tarball_url)
# These contain the install.sh scripts needed to build the ISO via Cubic
get_release_info() {
    log "INFO" "Fetching release information from GitHub..."
    log "INFO" "Release mode: $RELEASE_MODE"
    
    case "$RELEASE_MODE" in
        stable)
            log "INFO" "Fetching latest stable release from GitHub Releases..."
            if ! RELEASE_JSON=$(curl -s -f "${GITHUB_API_URL}/latest"); then
                log "ERROR" "Failed to fetch latest stable release"
                return 1
            fi
            ;;
        latest)
            log "INFO" "Fetching latest release (most recent tag)..."
            # Fetch all releases and use the first one (most recent)
            if ! ALL_RELEASES=$(curl -s -f "${GITHUB_API_URL}?per_page=1"); then
                log "ERROR" "Failed to fetch latest release"
                return 1
            fi
            RELEASE_JSON=$(echo "$ALL_RELEASES" | jq '.[0]')
            ;;
        tag)
            log "INFO" "Using specified tag: $SPECIFIED_TAG"
            if ! RELEASE_JSON=$(curl -s -f "${GITHUB_API_URL}/tags/${SPECIFIED_TAG}"); then
                log "ERROR" "Failed to fetch release info for tag: $SPECIFIED_TAG"
                return 1
            fi
            ;;
    esac
    
    # Extract release details from GitHub API response
    RELEASE_TAG=$(echo "$RELEASE_JSON" | jq -r '.tag_name // "unknown"')
    RELEASE_NAME=$(echo "$RELEASE_JSON" | jq -r '.name // .tag_name // "unknown"')
    RELEASE_DATE=$(echo "$RELEASE_JSON" | jq -r '.published_at // .created_at // "unknown"' | cut -d'T' -f1)
    
    # GitHub automatically provides tarball_url for every release
    # This is the source code archive containing the install.sh scripts
    TARBALL_URL=$(echo "$RELEASE_JSON" | jq -r '.tarball_url // "null"')
    
    if [ -z "$TARBALL_URL" ] || [ "$TARBALL_URL" = "null" ]; then
        log "ERROR" "Failed to get tarball URL from GitHub API for release: $RELEASE_TAG"
        return 1
    fi
    
    # GitHub tarball URL format: https://api.github.com/repos/.../tarball/TAG
    # Convert to a more descriptive filename
    TARBALL_FILE="${RELEASE_TAG}.tar.gz"
    
    # Parse version info from tag
    # Tag format: emcomm-tools-os-community-YYYYMMDD-rX-final-X.X.X
    # Example: emcomm-tools-os-community-20250401-r4-final-4.0.0
    VERSION=$(echo "$RELEASE_TAG" | grep -oP '\d+\.\d+\.\d+$' || echo "unknown")
    DATE_VERSION=$(echo "$RELEASE_TAG" | grep -oP '\d{8}' || echo "unknown")
    RELEASE_NUMBER=$(echo "$RELEASE_TAG" | grep -oP 'r\d+' || echo "r0")
    
    # Construct project directory name
    PROJECT_DIR="${BUILD_BASE_DIR}/${RELEASE_TAG}"
    
    log "SUCCESS" "Release found: $RELEASE_NAME"
    log "INFO" "Tag: $RELEASE_TAG"
    log "INFO" "Version: $VERSION"
    log "INFO" "Published: $RELEASE_DATE"
    log "INFO" "Tarball: $TARBALL_FILE"
    
    return 0
}

# Check if ISO exists on Ventoy drive
find_iso_on_ventoy() {
    local iso_filename="$1"
    local ventoy_path
    
    # Try to auto-detect Ventoy mount
    if ventoy_path=$(findmnt -rn -S LABEL=Ventoy -o TARGET 2>/dev/null || true); then
        if [ -n "$ventoy_path" ] && [ -f "$ventoy_path/$iso_filename" ]; then
            log "SUCCESS" "Found Ubuntu ISO on Ventoy: $ventoy_path/$iso_filename"
            printf '%s' "$ventoy_path/$iso_filename"
            return 0
        fi
    fi
    
    # Check common Ventoy mount locations
    local candidates=(
        "/media/$USER/Ventoy"
        "/run/media/$USER/Ventoy"
        "/mnt/Ventoy"
        "/Volumes/Ventoy"
    )
    
    for candidate in "${candidates[@]}"; do
        if [ -f "$candidate/$iso_filename" ]; then
            log "SUCCESS" "Found Ubuntu ISO on Ventoy: $candidate/$iso_filename"
            printf '%s' "$candidate/$iso_filename"
            return 0
        fi
    done
    
    return 1
}

# Download or verify Ubuntu ISO
download_ubuntu_iso() {
    mkdir -p "$DOWNLOADS_DIR"
    
    # Use provided path or download location
    if [ -n "$UBUNTU_ISO_PATH" ]; then
        if [ ! -f "$UBUNTU_ISO_PATH" ]; then
            log "ERROR" "Specified Ubuntu ISO not found: $UBUNTU_ISO_PATH"
            return 1
        fi
        log "SUCCESS" "Using provided Ubuntu ISO: $UBUNTU_ISO_PATH"
        # Create symlink in downloads dir for consistency
        local iso_path="${DOWNLOADS_DIR}/${UBUNTU_ISO_FILE}"
        if [ ! -L "$iso_path" ]; then
            ln -sf "$UBUNTU_ISO_PATH" "$iso_path"
            log "INFO" "Created symlink: $iso_path -> $UBUNTU_ISO_PATH"
        fi
        return 0
    fi
    
    local iso_path="${DOWNLOADS_DIR}/${UBUNTU_ISO_FILE}"
    
    if [ -f "$iso_path" ]; then
        log "INFO" "Ubuntu ISO already downloaded: $iso_path"
        return 0
    fi
    
    # Check Ventoy before downloading
    local ventoy_iso
    if ventoy_iso=$(find_iso_on_ventoy "$UBUNTU_ISO_FILE"); then
        log "INFO" "Copying Ubuntu ISO from Ventoy to downloads..."
        if [ $DRY_RUN -eq 0 ]; then
            if cp "$ventoy_iso" "$iso_path"; then
                log "SUCCESS" "Ubuntu ISO copied from Ventoy"
                return 0
            else
                log "WARN" "Failed to copy from Ventoy, will attempt download"
            fi
        else
            log "DRY-RUN" "Would copy from Ventoy: $ventoy_iso to $iso_path"
            return 0
        fi
    fi
    
    log "INFO" "Downloading Ubuntu 22.10 ISO..."
    log "INFO" "URL: $UBUNTU_ISO_URL"
    log "INFO" "This may take several minutes (3.6 GB)..."
    
    if [ $DRY_RUN -eq 0 ]; then
        if ! wget -c -O "$iso_path" "$UBUNTU_ISO_URL"; then
            log "ERROR" "Failed to download Ubuntu ISO"
            return 1
        fi
        log "SUCCESS" "Ubuntu ISO downloaded successfully"
    else
        log "DRY-RUN" "Would download Ubuntu ISO to: $iso_path"
    fi
    
    return 0
}

# Download ETC installer tarball
download_etc_installer() {
    mkdir -p "$DOWNLOADS_DIR"
    
    local tarball_path="${DOWNLOADS_DIR}/${TARBALL_FILE}"
    
    if [ -f "$tarball_path" ]; then
        log "INFO" "ETC installer tarball already downloaded: $tarball_path"
        return 0
    fi
    
    log "INFO" "Downloading ETC installer tarball..."
    log "INFO" "URL: $TARBALL_URL"
    
    if [ $DRY_RUN -eq 0 ]; then
        if ! wget -O "$tarball_path" "$TARBALL_URL"; then
            log "ERROR" "Failed to download ETC installer tarball"
            return 1
        fi
        log "SUCCESS" "ETC installer tarball downloaded successfully"
    else
        log "DRY-RUN" "Would download ETC tarball to: $tarball_path"
    fi
    
    return 0
}

# Extract ETC installer tarball into project directory
extract_etc_installer() {
    local tarball_path="${DOWNLOADS_DIR}/${TARBALL_FILE}"
    local extract_dir="${PROJECT_DIR}/etc-source"
    
    if [ ! -f "$tarball_path" ]; then
        log "ERROR" "ETC installer tarball not found: $tarball_path"
        return 1
    fi
    
    if [ -d "$extract_dir" ]; then
        log "INFO" "ETC installer already extracted: $extract_dir"
        return 0
    fi
    
    log "INFO" "Extracting ETC installer tarball..."
    log "INFO" "Source: $tarball_path"
    log "INFO" "Destination: $extract_dir"
    
    if [ $DRY_RUN -eq 0 ]; then
        mkdir -p "$extract_dir"
        
        # GitHub tarballs extract to a directory like 'owner-repo-hash'
        # We need to extract and handle the directory structure
        if ! tar -xzf "$tarball_path" -C "$extract_dir" 2>&1 | tee -a "$LOG_FILE"; then
            log "ERROR" "Failed to extract ETC installer tarball"
            return 1
        fi
        
        # Find the extracted directory (GitHub creates owner-repo-hash/ directory)
        local extracted_dir
        extracted_dir=$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | head -1)
        
        if [ -z "$extracted_dir" ]; then
            log "ERROR" "Failed to find extracted directory in: $extract_dir"
            return 1
        fi
        
        # Move contents up one level for easier access
        log "INFO" "Organizing extracted files..."
        if ! mv "$extracted_dir"/* "$extract_dir/" 2>&1 | tee -a "$LOG_FILE"; then
            log "WARN" "Some files may not have been moved (this is usually OK)"
        fi
        
        # Remove the now-empty subdirectory if it exists
        rmdir "$extracted_dir" 2>/dev/null || true
        
        log "SUCCESS" "ETC installer tarball extracted successfully"
        log "INFO" "Scripts available at: $extract_dir/scripts/"
    else
        log "DRY-RUN" "Would extract: $tarball_path to: $extract_dir"
    fi
    
    return 0
}

# Prepare private files
prepare_private_files() {
    if [ -z "$PRIVATE_FILES_PATH" ]; then
        log "INFO" "No private files specified, skipping"
        return 0
    fi
    
    local private_dir="${PROJECT_DIR}/private-files"
    mkdir -p "$private_dir"
    
    log "INFO" "Preparing private files..."
    
    # Check if it's a GitHub repo URL
    if [[ "$PRIVATE_FILES_PATH" =~ ^(https://github\.com/|git@github\.com:) ]]; then
        log "INFO" "Cloning private GitHub repo: $PRIVATE_FILES_PATH"
        
        if [ $DRY_RUN -eq 0 ]; then
            if ! git clone "$PRIVATE_FILES_PATH" "$private_dir" 2>&1 | tee -a "$LOG_FILE"; then
                log "ERROR" "Failed to clone private repo"
                log "WARN" "Ensure you have SSH keys configured or use HTTPS with token"
                return 1
            fi
            log "SUCCESS" "Private repo cloned successfully"
        else
            log "DRY-RUN" "Would clone: $PRIVATE_FILES_PATH to: $private_dir"
        fi
    # Check if it's a local directory
    elif [ -d "$PRIVATE_FILES_PATH" ]; then
        log "INFO" "Copying private files from local directory: $PRIVATE_FILES_PATH"
        
        if [ $DRY_RUN -eq 0 ]; then
            if ! cp -r "$PRIVATE_FILES_PATH"/* "$private_dir/" 2>&1 | tee -a "$LOG_FILE"; then
                log "ERROR" "Failed to copy private files"
                return 1
            fi
            log "SUCCESS" "Private files copied successfully"
        else
            log "DRY-RUN" "Would copy: $PRIVATE_FILES_PATH/* to: $private_dir/"
        fi
    else
        log "ERROR" "Private files path is not a valid directory or GitHub URL: $PRIVATE_FILES_PATH"
        return 1
    fi
    
    log "INFO" "Private files ready at: $private_dir"
    return 0
}

# Prepare backup files
prepare_backups() {
    local backups_dir="${PROJECT_DIR}/backups"
    mkdir -p "$backups_dir"
    
    # Prepare .wine backup
    if [ -n "$WINE_BACKUP_PATH" ]; then
        log "INFO" "Preparing .wine backup..."
        
        # Check if it's a tar.gz file (from et-user-backup)
        if [[ "$WINE_BACKUP_PATH" == *.tar.gz ]]; then
            if [ ! -f "$WINE_BACKUP_PATH" ]; then
                log "ERROR" ".wine backup file not found: $WINE_BACKUP_PATH"
                return 1
            fi
            
            local wine_backup="${backups_dir}/wine.tar.gz"
            if [ $DRY_RUN -eq 0 ]; then
                if ! cp "$WINE_BACKUP_PATH" "$wine_backup" 2>&1 | tee -a "$LOG_FILE"; then
                    log "ERROR" "Failed to copy .wine backup"
                    return 1
                fi
                log "SUCCESS" ".wine backup (tar.gz) copied to: $wine_backup"
            else
                log "DRY-RUN" "Would copy .wine backup: $WINE_BACKUP_PATH to: $wine_backup"
            fi
        # Check if it's a directory
        elif [ -d "$WINE_BACKUP_PATH" ]; then
            local wine_backup="${backups_dir}/wine.tar.gz"
            if [ $DRY_RUN -eq 0 ]; then
                # Create tar.gz from directory
                log "INFO" "Creating tar.gz from directory..."
                if ! tar -czf "$wine_backup" -C "$(dirname "$WINE_BACKUP_PATH")" "$(basename "$WINE_BACKUP_PATH")" 2>&1 | tee -a "$LOG_FILE"; then
                    log "ERROR" "Failed to create .wine backup tar.gz"
                    return 1
                fi
                log "SUCCESS" ".wine backup archived to: $wine_backup"
            else
                log "DRY-RUN" "Would archive .wine directory: $WINE_BACKUP_PATH to: $wine_backup"
            fi
        else
            log "ERROR" ".wine backup path is not a file or directory: $WINE_BACKUP_PATH"
            return 1
        fi
    fi
    
    # Prepare et-user backup
    if [ -n "$ET_USER_BACKUP_PATH" ]; then
        log "INFO" "Preparing et-user backup..."
        
        # Check if it's a tar.gz file (from et-user-backup)
        if [[ "$ET_USER_BACKUP_PATH" == *.tar.gz ]]; then
            if [ ! -f "$ET_USER_BACKUP_PATH" ]; then
                log "ERROR" "et-user backup file not found: $ET_USER_BACKUP_PATH"
                return 1
            fi
            
            local etuser_backup="${backups_dir}/et-user.tar.gz"
            if [ $DRY_RUN -eq 0 ]; then
                if ! cp "$ET_USER_BACKUP_PATH" "$etuser_backup" 2>&1 | tee -a "$LOG_FILE"; then
                    log "ERROR" "Failed to copy et-user backup"
                    return 1
                fi
                log "SUCCESS" "et-user backup (tar.gz) copied to: $etuser_backup"
            else
                log "DRY-RUN" "Would copy et-user backup: $ET_USER_BACKUP_PATH to: $etuser_backup"
            fi
        # Check if it's a directory (legacy format)
        elif [ -d "$ET_USER_BACKUP_PATH" ]; then
            local etuser_backup="${backups_dir}/et-user.tar.gz"
            if [ $DRY_RUN -eq 0 ]; then
                # Create tar.gz from directory
                log "INFO" "Creating tar.gz from directory..."
                if ! tar -czf "$etuser_backup" -C "$(dirname "$ET_USER_BACKUP_PATH")" "$(basename "$ET_USER_BACKUP_PATH")" 2>&1 | tee -a "$LOG_FILE"; then
                    log "ERROR" "Failed to create et-user backup tar.gz"
                    return 1
                fi
                log "SUCCESS" "et-user backup archived to: $etuser_backup"
            else
                log "DRY-RUN" "Would archive et-user directory: $ET_USER_BACKUP_PATH to: $etuser_backup"
            fi
        # Check if it's a legacy .conf file
        elif [ -f "$ET_USER_BACKUP_PATH" ] && [[ "$ET_USER_BACKUP_PATH" == *.conf ]]; then
            local etuser_backup="${backups_dir}/et-user.conf"
            if [ $DRY_RUN -eq 0 ]; then
                if ! cp "$ET_USER_BACKUP_PATH" "$etuser_backup" 2>&1 | tee -a "$LOG_FILE"; then
                    log "ERROR" "Failed to copy et-user backup"
                    return 1
                fi
                log "SUCCESS" "et-user backup (legacy .conf) copied to: $etuser_backup"
            else
                log "DRY-RUN" "Would copy et-user backup: $ET_USER_BACKUP_PATH to: $etuser_backup"
            fi
        else
            log "ERROR" "et-user backup path is not a recognized format: $ET_USER_BACKUP_PATH"
            return 1
        fi
    fi
    
    if [ -z "$WINE_BACKUP_PATH" ] && [ -z "$ET_USER_BACKUP_PATH" ]; then
        log "INFO" "No backup files specified, skipping"
    fi
    
    return 0
}

# Create project directory
create_project_directory() {
    if [ -d "$PROJECT_DIR" ]; then
        log "WARN" "Project directory already exists: $PROJECT_DIR"
        read -r -p "Delete and recreate? (y/N): " response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            run_command rm -rf "$PROJECT_DIR"
        else
            log "INFO" "Using existing project directory"
            return 0
        fi
    fi
    
    log "INFO" "Creating project directory: $PROJECT_DIR"
    run_command mkdir -p "$PROJECT_DIR"
    
    return 0
}

# Generate Cubic instructions
generate_cubic_instructions() {
    local instructions_file="${PROJECT_DIR}/CUBIC_INSTRUCTIONS.md"
    
    log "INFO" "Generating Cubic instructions: $instructions_file"
    
    if [ $DRY_RUN -eq 1 ]; then
        log "DRY-RUN" "Would create: $instructions_file"
        return 0
    fi
    
    # Add cleanup mode instructions if flag is set
    local cleanup_instructions=""
    if [ $CLEANUP_EMBEDDED_ISO -eq 1 ]; then
        cleanup_instructions="
### 5.8 Remove Embedded Ubuntu ISO (Cleanup Mode)

**Note**: Cleanup mode was specified with -c flag.

\`\`\`bash
# Remove embedded ISO to save space (~3.6 GB)
rm -f /opt/emcomm-resources/ubuntu-*.iso
\`\`\`
"
    fi
    
    cat > "$instructions_file" <<EOF
# Cubic Build Instructions for ${RELEASE_TAG}

Generated: $(date +'%Y-%m-%d %H:%M:%S')

## Step 1: Launch Cubic

\`\`\`bash
cubic
\`\`\`

## Step 2: Select Project Directory

Click the folder icon and select:
\`${PROJECT_DIR}\`

Click **Next**.

## Step 3: Select Original Disk

Under "Select the original disk", click the folder icon and select:
\`${DOWNLOADS_DIR}/${UBUNTU_ISO_FILE}\`

## Step 4: Configure Custom Disk

Update the following fields:

- **Version**: \`${DATE_VERSION}.${RELEASE_NUMBER}-final\`
- **Filename**: \`${RELEASE_TAG}.iso\`
- **Volume ID**: \`ETC_${RELEASE_NUMBER^^}_FINAL\`
- **Release**: \`TTP\`
- **Disk Name**: \`ETC_${RELEASE_NUMBER^^}_FINAL "TTP"\`
- **Release URL**: \`https://community.emcommtools.com\`

Click **Next** and wait for extraction to complete.

## Step 5: In Cubic Virtual Terminal

### 5.1 Download ETC Installer

\`\`\`bash
wget https://github.com/${GITHUB_REPO}/releases/download/${RELEASE_TAG}/${TARBALL_FILE}
\`\`\`

### 5.2 Extract Installer

\`\`\`bash
tar -xzf ${TARBALL_FILE}
cd emcomm-tools-os-community/scripts
\`\`\`

### 5.3 Run Installer

**Note**: This can take 1+ hour depending on your system and internet connection.

\`\`\`bash
./install.sh
\`\`\`

### 5.4 Optional: Download State Map

Use arrow keys to select your state, or press ESC to skip.

### 5.5 Run Customizations (KD7DGF)

**Copy customization scripts into Cubic environment:**

From your HOST machine (not Cubic terminal), copy files:

\`\`\`bash
# From the Cubic GUI, use the copy icon (upper-left corner) to copy:
# - ${SCRIPT_DIR}/cubic/*.sh
# - ${SCRIPT_DIR}/secrets.env (if configured)
# - ${PROJECT_DIR}/private-files/* (if private files specified)
# - ${PROJECT_DIR}/backups/* (if backups specified)
\`\`\`

**In Cubic terminal, run customizations:**

\`\`\`bash
cd /root  # Or wherever you copied the scripts

# Run Cubic customization scripts in order:
# (Scripts already have execute permissions, just run them directly)

./install-dev-tools.sh
./install-ham-tools.sh
./configure-aprs-apps.sh
./setup-desktop-defaults.sh
./setup-user-and-hostname.sh
./configure-wifi.sh
./configure-radio-defaults.sh
./restore-backups.sh  # Only if backups were provided
./install-private-files.sh  # Only if private files were provided
./embed-ubuntu-iso.sh
./finalize-build.sh
\`\`\`

### 5.6 Run Validation Tests

\`\`\`bash
cd ../tests
./run-test-suite.sh
\`\`\`

Review test results and resolve any failures before continuing.
${cleanup_instructions}
### 5.7 Exit Virtual Terminal

Click **Next** to continue.

## Step 6: Package Selection

- Do **NOT** change anything on "Select packages to be automatically removed" screen
- Click **Next**

- Do **NOT** change anything on "Select packages..." screen  
- Click **Next**

## Step 7: Boot Menu (Optional)

On the Boot tab, optionally change:
- From: "Try or Install Ubuntu"
- To: "Try or Install ETC_${RELEASE_NUMBER^^}_Final"

Click **Next**.

## Step 8: Generate ISO

Click **Generate** on the compression options screen.

**Note**: This can take 5 minutes to 1+ hour depending on your machine.

## Step 9: Complete

When finished, your ISO will be at:
\`${PROJECT_DIR}/${RELEASE_TAG}.iso\`

Click **Close** to finish.

## Step 10: Copy ISO to Ventoy Drive

1. Prepare a Ventoy USB drive once using the official installer (https://www.ventoy.net/en/index.html).
2. Mount the Ventoy data partition on your build system (usually `/media/$USER/Ventoy`).
3. Copy the generated ISO onto the Ventoy partition:

```bash
cp "${PROJECT_DIR}/${RELEASE_TAG}.iso" /media/$USER/Ventoy/
sync
```

4. Alternatively, run `${SCRIPT_DIR}/copy-iso-to-ventoy.sh "${PROJECT_DIR}/${RELEASE_TAG}.iso"` to auto-detect the Ventoy mount point and copy the ISO for you.
5. Safely eject the Ventoy drive. Ventoy will list the new ISO on next boot.

---

**Build Information:**
- Release: ${RELEASE_NAME}
- Version: ${VERSION}
- Tag: ${RELEASE_TAG}
- Published: ${RELEASE_DATE}
- Build Date: $(date +'%Y-%m-%d %H:%M:%S')
$(if [ $CLEANUP_EMBEDDED_ISO -eq 1 ]; then echo "- Cleanup Mode: ENABLED (embedded ISO will be removed)"; fi)
EOF

    log "SUCCESS" "Cubic instructions generated"
    return 0
}

# Generate build summary
generate_build_summary() {
    local summary_file="${PROJECT_DIR}/BUILD_SUMMARY.txt"
    
    log "INFO" "Generating build summary: $summary_file"
    
    if [ $DRY_RUN -eq 1 ]; then
        log "DRY-RUN" "Would create: $summary_file"
        return 0
    fi
    
    cat > "$summary_file" <<EOF
EmComm Tools Community ISO Build Summary
Generated: $(date +'%Y-%m-%d %H:%M:%S')

=== RELEASE INFORMATION ===
Release Name:    ${RELEASE_NAME}
Release Tag:     ${RELEASE_TAG}
Version:         ${VERSION}
Published Date:  ${RELEASE_DATE}

=== BUILD PATHS ===
Project Directory:  ${PROJECT_DIR}
Downloads Directory: ${DOWNLOADS_DIR}
Ubuntu ISO:         ${DOWNLOADS_DIR}/${UBUNTU_ISO_FILE}
ETC Tarball:        ${DOWNLOADS_DIR}/${TARBALL_FILE}
Output ISO:         ${PROJECT_DIR}/${RELEASE_TAG}.iso

=== NEXT STEPS ===
1. Review Cubic instructions: ${PROJECT_DIR}/CUBIC_INSTRUCTIONS.md
2. Launch Cubic: cubic
3. Follow the step-by-step instructions
4. Copy resulting ISO to Ventoy USB (`${SCRIPT_DIR}/copy-iso-to-ventoy.sh ${PROJECT_DIR}/${RELEASE_TAG}.iso` or `cp ${PROJECT_DIR}/${RELEASE_TAG}.iso /media/$USER/Ventoy/ && sync`)

=== CUSTOMIZATION SCRIPTS ===
Located in: ${SCRIPT_DIR}/cubic/

These scripts should be copied into the Cubic environment and run:
$(if [ -d "${SCRIPT_DIR}/cubic" ]; then
    find "${SCRIPT_DIR}/cubic" -name "*.sh" -type f -exec basename {} \; 2>/dev/null | sort | nl -w2 -s'. '
else
    echo "  (cubic/ directory not yet created)"
fi)

Execution order:
1. install-dev-tools.sh - VS Code, uv, git, build essentials
2. install-ham-tools.sh - CHIRP, dmrconfig, flrig, LibreOffice
3. configure-aprs-apps.sh - direwolf/YAAC/Pat config (from secrets.env)
4. setup-desktop-defaults.sh - GNOME dark mode, accessibility
5. setup-user-and-hostname.sh - User creation and hostname (ETC-{CALLSIGN})
6. configure-wifi.sh - WiFi pre-configuration (requires secrets.env)
7. configure-radio-defaults.sh - Radio presets (BTech/Anytone)
8. restore-backups.sh - .wine and et-user restore (if provided)
9. install-private-files.sh - Private files (if provided)
10. embed-ubuntu-iso.sh - Embed Ubuntu ISO for future builds
11. finalize-build.sh - Cleanup and manifest generation

Note: If cleanup mode (-c) is used, add this step before creating ISO:
  12. Remove embedded Ubuntu ISO: rm -f /opt/emcomm-resources/ubuntu-*.iso

=== SECRETS CONFIGURATION ===
WiFi Configuration: ${SCRIPT_DIR}/secrets.env
$(if [ -f "${SCRIPT_DIR}/secrets.env" ]; then
    echo "Status: ✓ Configured"
else
    echo "Status: ✗ Not configured (WiFi will not be pre-configured)"
fi)

=== LOGS ===
Build log: ${LOG_FILE}

---
Built by: $(whoami)
Hostname: $(hostname)
EOF

    log "SUCCESS" "Build summary generated"
    return 0
}

# Main execution
main() {
    log "INFO" "=== EmComm Tools Community ISO Build Script ==="
    log "INFO" "Script started at $(date)"
    
    # Auto-detect backups if not provided
    auto_detect_backups
    
    # Check prerequisites
    if ! check_prerequisites; then
        log "ERROR" "Prerequisites check failed"
        exit 2
    fi
    
    # Get release information
    if ! get_release_info; then
        log "ERROR" "Failed to get release information"
        exit 1
    fi
    
    # Download Ubuntu ISO
    if ! download_ubuntu_iso; then
        log "ERROR" "Failed to download Ubuntu ISO"
        exit 1
    fi
    
    # Download ETC installer
    if ! download_etc_installer; then
        log "ERROR" "Failed to download ETC installer"
        exit 1
    fi
    
    # Create project directory (needed for tarball extraction)
    if ! create_project_directory; then
        log "ERROR" "Failed to create project directory"
        exit 1
    fi
    
    # Extract ETC installer tarball
    if ! extract_etc_installer; then
        log "ERROR" "Failed to extract ETC installer"
        exit 1
    fi
    
    # Prepare private files
    if ! prepare_private_files; then
        log "ERROR" "Failed to prepare private files"
        exit 1
    fi
    
    # Prepare backups
    if ! prepare_backups; then
        log "ERROR" "Failed to prepare backups"
        exit 1
    fi
    
    # Generate Cubic instructions
    if ! generate_cubic_instructions; then
        log "ERROR" "Failed to generate Cubic instructions"
        exit 1
    fi
    
    # Generate build summary
    if ! generate_build_summary; then
        log "ERROR" "Failed to generate build summary"
        exit 1
    fi
    
    log "SUCCESS" "=== Build preparation complete ==="
    log "INFO" ""
    log "INFO" "Next steps:"
    log "INFO" "1. Review instructions: ${PROJECT_DIR}/CUBIC_INSTRUCTIONS.md"
    log "INFO" "2. Launch Cubic: cubic"
    log "INFO" "3. Select project directory: ${PROJECT_DIR}"
    log "INFO" ""
    log "INFO" "Build summary: ${PROJECT_DIR}/BUILD_SUMMARY.txt"
    log "INFO" "Log file: ${LOG_FILE}"
    
    if [ ! -f "$SCRIPT_DIR/secrets.env" ]; then
        log "WARN" ""
        log "WARN" "⚠️  secrets.env not found!"
        log "WARN" "WiFi will NOT be pre-configured in the ISO."
        log "WARN" "Copy secrets.env.template to secrets.env and configure it."
    fi
}

# Run main function
main "$@"
