#!/bin/bash
#
# Script Name: build-etc-iso.sh
# Description: Fully automated ETC ISO customization using xorriso/squashfs (no Cubic GUI)
# Usage: ./build-etc-iso.sh [OPTIONS]
# Options:
#   -r MODE   Release mode: stable, latest, or tag (default: latest)
#   -t TAG    Specify release tag (required when -r tag)
#   -l        List available tags from GitHub and exit
#   -d        Dry-run mode (show what would be done)
#   -v        Verbose mode (enable set -x)
#   -h        Show this help message
# Author: KD7DGF
# Date: 2025-11-29
# Method: Direct ISO modification via xorriso/squashfs (fully automated, no Cubic)
#

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_FILE="${SCRIPT_DIR}/secrets.env"

# GitHub repository info
GITHUB_REPO="thetechprepper/emcomm-tools-os-community"
GITHUB_API_BASE="https://api.github.com/repos/${GITHUB_REPO}"
GITHUB_RELEASES_URL="${GITHUB_API_BASE}/releases"
GITHUB_TAGS_URL="${GITHUB_API_BASE}/tags"

# Ubuntu ISO info
UBUNTU_ISO_URL="https://old-releases.ubuntu.com/releases/kinetic/ubuntu-22.10-desktop-amd64.iso"
UBUNTU_ISO_FILE="ubuntu-22.10-desktop-amd64.iso"

# Directory structure (relative to script)
CACHE_DIR="${SCRIPT_DIR}/cache"          # Downloaded files (ISOs, tarballs) - persists across builds
OUTPUT_DIR="${SCRIPT_DIR}/output"         # Generated ISOs
WORK_DIR="${SCRIPT_DIR}/.work"            # Temporary build directory (cleaned each build)

# Build state
DRY_RUN=0
RELEASE_MODE="latest"
SPECIFIED_TAG=""
MINIMAL_BUILD=0                           # When 1, omit cache files from ISO to reduce size

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Debug mode (set to 1 to see DEBUG messages on console)
DEBUG_MODE=0

# ============================================================================
# Logging
# ============================================================================

LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/build-etc-iso_$(date +'%Y%m%d_%H%M%S').log"

log() {
    local level="${1:-INFO}"
    local message="$2"
    local timestamp
    timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    
    # Always log to file (including DEBUG)
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    # Log to console with color (DEBUG only shown if DEBUG_MODE=1)
    case "$level" in
        ERROR)   echo -e "${RED}[$level]${NC} $message" ;;
        WARN)    echo -e "${YELLOW}[$level]${NC} $message" ;;
        SUCCESS) echo -e "${GREEN}[$level]${NC} $message" ;;
        INFO)    echo -e "${BLUE}[$level]${NC} $message" ;;
        DEBUG)   
            if [ $DEBUG_MODE -eq 1 ]; then
                echo -e "${CYAN}[$level]${NC} $message"
            fi
            ;;
        *)       echo "[$level] $message" ;;
    esac
}

# ============================================================================
# Usage
# ============================================================================

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Fully automated ETC ISO customization using xorriso/squashfs.
No Cubic GUI required - everything is scripted.

RELEASE OPTIONS:
    -r MODE   Release mode (default: latest)
              - stable: Latest formal GitHub Release (production-ready)
              - latest: Most recent git tag (development builds)
              - tag:    Use a specific tag by name (requires -t)
    -t TAG    Specify exact tag name (use -l to list available)
    -l        List available tags and releases, then exit

BUILD OPTIONS:
    -d        Dry-run mode (show what would be done without making changes)
    -m        Minimal build (omit cache files from ISO to reduce size)
    -v        Verbose mode (enable bash -x debugging)
    -D        Debug mode (show DEBUG log messages on console)
    -h        Show this help message

DIRECTORY STRUCTURE:
    cache/    Downloaded ISOs and tarballs (persistent)
              - Drop your Ubuntu ISO here to skip download
              - ETC tarballs are cached here too
    output/   Generated custom ISOs
    logs/     Build logs (DEBUG messages always written here)

BUILD SIZE:
    By default, cache files (Ubuntu ISO, ETC tarballs) are embedded in the
    output ISO so they're available for the next build on the installed system.
    Use -m for a minimal build that excludes these files (saves ~4GB).

PREREQUISITES:
    sudo apt install xorriso squashfs-tools wget curl jq

EXAMPLES:
    # List available releases
    ./build-etc-iso.sh -l

    # Build from stable release (recommended)
    sudo ./build-etc-iso.sh -r stable

    # Build from latest development tag
    sudo ./build-etc-iso.sh -r latest

    # Build specific version
    sudo ./build-etc-iso.sh -r tag -t emcomm-tools-os-community-20251113-r5-build17

    # Build with debug output for troubleshooting
    sudo ./build-etc-iso.sh -r stable -D

    # Minimal build (smaller ISO, no embedded cache)
    sudo ./build-etc-iso.sh -r stable -m

EOF
}

# ============================================================================
# GitHub API Functions
# ============================================================================

list_available_versions() {
    echo ""
    echo "=== Available ETC Releases ==="
    echo ""
    
    echo "STABLE RELEASES (GitHub Releases - production ready):"
    echo "------------------------------------------------------"
    if RELEASES_JSON=$(curl -s -f "${GITHUB_RELEASES_URL}?per_page=5" 2>/dev/null); then
        echo "$RELEASES_JSON" | jq -r '.[] | "  \(.tag_name) - \(.name) (\(.published_at | split("T")[0]))"' 2>/dev/null || echo "  (Unable to parse releases)"
    else
        echo "  (Unable to fetch releases - check network connection)"
    fi
    
    echo ""
    echo "DEVELOPMENT TAGS (Git Tags - bleeding edge):"
    echo "----------------------------------------------"
    if TAGS_JSON=$(curl -s -f "${GITHUB_TAGS_URL}?per_page=10" 2>/dev/null); then
        echo "$TAGS_JSON" | jq -r '.[].name' 2>/dev/null | while read -r tag; do
            echo "  $tag"
        done
    else
        echo "  (Unable to fetch tags - check network connection)"
    fi
    
    echo ""
    echo "Usage:"
    echo "  ./build-etc-iso.sh -r stable                    # Latest stable release"
    echo "  ./build-etc-iso.sh -r latest                    # Latest development tag"
    echo "  ./build-etc-iso.sh -r tag -t <tag-name>         # Specific tag"
    echo ""
}

