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

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    
    # Log to file
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    # Log to console with color
    case "$level" in
        ERROR)   echo -e "${RED}[$level]${NC} $message" ;;
        WARN)    echo -e "${YELLOW}[$level]${NC} $message" ;;
        SUCCESS) echo -e "${GREEN}[$level]${NC} $message" ;;
        INFO)    echo -e "${BLUE}[$level]${NC} $message" ;;
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
    -v        Verbose mode (enable bash -x debugging)
    -h        Show this help message

DIRECTORY STRUCTURE:
    cache/    Downloaded ISOs and tarballs (persistent)
              - Drop your Ubuntu ISO here to skip download
              - ETC tarballs are cached here too
    output/   Generated custom ISOs
    logs/     Build logs

PREREQUISITES:
    sudo apt install xorriso squashfs-tools genisoimage p7zip-full wget curl jq

EXAMPLES:
    # List available releases
    ./build-etc-iso.sh -l

    # Build from stable release (recommended)
    sudo ./build-etc-iso.sh -r stable

    # Build from latest development tag
    sudo ./build-etc-iso.sh -r latest

    # Build specific version
    sudo ./build-etc-iso.sh -r tag -t emcomm-tools-os-community-20251113-r5-build17

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
    local required_commands=(xorriso unsquashfs mksquashfs genisoimage wget curl jq)
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            log "ERROR" "Required command not found: $cmd"
            missing=1
        fi
    done
    
    if [ $missing -eq 1 ]; then
        log "ERROR" "Install missing prerequisites with:"
        log "ERROR" "  sudo apt install xorriso squashfs-tools genisoimage p7zip-full wget curl jq"
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
# Customization Functions (from cubic scripts)
# ============================================================================

customize_hostname() {
    log "INFO" "Configuring hostname..."
    
    # shellcheck source=/dev/null
    source "$SECRETS_FILE"
    
    local callsign="${CALLSIGN:-N0CALL}"
    local machine_name="${MACHINE_NAME:-ETC-${callsign}}"
    
    if [ $DRY_RUN -eq 1 ]; then
        log "DRY-RUN" "Would set hostname to: $machine_name"
        return 0
    fi
    
    # Set hostname
    echo "$machine_name" > "${SQUASHFS_DIR}/etc/hostname"
    
    # Update /etc/hosts
    cat > "${SQUASHFS_DIR}/etc/hosts" <<EOF
127.0.0.1       localhost
127.0.1.1       $machine_name

::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF
    
    log "SUCCESS" "Hostname set to: $machine_name"
}

customize_wifi() {
    log "INFO" "Configuring WiFi networks..."
    
    # shellcheck source=/dev/null
    source "$SECRETS_FILE"
    
    local nm_dir="${SQUASHFS_DIR}/etc/NetworkManager/system-connections"
    mkdir -p "$nm_dir"
    
    # Find all WIFI_SSID_* variables
    local wifi_count=0
    while IFS= read -r line; do
        if [[ "$line" =~ ^WIFI_SSID_([A-Z0-9_]+)= ]]; then
            local identifier="${BASH_REMATCH[1]}"
            local ssid_var="WIFI_SSID_${identifier}"
            local password_var="WIFI_PASSWORD_${identifier}"
            local autoconnect_var="WIFI_AUTOCONNECT_${identifier}"
            
            local ssid="${!ssid_var:-}"
            local password="${!password_var:-}"
            local autoconnect="${!autoconnect_var:-yes}"
            
            # Skip empty/template values
            if [[ -z "$ssid" ]] || [[ "$ssid" == "YOUR_"* ]]; then
                continue
            fi
            if [[ -z "$password" ]]; then
                log "WARN" "No password for $ssid, skipping"
                continue
            fi
            
            if [ $DRY_RUN -eq 1 ]; then
                log "DRY-RUN" "Would configure WiFi: $ssid"
                ((wifi_count++))
                continue
            fi
            
            # Normalize autoconnect
            [[ "${autoconnect,,}" == "no" || "${autoconnect,,}" == "false" ]] && autoconnect="false" || autoconnect="true"
            
            # Generate UUID
            local uuid
            uuid=$(cat /proc/sys/kernel/random/uuid)
            
            # Create connection file
            cat > "${nm_dir}/${ssid}.nmconnection" <<EOF
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
            
            chmod 600 "${nm_dir}/${ssid}.nmconnection"
            log "SUCCESS" "WiFi configured: $ssid"
            ((wifi_count++))
        fi
    done < "$SECRETS_FILE"
    
    if [ $wifi_count -eq 0 ]; then
        log "WARN" "No WiFi networks configured in secrets.env"
    else
        log "SUCCESS" "Configured $wifi_count WiFi network(s)"
    fi
}