get_release_info() {
    log "INFO" "Fetching release information (mode: $RELEASE_MODE)..."
    
    case "$RELEASE_MODE" in
        stable)
            log "INFO" "Fetching latest stable release from GitHub Releases API..."
            if ! RELEASE_JSON=$(curl -s -f "${GITHUB_RELEASES_URL}/latest"); then
                log "ERROR" "Failed to fetch latest release from GitHub"
                return 1
            fi
            
            RELEASE_TAG=$(echo "$RELEASE_JSON" | jq -r '.tag_name // empty')
            RELEASE_NAME=$(echo "$RELEASE_JSON" | jq -r '.name // empty')
            RELEASE_DATE=$(echo "$RELEASE_JSON" | jq -r '.published_at // empty' | cut -d'T' -f1)
            TARBALL_URL=$(echo "$RELEASE_JSON" | jq -r '.tarball_url // empty')
            ;;
            
        latest)
            log "INFO" "Fetching latest tag from GitHub Tags API..."
            if ! TAGS_JSON=$(curl -s -f "${GITHUB_TAGS_URL}?per_page=1"); then
                log "ERROR" "Failed to fetch tags from GitHub"
                return 1
            fi
            
            RELEASE_TAG=$(echo "$TAGS_JSON" | jq -r '.[0].name // empty')
            TARBALL_URL=$(echo "$TAGS_JSON" | jq -r '.[0].tarball_url // empty')
            RELEASE_NAME="$RELEASE_TAG"
            RELEASE_DATE=$(date +%Y-%m-%d)
            ;;
            
        tag)
            log "INFO" "Looking up specific tag: $SPECIFIED_TAG"
            if ! TAGS_JSON=$(curl -s -f "${GITHUB_TAGS_URL}?per_page=100"); then
                log "ERROR" "Failed to fetch tags from GitHub"
                return 1
            fi
            
            RELEASE_TAG=$(echo "$TAGS_JSON" | jq -r --arg tag "$SPECIFIED_TAG" '.[] | select(.name == $tag) | .name // empty')
            TARBALL_URL=$(echo "$TAGS_JSON" | jq -r --arg tag "$SPECIFIED_TAG" '.[] | select(.name == $tag) | .tarball_url // empty')
            
            if [ -z "$RELEASE_TAG" ]; then
                log "ERROR" "Tag not found: $SPECIFIED_TAG"
                log "INFO" "Use -l to list available tags"
                return 1
            fi
            
            RELEASE_NAME="$RELEASE_TAG"
            RELEASE_DATE=$(date +%Y-%m-%d)
            ;;
    esac
    
    if [ -z "$RELEASE_TAG" ] || [ -z "$TARBALL_URL" ]; then
        log "ERROR" "Failed to determine release information"
        return 1
    fi
    
    # Parse version components from tag
    TARBALL_FILE="${RELEASE_TAG}.tar.gz"
    VERSION=$(echo "$RELEASE_TAG" | grep -oP '\d+\.\d+\.\d+$' || echo "dev")
    DATE_VERSION=$(echo "$RELEASE_TAG" | grep -oP '\d{8}' | head -1 || echo "unknown")
    RELEASE_NUMBER=$(echo "$RELEASE_TAG" | grep -oP 'r\d+' | head -1 || echo "r0")
    BUILD_NUMBER=$(echo "$RELEASE_TAG" | grep -oP 'build\d+' || echo "")
    
    # Output ISO filename
    OUTPUT_ISO="${OUTPUT_DIR}/${RELEASE_TAG}-custom.iso"
    
    log "SUCCESS" "Release: $RELEASE_NAME"
    log "INFO" "  Tag: $RELEASE_TAG"
    log "INFO" "  Version: $VERSION"
    [ -n "$BUILD_NUMBER" ] && log "INFO" "  Build: $BUILD_NUMBER"
    log "INFO" "  Date: $DATE_VERSION"
    
    return 0
}

# ============================================================================
# Prerequisites Check
# ============================================================================

check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    local missing=0
    local required_commands=(xorriso unsquashfs mksquashfs wget curl jq)
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            log "ERROR" "Required command not found: $cmd"
            missing=1
        fi
    done
    
    if [ $missing -eq 1 ]; then
        log "ERROR" "Install missing prerequisites with:"
        log "ERROR" "  sudo apt install xorriso squashfs-tools wget curl jq"
        return 1
    fi
    
    # Check for root (required for squashfs operations)
    if [ "$(id -u)" -ne 0 ]; then
        log "ERROR" "This script must be run as root (sudo)"
        log "ERROR" "  sudo ./build-etc-iso.sh $*"
        return 1
    fi
    
    # Check for secrets.env
    if [ ! -f "$SECRETS_FILE" ]; then
        log "ERROR" "secrets.env not found: $SECRETS_FILE"
        log "ERROR" "Copy secrets.env.template to secrets.env and configure it"
        return 1
    fi
    
    # Validate secrets.env has required fields
    # shellcheck source=/dev/null
    source "$SECRETS_FILE"
    
    if [ -z "${CALLSIGN:-}" ] || [ "$CALLSIGN" = "N0CALL" ]; then
        log "WARN" "CALLSIGN not configured in secrets.env (using default N0CALL)"
    fi
    
    log "SUCCESS" "All prerequisites satisfied"
    return 0
}

# ============================================================================
# Download Functions
# ============================================================================

download_ubuntu_iso() {
    mkdir -p "$CACHE_DIR"
    
    local iso_path="${CACHE_DIR}/${UBUNTU_ISO_FILE}"
    
    # Check if already cached
    if [ -f "$iso_path" ]; then
        log "SUCCESS" "Ubuntu ISO found in cache: $iso_path"
        UBUNTU_ISO_PATH="$iso_path"
        return 0
    fi
    
    log "INFO" "Ubuntu ISO not found in cache"
    log "INFO" "Downloading Ubuntu 22.10 ISO (3.6 GB)..."
    log "INFO" "  URL: $UBUNTU_ISO_URL"
    log "INFO" "  Destination: $iso_path"
    log "INFO" ""
    log "INFO" "TIP: To skip download, place your Ubuntu ISO at:"
    log "INFO" "     $iso_path"
    
    if [ $DRY_RUN -eq 1 ]; then
        log "DRY-RUN" "Would download Ubuntu ISO"
        UBUNTU_ISO_PATH="$iso_path"
        return 0
    fi
    
    if ! wget -c -O "$iso_path" "$UBUNTU_ISO_URL"; then
        log "ERROR" "Failed to download Ubuntu ISO"
        return 1
    fi
    
    log "SUCCESS" "Ubuntu ISO downloaded: $iso_path"
    UBUNTU_ISO_PATH="$iso_path"
    return 0
}

download_etc_installer() {
    mkdir -p "$CACHE_DIR"
    
    local tarball_path="${CACHE_DIR}/${TARBALL_FILE}"
    
    # Check if already cached
    if [ -f "$tarball_path" ]; then
        log "SUCCESS" "ETC tarball found in cache: $tarball_path"
        ETC_TARBALL_PATH="$tarball_path"
        return 0
    fi
    
    log "INFO" "Downloading ETC installer: $TARBALL_FILE"
    
    if [ $DRY_RUN -eq 1 ]; then
        log "DRY-RUN" "Would download ETC tarball"
        ETC_TARBALL_PATH="$tarball_path"
        return 0
    fi
    
    if ! wget -O "$tarball_path" "$TARBALL_URL"; then
        log "ERROR" "Failed to download ETC installer"
        return 1
    fi
    
    log "SUCCESS" "ETC tarball downloaded: $tarball_path"
    ETC_TARBALL_PATH="$tarball_path"
    return 0
}

# ============================================================================
# ISO Extraction
# ============================================================================

extract_iso() {
    log "INFO" "Extracting Ubuntu ISO..."
    
    local iso_extract_dir="${WORK_DIR}/iso"
    local squashfs_dir="${WORK_DIR}/squashfs"
    
    mkdir -p "$iso_extract_dir" "$squashfs_dir"
    
    if [ $DRY_RUN -eq 1 ]; then
        log "DRY-RUN" "Would extract ISO to: $iso_extract_dir"
        log "DRY-RUN" "Would extract squashfs to: $squashfs_dir"
        return 0
    fi
    
    # Extract ISO contents
    log "INFO" "Extracting ISO structure..."
    xorriso -osirrox on -indev "$UBUNTU_ISO_PATH" -extract / "$iso_extract_dir"
    
    # Find and extract squashfs filesystem
    local squashfs_file
    squashfs_file=$(find "$iso_extract_dir" -name "filesystem.squashfs" -type f | head -1)
    
    if [ -z "$squashfs_file" ]; then
        log "ERROR" "Could not find filesystem.squashfs in ISO"
        return 1
    fi
    
    log "INFO" "Extracting squashfs filesystem (this takes several minutes)..."
    unsquashfs -d "$squashfs_dir" -f "$squashfs_file"
    
    # Store paths for later
    ISO_EXTRACT_DIR="$iso_extract_dir"
    SQUASHFS_DIR="$squashfs_dir"
    SQUASHFS_FILE="$squashfs_file"
    
    log "SUCCESS" "ISO extracted successfully"
    return 0
}

# ============================================================================
# ETC Installation (chroot)
# ============================================================================

setup_chroot_mounts() {
    # Set up bind mounts for chroot environment
    log "DEBUG" "Setting up chroot bind mounts..."
    
    mount --bind /dev "${SQUASHFS_DIR}/dev"
    mount --bind /dev/pts "${SQUASHFS_DIR}/dev/pts"
    mount --bind /proc "${SQUASHFS_DIR}/proc"
    mount --bind /sys "${SQUASHFS_DIR}/sys"
    mount --bind /run "${SQUASHFS_DIR}/run"
    
    # Copy resolv.conf for network access
    cp /etc/resolv.conf "${SQUASHFS_DIR}/etc/resolv.conf"
    
    log "DEBUG" "Chroot mounts configured"
}

cleanup_chroot_mounts() {
    # Unmount in reverse order
    log "DEBUG" "Cleaning up chroot bind mounts..."
    
    umount -l "${SQUASHFS_DIR}/run" 2>/dev/null || true
    umount -l "${SQUASHFS_DIR}/sys" 2>/dev/null || true
    umount -l "${SQUASHFS_DIR}/proc" 2>/dev/null || true
    umount -l "${SQUASHFS_DIR}/dev/pts" 2>/dev/null || true
    umount -l "${SQUASHFS_DIR}/dev" 2>/dev/null || true
    
    log "DEBUG" "Chroot mounts cleaned up"
}

install_etc_in_chroot() {
    log "INFO" ""
    log "INFO" "=== Installing EmComm Tools Community ==="
    log "INFO" "This will take 30-60 minutes depending on your internet connection..."
    
    if [ $DRY_RUN -eq 1 ]; then
        log "DRY-RUN" "Would install ETC in chroot from: $ETC_TARBALL_PATH"
        return 0
    fi
    
    # Extract ETC tarball to a temp location in the chroot
    local etc_install_dir="${SQUASHFS_DIR}/tmp/etc-installer"
    log "DEBUG" "Extracting ETC installer to: $etc_install_dir"
    
    mkdir -p "$etc_install_dir"
    tar -xzf "$ETC_TARBALL_PATH" -C "$etc_install_dir" --strip-components=1
    
    # Set up chroot environment
    setup_chroot_mounts
    
    # Trap to ensure cleanup on error
    trap 'cleanup_chroot_mounts' EXIT
    
    # Fix apt sources for Ubuntu 22.10 EOL
    log "INFO" "Fixing apt sources for Ubuntu 22.10 (EOL)..."
    chroot "${SQUASHFS_DIR}" /bin/bash -c "
        sed -i 's/archive.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list
        sed -i 's/security.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list
    "
    
    # Run the ETC installer inside chroot
    # Note: The installer uses dialog for interactive menus (OSM maps, Wikipedia, etc.)
    # We redirect stdin from /dev/null to make dialog exit immediately (simulating ESC)
    # This causes the interactive scripts to skip their downloads
    log "INFO" "Running ETC installer (this takes a while)..."
    log "INFO" "Note: Interactive map/Wikipedia downloads will be skipped (run post-install if needed)"
    
    # Set DEBIAN_FRONTEND to avoid interactive prompts
    # Redirect stdin from /dev/null to skip dialog prompts
    chroot "${SQUASHFS_DIR}" /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive
        export NEEDRESTART_MODE=a
        cd /tmp/etc-installer/scripts
        ./install.sh
    " </dev/null 2>&1 | while IFS= read -r line; do
        log "ETC" "$line"
    done
    
    local exit_code=${PIPESTATUS[0]}
    
    # Clean up
    cleanup_chroot_mounts
    trap - EXIT
    
    # Remove installer files
    log "DEBUG" "Cleaning up installer files..."
    rm -rf "$etc_install_dir"
    
    if [ $exit_code -ne 0 ]; then
        log "ERROR" "ETC installation failed with exit code: $exit_code"
        return 1
    fi
    
    log "SUCCESS" "EmComm Tools Community installed successfully"
    return 0
}

# ============================================================================
# Customization Functions (apply AFTER ETC is installed)
# ============================================================================

customize_hostname() {
    log "INFO" "Configuring hostname..."
    
    # shellcheck source=/dev/null
    source "$SECRETS_FILE"
    log "DEBUG" "Sourced secrets file: $SECRETS_FILE"
    
    local callsign="${CALLSIGN:-N0CALL}"
    local machine_name="${MACHINE_NAME:-ETC-${callsign}}"
    log "DEBUG" "CALLSIGN=$callsign, MACHINE_NAME=$machine_name"
    
    if [ $DRY_RUN -eq 1 ]; then
        log "DRY-RUN" "Would set hostname to: $machine_name"
        return 0
    fi
    
    # Set hostname
    local hostname_file="${SQUASHFS_DIR}/etc/hostname"
    log "DEBUG" "Writing hostname to: $hostname_file"
    echo "$machine_name" > "$hostname_file"
    log "DEBUG" "Hostname file written successfully"
    
    # Update /etc/hosts
    local hosts_file="${SQUASHFS_DIR}/etc/hosts"
    log "DEBUG" "Writing hosts file: $hosts_file"
    cat > "$hosts_file" <<EOF
127.0.0.1       localhost
127.0.1.1       $machine_name

::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF
    log "DEBUG" "Hosts file written successfully"
    
    log "SUCCESS" "Hostname set to: $machine_name"
}

customize_wifi() {
    log "INFO" "Configuring WiFi networks..."
    
    # shellcheck source=/dev/null
    source "$SECRETS_FILE"
    
    local nm_dir="${SQUASHFS_DIR}/etc/NetworkManager/system-connections"
    log "DEBUG" "NetworkManager connections dir: $nm_dir"
    mkdir -p "$nm_dir"
    
    # Find all WIFI_SSID_* variables
    local wifi_count=0
    log "DEBUG" "Scanning secrets.env for WIFI_SSID_* variables..."
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^WIFI_SSID_([A-Z0-9_]+)= ]]; then
            local identifier="${BASH_REMATCH[1]}"
            log "DEBUG" "Found WiFi identifier: $identifier"
            
            local ssid_var="WIFI_SSID_${identifier}"
            local password_var="WIFI_PASSWORD_${identifier}"
            local autoconnect_var="WIFI_AUTOCONNECT_${identifier}"
            
            local ssid="${!ssid_var:-}"
            local password="${!password_var:-}"
            local autoconnect="${!autoconnect_var:-yes}"
            
            log "DEBUG" "Processing: ssid_var=$ssid_var, ssid='$ssid'"
            
            # Skip empty/template values
            if [[ -z "$ssid" ]] || [[ "$ssid" == "YOUR_"* ]]; then
                log "DEBUG" "Skipping empty or template SSID: '$ssid'"
                continue
            fi
            if [[ -z "$password" ]]; then
                log "WARN" "No password for $ssid, skipping"
                continue
            fi
            
            if [ $DRY_RUN -eq 1 ]; then
                log "DRY-RUN" "Would configure WiFi: $ssid"
                wifi_count=$((wifi_count + 1))
                continue
            fi
            
            # Normalize autoconnect
            [[ "${autoconnect,,}" == "no" || "${autoconnect,,}" == "false" ]] && autoconnect="false" || autoconnect="true"
            
            # Generate UUID
            local uuid
            uuid=$(cat /proc/sys/kernel/random/uuid)
            log "DEBUG" "Generated UUID for $ssid: $uuid"
            
            local conn_file="${nm_dir}/${ssid}.nmconnection"
            log "DEBUG" "Creating connection file: $conn_file"
            
            # Create connection file
            cat > "$conn_file" <<EOF
[connection]
id=$ssid
uuid=$uuid
type=wifi
autoconnect=$autoconnect

[wifi]
mode=infrastructure
ssid=$ssid

[wifi-security]
key-mgmt=wpa-psk
psk=$password

[ipv4]
method=auto

[ipv6]
addr-gen-mode=default
method=auto
EOF
            
            chmod 600 "$conn_file"
            log "DEBUG" "Set permissions 600 on $conn_file"
            log "SUCCESS" "WiFi configured: $ssid"
            wifi_count=$((wifi_count + 1))
            log "DEBUG" "wifi_count is now: $wifi_count"
        fi
    done < "$SECRETS_FILE"
    
    log "DEBUG" "Finished scanning secrets.env, wifi_count=$wifi_count"
    
    if [ $wifi_count -eq 0 ]; then
        log "WARN" "No WiFi networks configured in secrets.env"
    else
        log "SUCCESS" "Configured $wifi_count WiFi network(s)"
    fi
}