customize_desktop() {
    log "INFO" "Configuring desktop preferences..."
    
    local skel_dconf="${SQUASHFS_DIR}/etc/skel/.config/dconf"
    mkdir -p "$skel_dconf"
    
    if [ $DRY_RUN -eq 1 ]; then
        log "DRY-RUN" "Would configure: dark mode, scaling, accessibility disabled"
        return 0
    fi
    
    # Create dconf user database directory
    mkdir -p "${skel_dconf}/user.d"
    
    # Create dconf settings file
    cat > "${skel_dconf}/user.d/00-emcomm-defaults" <<'EOF'
# Dark mode
[org/gnome/desktop/interface]
color-scheme='prefer-dark'
gtk-theme='Yaru-dark'
icon-theme='Yaru-dark'

# Disable accessibility features
[org/gnome/desktop/a11y]
always-show-universal-access-status=false

[org/gnome/desktop/a11y/applications]
screen-keyboard-enabled=false
screen-reader-enabled=false

[org/gnome/desktop/a11y/interface]
high-contrast=false

# Disable automatic brightness
[org/gnome/settings-daemon/plugins/power]
ambient-enabled=false

# Desktop scaling (1x by default, user can adjust)
[org/gnome/desktop/interface]
text-scaling-factor=1.0
EOF
    
    log "SUCCESS" "Desktop preferences configured"
}

customize_aprs() {
    log "INFO" "Configuring APRS applications (direwolf, YAAC)..."
    
    # shellcheck source=/dev/null
    source "$SECRETS_FILE"
    
    local callsign="${CALLSIGN:-N0CALL}"
    local aprs_ssid="${APRS_SSID:-10}"
    local aprs_passcode="${APRS_PASSCODE:--1}"
    local aprs_symbol="${APRS_SYMBOL:-r/}"
    local aprs_comment="${APRS_COMMENT:-EmComm iGate}"
    local digipeater_path="${DIGIPEATER_PATH:-WIDE1-1}"
    local enable_beacon="${ENABLE_APRS_BEACON:-no}"
    local beacon_interval="${APRS_BEACON_INTERVAL:-300}"
    local enable_igate="${ENABLE_APRS_IGATE:-yes}"
    local aprs_server="${APRS_SERVER:-noam.aprs2.net}"
    local direwolf_adevice="${DIREWOLF_ADEVICE:-plughw:1,0}"
    local direwolf_ptt="${DIREWOLF_PTT:-CM108}"
    
    if [ $DRY_RUN -eq 1 ]; then
        log "DRY-RUN" "Would configure APRS for: ${callsign}-${aprs_ssid}"
        return 0
    fi
    
    # Configure direwolf
    local direwolf_dir="${SQUASHFS_DIR}/etc/skel/.config/direwolf"
    mkdir -p "$direwolf_dir"
    
    cat > "${direwolf_dir}/direwolf.conf" <<EOF
# Direwolf Configuration - Internet iGate
# Generated by build-etc-iso.sh

ADEVICE ${direwolf_adevice}
ACHANNELS 1

MYCALL ${callsign}-${aprs_ssid}

IGSERVER ${aprs_server}
IGLOGIN ${callsign}-${aprs_ssid} ${aprs_passcode}

$(if [ "$enable_igate" = "yes" ]; then
    echo "IGTXVIA 0 ${digipeater_path}"
    echo "IGFILTER m/500"
else
    echo "# iGate DISABLED"
fi)

PTT ${direwolf_ptt}

$(if [ "$enable_beacon" = "yes" ]; then
    echo "PBEACON delay=1 every=${beacon_interval} overlay=S symbol=\"${aprs_symbol}\" comment=\"${aprs_comment}\" via=${digipeater_path}"
else
    echo "# Beacon DISABLED - enable after GPS connection"
fi)

LOGDIR /var/log/direwolf
EOF
    
    chmod 644 "${direwolf_dir}/direwolf.conf"
    
    # Configure YAAC
    local yaac_dir="${SQUASHFS_DIR}/etc/skel/.config/YAAC"
    mkdir -p "$yaac_dir"
    
    cat > "${yaac_dir}/YAAC.properties" <<EOF
# YAAC Configuration
# Generated by build-etc-iso.sh

callsign=${callsign}
ssid=${aprs_ssid}
aprsIsEnabled=true
aprsIsServer=${aprs_server}
aprsIsPort=14580
aprsIsPasscode=${aprs_passcode}
digipeaterEnabled=true
digipeaterAlias=${digipeater_path}
mapEnabled=true
onlineMapEnabled=false
comment=${aprs_comment}
EOF
    
    chmod 644 "${yaac_dir}/YAAC.properties"
    
    log "SUCCESS" "APRS configured for ${callsign}-${aprs_ssid}"
}

customize_user_and_autologin() {
    log "INFO" "Configuring user and autologin..."
    
    # shellcheck source=/dev/null
    source "$SECRETS_FILE"
    
    local fullname="${USER_FULLNAME:-EmComm User}"
    local username="${USER_USERNAME:-emcomm}"
    
    if [ $DRY_RUN -eq 1 ]; then
        log "DRY-RUN" "Would configure autologin for: $username"
        return 0
    fi
    
    # Configure LightDM autologin
    local lightdm_dir="${SQUASHFS_DIR}/etc/lightdm/lightdm.conf.d"
    mkdir -p "$lightdm_dir"
    
    cat > "${lightdm_dir}/50-autologin.conf" <<EOF
[Seat:*]
autologin-user=$username
autologin-user-timeout=0
user-session=ubuntu
EOF
    
    log "SUCCESS" "Autologin configured for: $username"
}

customize_vara_license() {
    log "INFO" "Configuring VARA license (if provided)..."
    
    # shellcheck source=/dev/null
    source "$SECRETS_FILE"
    
    local vara_fm_callsign="${VARA_FM_CALLSIGN:-}"
    local vara_fm_key="${VARA_FM_LICENSE_KEY:-}"
    local vara_hf_callsign="${VARA_HF_CALLSIGN:-}"
    local vara_hf_key="${VARA_HF_LICENSE_KEY:-}"
    
    if [ -z "$vara_fm_key" ] && [ -z "$vara_hf_key" ]; then
        log "INFO" "No VARA license keys configured, skipping"
        return 0
    fi
    
    if [ $DRY_RUN -eq 1 ]; then
        [ -n "$vara_fm_key" ] && log "DRY-RUN" "Would inject VARA FM license"
        [ -n "$vara_hf_key" ] && log "DRY-RUN" "Would inject VARA HF license"
        return 0
    fi
    
    # Create Wine registry snippet directory
    local wine_reg_dir="${SQUASHFS_DIR}/etc/skel/.wine/user.reg.d"
    mkdir -p "$wine_reg_dir"
    
    if [ -n "$vara_fm_key" ]; then
        cat > "${wine_reg_dir}/vara-fm-license.reg" <<EOF
REGEDIT4

[HKEY_CURRENT_USER\\Software\\VARA FM]
"Callsign"="${vara_fm_callsign}"
"License"="${vara_fm_key}"
EOF
        log "SUCCESS" "VARA FM license configured"
    fi
    
    if [ -n "$vara_hf_key" ]; then
        cat > "${wine_reg_dir}/vara-hf-license.reg" <<EOF
REGEDIT4

[HKEY_CURRENT_USER\\Software\\VARA]
"Callsign"="${vara_hf_callsign}"
"License"="${vara_hf_key}"
EOF
        log "SUCCESS" "VARA HF license configured"
    fi
}