customize_desktop() {
    log "INFO" "Configuring desktop preferences..."
    
    # shellcheck source=/dev/null
    source "$SECRETS_FILE"
    log "DEBUG" "Sourced secrets file for desktop config"
    
    local color_scheme="${DESKTOP_COLOR_SCHEME:-prefer-dark}"
    local scaling="${DESKTOP_SCALING_FACTOR:-1.0}"
    local disable_a11y="${DISABLE_ACCESSIBILITY:-yes}"
    local disable_auto_bright="${DISABLE_AUTO_BRIGHTNESS:-yes}"
    
    log "DEBUG" "Desktop config: color_scheme=$color_scheme, scaling=$scaling"
    
    if [ $DRY_RUN -eq 1 ]; then
        log "DRY-RUN" "Would configure: $color_scheme mode, ${scaling}x scaling"
        return 0
    fi
    
    # GNOME dconf uses a binary database, not plain text files in user.d
    # To set system-wide defaults, we use:
    #   1. /etc/dconf/profile/user - defines database cascade order
    #   2. /etc/dconf/db/local.d/* - settings files (keyfile format)
    #   3. Run 'dconf update' to compile the database
    
    # Create dconf profile to include local database
    local dconf_profile_dir="${SQUASHFS_DIR}/etc/dconf/profile"
    local dconf_db_dir="${SQUASHFS_DIR}/etc/dconf/db/local.d"
    mkdir -p "$dconf_profile_dir" "$dconf_db_dir"
    
    # Create profile that includes local database before user settings
    cat > "${dconf_profile_dir}/user" <<'EOF'
user-db:user
system-db:local
EOF
    log "DEBUG" "Created dconf profile"
    
    # Determine theme based on color scheme
    local gtk_theme="Yaru"
    local icon_theme="Yaru"
    if [[ "$color_scheme" == "prefer-dark" ]]; then
        gtk_theme="Yaru-dark"
        icon_theme="Yaru-dark"
    fi
    
    # Create dconf settings file (keyfile format)
    local dconf_file="${dconf_db_dir}/00-emcomm-defaults"
    log "DEBUG" "Writing dconf settings to: $dconf_file"
    cat > "$dconf_file" <<EOF
# EmComm Tools Customizer - Desktop Preferences
# Color scheme and theme
[org/gnome/desktop/interface]
color-scheme='${color_scheme}'
gtk-theme='${gtk_theme}'
icon-theme='${icon_theme}'
text-scaling-factor=${scaling}
EOF

    # Add accessibility settings if disabled
    if [[ "$disable_a11y" == "yes" ]]; then
        cat >> "$dconf_file" <<'EOF'

# Disable accessibility features
[org/gnome/desktop/a11y]
always-show-universal-access-status=false

[org/gnome/desktop/a11y/applications]
screen-keyboard-enabled=false
screen-reader-enabled=false

[org/gnome/desktop/a11y/interface]
high-contrast=false
EOF
    fi

    # Add auto-brightness setting if disabled
    if [[ "$disable_auto_bright" == "yes" ]]; then
        cat >> "$dconf_file" <<'EOF'

# Disable automatic brightness
[org/gnome/settings-daemon/plugins/power]
ambient-enabled=false
EOF
    fi

    # Compile dconf database using chroot
    log "DEBUG" "Compiling dconf database..."
    setup_chroot_mounts
    trap 'cleanup_chroot_mounts' EXIT
    
    chroot "${SQUASHFS_DIR}" /usr/bin/dconf update 2>/dev/null || {
        log "WARN" "dconf update failed - settings may not apply correctly"
    }
    
    cleanup_chroot_mounts
    trap - EXIT

    log "DEBUG" "dconf database compiled"
    log "SUCCESS" "Desktop preferences configured (${color_scheme}, ${scaling}x)"
}

customize_aprs() {
    log "INFO" "Configuring APRS/Direwolf settings..."
    
    # shellcheck source=/dev/null
    source "$SECRETS_FILE"
    log "DEBUG" "Sourced secrets file for APRS config"
    
    local callsign="${CALLSIGN:-N0CALL}"
    local grid="${GRID_SQUARE:-}"
    local winlink_passwd="${WINLINK_PASSWORD:-}"
    
    # APRS-specific settings
    local aprs_ssid="${APRS_SSID:-10}"
    local aprs_passcode="${APRS_PASSCODE:--1}"
    local aprs_symbol="${APRS_SYMBOL:-/r}"
    local aprs_comment="${APRS_COMMENT:-EmComm iGate}"
    local enable_beacon="${ENABLE_APRS_BEACON:-no}"
    local beacon_interval="${APRS_BEACON_INTERVAL:-300}"
    local beacon_via="${APRS_BEACON_VIA:-WIDE1-1}"
    local beacon_power="${APRS_BEACON_POWER:-10}"
    local beacon_height="${APRS_BEACON_HEIGHT:-20}"
    local beacon_gain="${APRS_BEACON_GAIN:-3}"
    local beacon_dir="${APRS_BEACON_DIR:-}"
    local enable_igate="${ENABLE_APRS_IGATE:-yes}"
    local aprs_server="${APRS_SERVER:-noam.aprs2.net}"
    local direwolf_adevice="${DIREWOLF_ADEVICE:-plughw:1,0}"
    local direwolf_ptt="${DIREWOLF_PTT:-CM108}"
    
    log "DEBUG" "User config: callsign=$callsign, grid=$grid"
    log "DEBUG" "APRS config: ssid=$aprs_ssid, igate=$enable_igate, beacon=$enable_beacon"
    
    if [[ "$callsign" == "N0CALL" ]]; then
        log "WARN" "APRS not configured - callsign is N0CALL"
        return 0
    fi
    
    if [ $DRY_RUN -eq 1 ]; then
        log "DRY-RUN" "Would pre-configure user.json for: ${callsign}"
        log "DRY-RUN" "Would modify ETC direwolf templates with iGate/beacon settings"
        return 0
    fi
    
    # === 1. Pre-populate ETC's user.json ===
    # ETC uses ~/.config/emcomm-tools/user.json for user settings
    # This is read by et-user, et-direwolf, et-yaac, et-winlink at runtime
    local etc_config_dir="${SQUASHFS_DIR}/etc/skel/.config/emcomm-tools"
    log "DEBUG" "Creating ETC config dir: $etc_config_dir"
    mkdir -p "$etc_config_dir"
    
    local user_json="${etc_config_dir}/user.json"
    log "DEBUG" "Writing user.json: $user_json"
    
    cat > "$user_json" <<EOF
{
  "callsign": "${callsign}",
  "grid": "${grid}",
  "winlinkPasswd": "${winlink_passwd}"
}
EOF
    chmod 644 "$user_json"
    log "DEBUG" "user.json written"
    
    # === 2. Modify ETC's direwolf template with iGate/beacon settings ===
    # ETC's et-direwolf substitutes {{ET_CALLSIGN}} and {{ET_AUDIO_DEVICE}} at runtime
    # We add our iGate/beacon settings to the template, keeping those placeholders
    
    local template_dir="${SQUASHFS_DIR}/opt/emcomm-tools/conf/template.d/packet"
    local aprs_template="${template_dir}/direwolf.aprs-digipeater.conf"
    
    if [ ! -d "$template_dir" ]; then
        log "WARN" "ETC template directory not found: $template_dir"
        log "WARN" "Skipping direwolf template modification"
        return 0
    fi
    
    # Backup original template
    if [ -f "$aprs_template" ]; then
        cp "$aprs_template" "${aprs_template}.orig"
        log "DEBUG" "Backed up original template"
    fi
    
    # Extract symbol table and code (e.g., "/r" -> table="/", code="r")
    local symbol_table="${aprs_symbol:0:1}"
    local symbol_code="${aprs_symbol:1:1}"
    
    # Create modified template with iGate/beacon settings
    # Keep {{ET_CALLSIGN}} and {{ET_AUDIO_DEVICE}} for ETC's runtime substitution
    cat > "$aprs_template" <<EOF
# Direwolf APRS Digipeater/iGate Configuration
# Template modified by EmComm Tools Customizer
# ETC substitutes {{ET_CALLSIGN}} and {{ET_AUDIO_DEVICE}} at runtime

# Audio device (substituted by et-direwolf at runtime)
ADEVICE {{ET_AUDIO_DEVICE}}
CHANNEL 0

# Callsign with SSID (substituted by et-direwolf, we append SSID)
MYCALL {{ET_CALLSIGN}}-${aprs_ssid}

# PTT configuration
PTT ${direwolf_ptt}

# Modem settings for APRS (1200 baud)
MODEM 1200

EOF

    # Add iGate configuration if enabled
    if [[ "$enable_igate" == "yes" ]]; then
        cat >> "$aprs_template" <<EOF
# ============================================
# iGate Configuration (RF to Internet gateway)
# ============================================
IGSERVER ${aprs_server}
IGLOGIN {{ET_CALLSIGN}} ${aprs_passcode}

EOF
        log "DEBUG" "Added iGate settings to template"
    fi

    # Add beacon configuration if enabled
    if [[ "$enable_beacon" == "yes" ]]; then
        # Build PHG string if we have the values
        local phg_string=""
        if [[ -n "$beacon_power" && -n "$beacon_height" && -n "$beacon_gain" ]]; then
            phg_string="power=${beacon_power} height=${beacon_height} gain=${beacon_gain}"
            if [[ -n "$beacon_dir" ]]; then
                phg_string="${phg_string} dir=${beacon_dir}"
            fi
        fi
        
        cat >> "$aprs_template" <<EOF
# ============================================
# Position Beacon Configuration
# ============================================
# Use GPS for position (requires gpsd running)
GPSD

# Smart beaconing: adjusts rate based on speed/heading
# fast_speed mph, fast_rate sec, slow_speed mph, slow_rate sec, turn_angle, turn_time sec, turn_slope
SMARTBEACONING 30 60 2 1800 15 15 255

# Fallback fixed beacon if no GPS
PBEACON delay=1 every=${beacon_interval} symbol="${symbol_table}${symbol_code}" ${phg_string} \\
    comment="${aprs_comment}" via=${beacon_via}

EOF
        log "DEBUG" "Added beacon settings to template (PHG: ${phg_string:-none})"
    fi

    # Add digipeater configuration
    cat >> "$aprs_template" <<EOF
# ============================================
# Digipeater Configuration
# ============================================
# Standard APRS digipeating with path tracing
DIGIPEAT 0 0 ^WIDE[3-7]-[1-7]$|^TEST$ ^WIDE[12]-[12]$ TRACE
DIGIPEAT 0 0 ^WIDE[12]-[12]$ ^WIDE[12]-[12]$ TRACE

EOF

    chmod 644 "$aprs_template"
    log "SUCCESS" "Modified ETC direwolf template: direwolf.aprs-digipeater.conf"
    log "SUCCESS" "APRS configured for ${callsign}-${aprs_ssid} (igate=${enable_igate}, beacon=${enable_beacon})"
}