customize_git_config() {
    log "INFO" "Configuring Git..."
    
    # shellcheck source=/dev/null
    source "$SECRETS_FILE"
    
    local git_name="${USER_FULLNAME:-User}"
    local git_email="${USER_EMAIL:-user@localhost}"
    
    if [[ "$git_name" == "Your Full Name" ]] || [[ "$git_email" == "your.email@example.com" ]]; then
        log "WARN" "Git not configured - template values in secrets.env"
        return 0
    fi
    
    if [ $DRY_RUN -eq 1 ]; then
        log "DRY-RUN" "Would configure Git for: $git_name <$git_email>"
        return 0
    fi
    
    cat > "${SQUASHFS_DIR}/etc/skel/.gitconfig" <<EOF
[user]
    name = $git_name
    email = $git_email
[init]
    defaultBranch = main
[pull]
    rebase = false
EOF
    
    log "SUCCESS" "Git configured for: $git_name"
}

create_build_manifest() {
    log "INFO" "Creating build manifest..."
    
    # shellcheck source=/dev/null
    source "$SECRETS_FILE"
    
    local manifest_file="${SQUASHFS_DIR}/etc/emcomm-customizations-manifest.txt"
    
    if [ $DRY_RUN -eq 1 ]; then
        log "DRY-RUN" "Would create manifest at: $manifest_file"
        return 0
    fi
    
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
    
    # Create new squashfs with compression
    mksquashfs "$SQUASHFS_DIR" "$new_squashfs" \
        -comp xz \
        -b 1M \
        -Xbcj x86 \
        -noappend
    
    # Replace original squashfs
    mv "$new_squashfs" "$SQUASHFS_FILE"
    
    # Update filesystem.size
    local fs_size
    fs_size=$(du -s "$SQUASHFS_DIR" | cut -f1)
    echo "$fs_size" > "$(dirname "$SQUASHFS_FILE")/filesystem.size"
    
    log "SUCCESS" "Squashfs rebuilt"
}

rebuild_iso() {
    log "INFO" "Rebuilding ISO image..."
    
    mkdir -p "$OUTPUT_DIR"
    
    if [ $DRY_RUN -eq 1 ]; then
        log "DRY-RUN" "Would create ISO: $OUTPUT_ISO"
        return 0
    fi
    
    # Calculate MD5 sums
    log "INFO" "Calculating checksums..."
    (cd "$ISO_EXTRACT_DIR" && find . -type f -print0 | xargs -0 md5sum > md5sum.txt)
    
    # Rebuild ISO with xorriso
    log "INFO" "Creating ISO image..."
    xorriso -as mkisofs \
        -r -V "ETC_${RELEASE_NUMBER^^}_CUSTOM" \
        -cache-inodes \
        -J -l \
        -b isolinux/isolinux.bin \
        -c isolinux/boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -eltorito-alt-boot \
        -e boot/grub/efi.img \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
        -o "$OUTPUT_ISO" \
        "$ISO_EXTRACT_DIR"
    
    # Make ISO hybrid (bootable from USB)
    if command -v isohybrid &>/dev/null; then
        isohybrid --uefi "$OUTPUT_ISO" 2>/dev/null || true
    fi
    
    local iso_size
    iso_size=$(du -h "$OUTPUT_ISO" | cut -f1)
    
    log "SUCCESS" "ISO created: $OUTPUT_ISO ($iso_size)"
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
    
    # Apply customizations
    log "INFO" ""
    log "INFO" "=== Applying Customizations ==="
    
    customize_hostname
    customize_wifi
    customize_desktop
    customize_aprs
    customize_user_and_autologin
    customize_vara_license
    customize_git_config
    create_build_manifest
    
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

while getopts "r:t:ldvh" opt; do
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
        v)
            set -x
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