customize_user_and_autologin() {
    log "INFO" "Configuring user account..."
    
    # shellcheck source=/dev/null
    source "$SECRETS_FILE"
    log "DEBUG" "Sourced secrets file for user config"
    
    local callsign="${CALLSIGN:-N0CALL}"
    local fullname="${USER_FULLNAME:-EmComm User}"
    # Default username to lowercase callsign
    local username="${USER_USERNAME:-${callsign,,}}"
    local password="${USER_PASSWORD:-}"
    local enable_autologin="${ENABLE_AUTOLOGIN:-no}"
    
    log "DEBUG" "User config: fullname='$fullname', username='$username'"
    log "DEBUG" "Autologin: $enable_autologin, password_set: $([ -n "$password" ] && echo 'yes' || echo 'no')"
    
    if [ $DRY_RUN -eq 1 ]; then
        if [ "$enable_autologin" = "yes" ]; then
            log "DRY-RUN" "Would configure autologin for: $username"
        else
            log "DRY-RUN" "Would configure password login for: $username"
        fi
        return 0
    fi
    
    # Only configure autologin if explicitly enabled
    if [ "$enable_autologin" = "yes" ]; then
        local lightdm_dir="${SQUASHFS_DIR}/etc/lightdm/lightdm.conf.d"
        log "DEBUG" "Creating LightDM config dir: $lightdm_dir"
        mkdir -p "$lightdm_dir"
        
        local autologin_conf="${lightdm_dir}/50-autologin.conf"
        log "DEBUG" "Writing autologin config: $autologin_conf"
        cat > "$autologin_conf" <<EOF
[Seat:*]
autologin-user=$username
autologin-user-timeout=0
user-session=ubuntu
EOF
        log "DEBUG" "Autologin config written successfully"
        log "SUCCESS" "Autologin configured for: $username"
    else
        log "INFO" "Autologin disabled - user will be prompted for password"
        # Remove any existing autologin configuration (if ETC has one)
        local autologin_conf="${SQUASHFS_DIR}/etc/lightdm/lightdm.conf.d/50-autologin.conf"
        if [ -f "$autologin_conf" ]; then
            log "DEBUG" "Removing existing autologin config: $autologin_conf"
            rm -f "$autologin_conf"
        fi
    fi
    
    # Set user password via chroot if provided
    # We need chroot because passwd requires proper system context
    if [ -n "$password" ]; then
        log "INFO" "Setting user password via chroot..."
        
        # Set up chroot mounts
        setup_chroot_mounts
        trap 'cleanup_chroot_mounts' EXIT
        
        # Use chpasswd to set password (more script-friendly than passwd)
        # Format: username:password
        echo "${username}:${password}" | chroot "${SQUASHFS_DIR}" /usr/sbin/chpasswd
        local chpasswd_exit=$?
        
        # Clean up
        cleanup_chroot_mounts
        trap - EXIT
        
        if [ $chpasswd_exit -eq 0 ]; then
            log "SUCCESS" "Password set for user: $username"
        else
            log "WARN" "Failed to set password (exit code: $chpasswd_exit)"
            log "WARN" "User may need to set password on first boot"
        fi
    else
        log "INFO" "No password configured - user will use ETC default or must set on first boot"
    fi
    
    log "SUCCESS" "User account configuration complete"
}

customize_vara_license() {
    log "INFO" "Configuring VARA license (if provided)..."
    
    # shellcheck source=/dev/null
    source "$SECRETS_FILE"
    log "DEBUG" "Sourced secrets file for VARA config"
    
    local vara_fm_callsign="${VARA_FM_CALLSIGN:-}"
    local vara_fm_key="${VARA_FM_LICENSE_KEY:-}"
    local vara_hf_callsign="${VARA_HF_CALLSIGN:-}"
    local vara_hf_key="${VARA_HF_LICENSE_KEY:-}"
    
    log "DEBUG" "VARA FM: callsign='$vara_fm_callsign', key_present=$([ -n "$vara_fm_key" ] && echo 'yes' || echo 'no')"
    log "DEBUG" "VARA HF: callsign='$vara_hf_callsign', key_present=$([ -n "$vara_hf_key" ] && echo 'yes' || echo 'no')"
    
    if [ -z "$vara_fm_key" ] && [ -z "$vara_hf_key" ]; then
        log "INFO" "No VARA license keys configured, skipping"
        return 0
    fi
    
    if [ $DRY_RUN -eq 1 ]; then
        [ -n "$vara_fm_key" ] && log "DRY-RUN" "Would create VARA FM license .reg file"
        [ -n "$vara_hf_key" ] && log "DRY-RUN" "Would create VARA HF license .reg file"
        return 0
    fi
    
    # IMPORTANT: Wine doesn't exist until VARA is installed post-install!
    # ETC workflow:
    #   1. ISO build: install-wine.sh installs Wine packages only
    #   2. Post-install (desktop session): user runs ~/add-ons/wine/*.sh to install VARA
    #   3. Wine prefix (~/.wine32) is created during VARA installation
    #
    # We create .reg files in add-ons for the user to import after VARA installation
    # using: wine regedit /path/to/vara-license.reg
    
    local addon_dir="${SQUASHFS_DIR}/etc/skel/add-ons/wine"
    log "DEBUG" "Creating Wine add-ons dir: $addon_dir"
    mkdir -p "$addon_dir"
    
    # Create a script to import all license registry files
    local import_script="${addon_dir}/99-import-vara-licenses.sh"
    
    cat > "$import_script" <<'SCRIPT_HEADER'
#!/bin/bash
# Auto-generated by build-etc-iso.sh
# Run this AFTER completing VARA installation to register your licenses
# Usage: ./99-import-vara-licenses.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -d "$HOME/.wine32" ]; then
    echo "ERROR: Wine prefix ~/.wine32 not found!"
    echo "Please install VARA first using the scripts in this directory:"
    echo "  1. ./01-install-wine-deps.sh"
    echo "  2. ./02-install-vara-hf.sh"
    echo "  3. ./03-install-vara-fm.sh"
    exit 1
fi

export WINEPREFIX="$HOME/.wine32"

echo "Importing VARA license registry files..."

SCRIPT_HEADER
    
    if [ -n "$vara_fm_key" ]; then
        local fm_reg="${addon_dir}/vara-fm-license.reg"
        log "DEBUG" "Writing VARA FM registry: $fm_reg"
        cat > "$fm_reg" <<EOF
REGEDIT4

[HKEY_CURRENT_USER\\Software\\VARA FM]
"Callsign"="${vara_fm_callsign}"
"License"="${vara_fm_key}"
EOF
        chmod 644 "$fm_reg"
        log "DEBUG" "VARA FM registry written"
        
        # Add to import script
        cat >> "$import_script" <<'EOF'

if [ -f "$SCRIPT_DIR/vara-fm-license.reg" ]; then
    echo "Importing VARA FM license..."
    wine regedit "$SCRIPT_DIR/vara-fm-license.reg"
    echo "VARA FM license imported successfully"
fi
EOF
        log "SUCCESS" "VARA FM license registry file created"
    fi
    
    if [ -n "$vara_hf_key" ]; then
        local hf_reg="${addon_dir}/vara-hf-license.reg"
        log "DEBUG" "Writing VARA HF registry: $hf_reg"
        cat > "$hf_reg" <<EOF
REGEDIT4

[HKEY_CURRENT_USER\\Software\\VARA]
"Callsign"="${vara_hf_callsign}"
"License"="${vara_hf_key}"
EOF
        chmod 644 "$hf_reg"
        log "DEBUG" "VARA HF registry written"
        
        # Add to import script
        cat >> "$import_script" <<'EOF'

if [ -f "$SCRIPT_DIR/vara-hf-license.reg" ]; then
    echo "Importing VARA HF license..."
    wine regedit "$SCRIPT_DIR/vara-hf-license.reg"
    echo "VARA HF license imported successfully"
fi
EOF
        log "SUCCESS" "VARA HF license registry file created"
    fi
    
    # Finish the import script
    cat >> "$import_script" <<'EOF'

echo ""
echo "License import complete!"
echo "Restart VARA to verify registration."
EOF
    
    chmod +x "$import_script"
    log "SUCCESS" "VARA license import script created: ~/add-ons/wine/99-import-vara-licenses.sh"
    log "INFO" "User must run this script AFTER installing VARA"
}

customize_git_config() {
    log "INFO" "Configuring Git..."
    
    # shellcheck source=/dev/null
    source "$SECRETS_FILE"
    log "DEBUG" "Sourced secrets file for Git config"
    
    local git_name="${USER_FULLNAME:-User}"
    local git_email="${USER_EMAIL:-user@localhost}"
    log "DEBUG" "Git config: name='$git_name', email='$git_email'"
    
    if [[ "$git_name" == "Your Full Name" ]] || [[ "$git_email" == "your.email@example.com" ]]; then
        log "WARN" "Git not configured - template values in secrets.env"
        return 0
    fi
    
    if [ $DRY_RUN -eq 1 ]; then
        log "DRY-RUN" "Would configure Git for: $git_name <$git_email>"
        return 0
    fi
    
    local gitconfig="${SQUASHFS_DIR}/etc/skel/.gitconfig"
    log "DEBUG" "Writing git config: $gitconfig"
    cat > "$gitconfig" <<EOF
[user]
    name = $git_name
    email = $git_email
[init]
    defaultBranch = main
[pull]
    rebase = false
EOF
    log "DEBUG" "Git config written successfully"
    
    log "SUCCESS" "Git configured for: $git_name"
}

customize_power() {
    log "INFO" "Configuring power management..."
    
    # shellcheck source=/dev/null
    source "$SECRETS_FILE"
    log "DEBUG" "Sourced secrets file for power config"
    
    # Read power settings with defaults
    local lid_close_ac="${POWER_LID_CLOSE_AC:-suspend}"
    local lid_close_battery="${POWER_LID_CLOSE_BATTERY:-suspend}"
    local power_button="${POWER_BUTTON_ACTION:-interactive}"
    local idle_ac="${POWER_IDLE_AC:-nothing}"
    local idle_battery="${POWER_IDLE_BATTERY:-suspend}"
    local idle_timeout="${POWER_IDLE_TIMEOUT:-900}"
    
    log "DEBUG" "Power settings: lid_ac=$lid_close_ac, lid_battery=$lid_close_battery, button=$power_button"
    log "DEBUG" "Idle settings: ac=$idle_ac, battery=$idle_battery, timeout=$idle_timeout"
    
    if [ $DRY_RUN -eq 1 ]; then
        log "DRY-RUN" "Would configure power management via dconf"
        return 0
    fi
    
    # Power management uses dconf - add to the same system-wide database
    # as the desktop settings (created by customize_desktop)
    local dconf_db_dir="${SQUASHFS_DIR}/etc/dconf/db/local.d"
    local dconf_file="${dconf_db_dir}/01-power-settings"
    
    # Ensure directory exists (should already exist from customize_desktop)
    mkdir -p "$dconf_db_dir"
    log "DEBUG" "Writing power dconf settings: $dconf_file"
    
    cat > "$dconf_file" <<EOF
# Power management settings
# Generated by emcomm-tools-customizer

[org/gnome/settings-daemon/plugins/power]
lid-close-ac-action='${lid_close_ac}'
lid-close-battery-action='${lid_close_battery}'
power-button-action='${power_button}'
sleep-inactive-ac-type='${idle_ac}'
sleep-inactive-battery-type='${idle_battery}'
sleep-inactive-ac-timeout=${idle_timeout}
sleep-inactive-battery-timeout=${idle_timeout}
EOF
    
    # Recompile dconf database
    log "DEBUG" "Recompiling dconf database..."
    setup_chroot_mounts
    trap 'cleanup_chroot_mounts' EXIT
    
    chroot "${SQUASHFS_DIR}" /usr/bin/dconf update 2>/dev/null || {
        log "WARN" "dconf update failed - power settings may not apply correctly"
    }
    
    cleanup_chroot_mounts
    trap - EXIT
    
    log "SUCCESS" "Power management configured"
}

customize_pat() {
    log "INFO" "Configuring Pat Winlink aliases..."
    
    # shellcheck source=/dev/null
    source "$SECRETS_FILE"
    log "DEBUG" "Sourced secrets file for Pat config"
    
    local emcomm_alias="${PAT_EMCOMM_ALIAS:-no}"
    local emcomm_gateway="${PAT_EMCOMM_GATEWAY:-}"
    
    log "DEBUG" "Pat settings: emcomm_alias=$emcomm_alias, gateway=$emcomm_gateway"
    
    if [[ "${emcomm_alias,,}" != "yes" ]]; then
        log "INFO" "Pat emcomm alias not enabled, skipping"
        return 0
    fi
    
    if [ $DRY_RUN -eq 1 ]; then
        log "DRY-RUN" "Would configure Pat emcomm alias"
        [ -n "$emcomm_gateway" ] && log "DRY-RUN" "  Gateway: $emcomm_gateway"
        return 0
    fi
    
    # Pat stores its config in ~/.config/pat/config.json (standard location)
    # ETC creates this when Pat runs for the first time
    # We create a helper script to add the emcomm alias to the standard config
    local pat_script_dir="${SQUASHFS_DIR}/etc/skel/.config/pat"
    local pat_alias_script="${pat_script_dir}/add-emcomm-alias.sh"
    
    mkdir -p "$pat_script_dir"
    log "DEBUG" "Creating Pat alias setup script: $pat_alias_script"
    
    # Create a setup script that adds the alias to standard Pat config
    cat > "$pat_alias_script" <<'SCRIPT_EOF'
#!/bin/bash
# Add emcomm alias to standard Pat Winlink config
# This modifies ~/.config/pat/config.json (Pat's normal config file)
# Run this after Pat has been configured with your callsign

PAT_CONFIG="$HOME/.config/pat/config.json"

if [ ! -f "$PAT_CONFIG" ]; then
    echo "Pat config not found. Run Pat first to create initial config."
    exit 1
fi

# Check if alias already exists
if grep -q '"emcomm"' "$PAT_CONFIG" 2>/dev/null; then
    echo "emcomm alias already exists in Pat config."
    exit 0
fi

SCRIPT_EOF

    # Add gateway-specific or generic alias
    if [ -n "$emcomm_gateway" ]; then
        cat >> "$pat_alias_script" <<EOF
# Add emcomm alias with preconfigured gateway
# This uses jq to properly modify the JSON config
if command -v jq &> /dev/null; then
    jq '.connect_aliases.emcomm = "${emcomm_gateway}"' "\$PAT_CONFIG" > "\$PAT_CONFIG.tmp" && \\
        mv "\$PAT_CONFIG.tmp" "\$PAT_CONFIG"
    echo "Added emcomm alias -> ${emcomm_gateway}"
else
    echo "jq not found. Please install: sudo apt install jq"
    echo "Then add manually: connect_aliases.emcomm = \"${emcomm_gateway}\""
fi
EOF
    else
        cat >> "$pat_alias_script" <<'EOF'
# Add placeholder emcomm alias - user will need to set gateway
echo ""
echo "To add an emcomm alias, edit ~/.config/pat/config.json"
echo "Add to connect_aliases section:"
echo '  "emcomm": "YOUR-GATEWAY-CALLSIGN"'
echo ""
echo "Example gateways: W7ACS-10, K7YYY-10"
EOF
    fi
    
    chmod +x "$pat_alias_script"
    log "DEBUG" "Pat alias script created"
    
    # Also create a desktop reminder or README
    local pat_readme="${pat_script_dir}/README-emcomm-alias.txt"
    cat > "$pat_readme" <<EOF
Pat Winlink EmComm Alias Setup
==============================

To quickly connect to Winlink, run:
  pat connect emcomm

First-time setup:
1. Run Pat once to create initial config: pat configure
2. Run the alias script: ~/.config/pat/add-emcomm-alias.sh
3. If no gateway was preconfigured, edit ~/.config/pat/config.json
   and add your preferred gateway to connect_aliases

Example connect_aliases in config.json:
{
  "connect_aliases": {
    "emcomm": "W7ACS-10",
    "hf": "W7ACS-5"
  }
}
EOF

    log "SUCCESS" "Pat emcomm alias configured"
    [ -n "$emcomm_gateway" ] && log "INFO" "  Default gateway: $emcomm_gateway"
}

embed_cache_files() {
    # Embed cache files into the ISO so they're available for future builds
    # This is for users who build on the same machine they install to
    
    if [ $MINIMAL_BUILD -eq 1 ]; then
        log "INFO" "Minimal build - skipping cache embedding"
        return 0
    fi
    
    log "INFO" "Embedding cache files for future builds..."
    
    if [ $DRY_RUN -eq 1 ]; then
        log "DRY-RUN" "Would embed cache files from: $CACHE_DIR"
        return 0
    fi
    
    # Create cache directory in /opt for the installed system
    local target_cache="${SQUASHFS_DIR}/opt/emcomm-customizer-cache"
    log "DEBUG" "Creating target cache dir: $target_cache"
    mkdir -p "$target_cache"
    
    # Copy Ubuntu ISO if present
    local ubuntu_iso="${CACHE_DIR}/${UBUNTU_ISO_FILE}"
    if [ -f "$ubuntu_iso" ]; then
        log "DEBUG" "Copying Ubuntu ISO to embedded cache..."
        cp -v "$ubuntu_iso" "$target_cache/"
        log "SUCCESS" "Ubuntu ISO embedded (~4GB)"
    else
        log "DEBUG" "No Ubuntu ISO found in cache"
    fi
    
    # Copy ETC tarball if present (find most recent)
    local etc_tarball
    etc_tarball=$(find "$CACHE_DIR" -maxdepth 1 -name "emcomm-tools-os-community*.tar.gz" -type f | sort -r | head -1)
    if [ -n "$etc_tarball" ] && [ -f "$etc_tarball" ]; then
        log "DEBUG" "Copying ETC tarball to embedded cache..."
        cp -v "$etc_tarball" "$target_cache/"
        log "SUCCESS" "ETC tarball embedded"
    else
        log "DEBUG" "No ETC tarball found in cache"
    fi
    
    # Create a README explaining the cache
    cat > "$target_cache/README.txt" <<EOF
EmComm Tools Customizer - Embedded Cache
=========================================

These files were embedded during ISO build so you can rebuild without
re-downloading large files.

To use this cache for your next build:
  cp -r /opt/emcomm-customizer-cache/* ~/emcomm-tools-customizer/cache/

Or run build-etc-iso.sh from /opt/emcomm-customizer-cache directly.

Files:
$(ls -lh "$target_cache" 2>/dev/null | grep -v README)

Build date: $(date +'%Y-%m-%d %H:%M:%S')
EOF
    
    log "SUCCESS" "Cache files embedded (use -m for minimal build without cache)"
}

create_build_manifest() {
    log "INFO" "Creating build manifest..."
    
    # shellcheck source=/dev/null
    source "$SECRETS_FILE"
    log "DEBUG" "Sourced secrets file for manifest"
    
    local manifest_file="${SQUASHFS_DIR}/etc/emcomm-customizations-manifest.txt"
    log "DEBUG" "Manifest file: $manifest_file"
    
    if [ $DRY_RUN -eq 1 ]; then
        log "DRY-RUN" "Would create manifest at: $manifest_file"
        return 0
    fi
    
    log "DEBUG" "Writing build manifest..."
    cat > "$manifest_file" <<EOF
EmComm Tools Community - KD7DGF Customizations
Build Date: $(date +'%Y-%m-%d %H:%M:%S')
Release: ${RELEASE_TAG}
Version: ${VERSION}

=== CUSTOMIZATIONS APPLIED ===

Station Configuration:
- Callsign: ${CALLSIGN:-N0CALL}
- Hostname: ${MACHINE_NAME:-ETC-${CALLSIGN:-N0CALL}}

Network:
- WiFi networks pre-configured from secrets.env

Desktop:
- Dark mode enabled
- Accessibility features disabled
- Automatic brightness disabled

APRS:
- direwolf configured
- YAAC configured

Build Information:
- Built with: build-etc-iso.sh (xorriso/squashfs method)
- Source: ${RELEASE_TAG}
- No Cubic GUI used - fully automated
EOF
    log "DEBUG" "Manifest written successfully"
    
    log "SUCCESS" "Build manifest created"
}

# ============================================================================
# ISO Rebuild
# ============================================================================

rebuild_squashfs() {
    log "INFO" "Rebuilding squashfs filesystem (this takes 10-20 minutes)..."
    
    if [ $DRY_RUN -eq 1 ]; then
        log "DRY-RUN" "Would rebuild squashfs"
        return 0
    fi
    
    local new_squashfs="${WORK_DIR}/filesystem.squashfs.new"
    log "DEBUG" "Creating new squashfs: $new_squashfs"
    log "DEBUG" "Source directory: $SQUASHFS_DIR"
    log "DEBUG" "Compression: xz, block size: 1M"
    
    # Create new squashfs with compression
    mksquashfs "$SQUASHFS_DIR" "$new_squashfs" \
        -comp xz \
        -b 1M \
        -Xbcj x86 \
        -noappend
    log "DEBUG" "mksquashfs completed"
    
    # Replace original squashfs
    log "DEBUG" "Moving new squashfs to: $SQUASHFS_FILE"
    mv "$new_squashfs" "$SQUASHFS_FILE"
    
    # Update filesystem.size
    local fs_size
    fs_size=$(du -s "$SQUASHFS_DIR" | cut -f1)
    log "DEBUG" "Filesystem size: $fs_size"
    echo "$fs_size" > "$(dirname "$SQUASHFS_FILE")/filesystem.size"
    
    log "SUCCESS" "Squashfs rebuilt"
}

rebuild_iso() {
    log "INFO" "Rebuilding ISO image..."
    
    log "DEBUG" "Output directory: $OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"
    
    if [ $DRY_RUN -eq 1 ]; then
        log "DRY-RUN" "Would create ISO: $OUTPUT_ISO"
        return 0
    fi
    
    # Calculate MD5 sums
    log "INFO" "Calculating checksums..."
    log "DEBUG" "Running md5sum on all files in ISO"
    (cd "$ISO_EXTRACT_DIR" && find . -type f -print0 | xargs -0 md5sum > md5sum.txt) 2>/dev/null || true
    log "DEBUG" "Checksums calculated"
    
    # Rebuild ISO with xorriso (Ventoy handles the booting)
    log "INFO" "Creating ISO image..."
    log "DEBUG" "Output ISO: $OUTPUT_ISO"
    log "DEBUG" "ISO label: ETC_${RELEASE_NUMBER^^}_CUSTOM"
    xorriso -as mkisofs \
        -r -V "ETC_${RELEASE_NUMBER^^}_CUSTOM" \
        -J -joliet-long \
        -l -cache-inodes \
        -c boot.catalog \
        -b boot/grub/i386-pc/eltorito.img \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        --grub2-boot-info \
        --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
        -eltorito-alt-boot \
        -e boot/grub/efi.img \
        -no-emul-boot \
        -append_partition 2 0xef "$ISO_EXTRACT_DIR/boot/grub/efi.img" \
        -o "$OUTPUT_ISO" \
        "$ISO_EXTRACT_DIR" 2>&1 | tee -a "$LOG_FILE"
    
    # If the above fails (missing grub files), try simpler approach
    if [ ! -f "$OUTPUT_ISO" ]; then
        log "WARN" "Standard method failed, trying simple ISO creation..."
        xorriso -as mkisofs \
            -r -V "ETC_${RELEASE_NUMBER^^}_CUSTOM" \
            -J -joliet-long \
            -l -cache-inodes \
            -o "$OUTPUT_ISO" \
            "$ISO_EXTRACT_DIR" 2>&1 | tee -a "$LOG_FILE"
    fi
    
    # Check if ISO was created
    if [ ! -f "$OUTPUT_ISO" ]; then
        log "ERROR" "ISO creation failed"
        return 1
    fi
    
    local iso_size
    iso_size=$(du -h "$OUTPUT_ISO" | cut -f1)
    
    log "SUCCESS" "ISO created: $OUTPUT_ISO ($iso_size)"
    log "INFO" "Copy to Ventoy drive: cp \"$OUTPUT_ISO\" /media/\$USER/Ventoy/"
}

# ============================================================================
# Cleanup
# ============================================================================

cleanup_work_dir() {
    if [ -d "$WORK_DIR" ]; then
        log "INFO" "Cleaning up work directory..."
        rm -rf "$WORK_DIR"
        log "SUCCESS" "Work directory cleaned"
    fi
}

# ============================================================================
# Main
# ============================================================================

main() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║   EmComm Tools Community ISO Customizer                      ║"
    echo "║   Fully Automated Build (xorriso/squashfs)                   ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    log "INFO" "Build started at $(date)"
    log "INFO" "Log file: $LOG_FILE"
    
    # Check prerequisites
    if ! check_prerequisites; then
        exit 2
    fi
    
    # Get release information
    if ! get_release_info; then
        exit 1
    fi
    
    # Create work directory
    log "INFO" "Creating work directory: $WORK_DIR"
    rm -rf "$WORK_DIR"
    mkdir -p "$WORK_DIR"
    
    # Download files
    if ! download_ubuntu_iso; then
        cleanup_work_dir
        exit 1
    fi
    
    if ! download_etc_installer; then
        cleanup_work_dir
        exit 1
    fi
    
    # Extract ISO
    if ! extract_iso; then
        cleanup_work_dir
        exit 1
    fi
    
    # Install ETC in chroot (this is the main installation)
    if ! install_etc_in_chroot; then
        cleanup_work_dir
        exit 1
    fi
    
    # Apply customizations (AFTER ETC is installed)
    log "INFO" ""
    log "INFO" "=== Applying Customizations ==="
    log "DEBUG" "Starting customization phase..."
    
    log "DEBUG" "Step 1/11: customize_hostname"
    customize_hostname
    log "DEBUG" "Step 1/11: customize_hostname COMPLETED"
    
    log "DEBUG" "Step 2/11: customize_wifi"
    customize_wifi
    log "DEBUG" "Step 2/11: customize_wifi COMPLETED"
    
    log "DEBUG" "Step 3/11: customize_desktop"
    customize_desktop
    log "DEBUG" "Step 3/11: customize_desktop COMPLETED"
    
    log "DEBUG" "Step 4/11: customize_aprs"
    customize_aprs
    log "DEBUG" "Step 4/11: customize_aprs COMPLETED"
    
    log "DEBUG" "Step 5/11: customize_user_and_autologin"
    customize_user_and_autologin
    log "DEBUG" "Step 5/11: customize_user_and_autologin COMPLETED"
    
    log "DEBUG" "Step 6/11: customize_vara_license"
    customize_vara_license
    log "DEBUG" "Step 6/11: customize_vara_license COMPLETED"
    
    log "DEBUG" "Step 7/11: customize_pat"
    customize_pat
    log "DEBUG" "Step 7/11: customize_pat COMPLETED"
    
    log "DEBUG" "Step 8/11: customize_git_config"
    customize_git_config
    log "DEBUG" "Step 8/11: customize_git_config COMPLETED"
    
    log "DEBUG" "Step 9/11: customize_power"
    customize_power
    log "DEBUG" "Step 9/11: customize_power COMPLETED"
    
    log "DEBUG" "Step 10/11: embed_cache_files"
    embed_cache_files
    log "DEBUG" "Step 10/11: embed_cache_files COMPLETED"
    
    log "DEBUG" "Step 11/11: create_build_manifest"
    create_build_manifest
    log "DEBUG" "Step 11/11: create_build_manifest COMPLETED"
    
    log "DEBUG" "All customizations completed successfully"
    
    # Rebuild ISO
    log "INFO" ""
    log "INFO" "=== Rebuilding ISO ==="
    
    if ! rebuild_squashfs; then
        cleanup_work_dir
        exit 1
    fi
    
    if ! rebuild_iso; then
        cleanup_work_dir
        exit 1
    fi
    
    # Cleanup
    cleanup_work_dir
    
    # Summary
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║   Build Complete!                                            ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    log "SUCCESS" "Custom ISO: $OUTPUT_ISO"
    log "INFO" ""
    log "INFO" "Next steps:"
    log "INFO" "  1. Copy ISO to Ventoy USB: cp \"$OUTPUT_ISO\" /media/\$USER/Ventoy/"
    log "INFO" "  2. Safely eject the USB drive"
    log "INFO" "  3. Boot target system from Ventoy"
    log "INFO" ""
    log "INFO" "Build log: $LOG_FILE"
}

# ============================================================================
# Parse Arguments
# ============================================================================

while getopts "r:t:ldmvDh" opt; do
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
        l)
            list_available_versions
            exit 0
            ;;
        d)
            DRY_RUN=1
            ;;
        m)
            MINIMAL_BUILD=1
            log "INFO" "Minimal build - cache files will not be embedded in ISO"
            ;;
        v)
            set -x
            ;;
        D)
            DEBUG_MODE=1
            log "INFO" "Debug mode enabled - showing DEBUG messages"
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

# Run main
main "$@"
