#!/bin/bash
#
# Script Name: build-etc-iso.sh
# Description: Fully automated ETC ISO customization using xorriso/squashfs (no Cubic GUI)
# Usage: ./build-etc-iso.sh [OPTIONS]
# Options:
#   -r MODE   Release mode: stable, latest, or tag (default: latest)
#   -t TAG    Specify release tag (required when -r tag)
#   -l        List available tags from GitHub and exit
#   -d        Debug mode (show DEBUG log messages)
#   -v        Verbose mode (enable set -x)
#   -m        Minimal build (omit cache files from ISO)
#   -h        Show this help message
# Author: KD7DGF
# Date: 2025-11-29
# Method: Direct ISO modification via xorriso/squashfs (fully automated, no Cubic)
#

set -euo pipefail

# Error trap to help diagnose where script fails
trap 'echo "[ERROR] Script failed at line $LINENO with exit code $?. Command: $BASH_COMMAND" | tee -a "${LOG_FILE:-/tmp/build-etc-iso-error.log}"' ERR

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
RELEASE_MODE="latest"
SPECIFIED_TAG=""
MINIMAL_BUILD=0                           # When 1, omit cache files from ISO to reduce size
KEEP_WORK=0                               # When 1, preserve .work directory for iterative debugging
WRITE_TO_USB=""                           # USB device path for dd write (e.g., /dev/sdb)
VENTOY_MOUNT=""                           # Path to mounted Ventoy USB

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
    
    # Always log to file (including DEBUG) - use sync to flush
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    sync  # Flush to disk so we don't lose log entries on crash
    
    # Log to console with color (DEBUG only shown if DEBUG_MODE=1)
    # Redirect to stderr so it doesn't pollute stdout for pipe operations
    case "$level" in
        ERROR)   echo -e "${RED}[$level]${NC} $message" >&2 ;;
        WARN)    echo -e "${YELLOW}[$level]${NC} $message" >&2 ;;
        SUCCESS) echo -e "${GREEN}[$level]${NC} $message" >&2 ;;
        INFO)    echo -e "${BLUE}[$level]${NC} $message" >&2 ;;
        DEBUG)   
            if [ $DEBUG_MODE -eq 1 ]; then
                echo -e "${CYAN}[$level]${NC} $message" >&2
            fi
            ;;
        *)       echo "[$level] $message" >&2 ;;
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
    -a        Include et-os-addons (WSJT-X Improved, GridTracker 2, SSTV, weather tools)
              Adds ~2GB to ISO but enables FT8/FT4 and extended radio modes
    -d        Debug mode (show DEBUG log messages on console)
    -k        Keep work directory after build (for iterative debugging)
    -m        Minimal build (omit cache files from ISO to reduce size)
    -v        Verbose mode (enable bash -x debugging)
    -h        Show this help message

USB WRITE OPTIONS:
    --write-to [/dev/sdX]
              Write ISO directly to USB device with dd (ERASES DEVICE!)
              If device is omitted, detects USB drives and prompts for selection.
              Automatically ejects when complete. This is the recommended method.
              Examples:
                sudo ./build-etc-iso.sh -r stable --write-to          # auto-detect
                sudo ./build-etc-iso.sh -r stable --write-to /dev/sdb # specific device
              
    --ventoy /path/to/ventoy
              Copy ISO + config files to mounted Ventoy USB
              Ventoy ignores ISO boot params, so extra config files are needed.
              Example: sudo ./build-etc-iso.sh -r stable --ventoy /media/user/Ventoy

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

    # Build and write to USB (auto-detect device - RECOMMENDED)
    sudo ./build-etc-iso.sh -r stable --write-to

    # Build and write to specific USB device
    sudo ./build-etc-iso.sh -r stable --write-to /dev/sdb

    # Build and copy to Ventoy USB
    sudo ./build-etc-iso.sh -r stable --ventoy /media/\$USER/Ventoy

    # Build from latest development tag
    sudo ./build-etc-iso.sh -r latest

    # Build specific version
    sudo ./build-etc-iso.sh -r tag -t emcomm-tools-os-community-20251113-r5-build17

    # Build with debug output for troubleshooting
    sudo ./build-etc-iso.sh -r stable -d

    # Minimal build (smaller ISO, no embedded cache)
    sudo ./build-etc-iso.sh -r stable -m

    # Build with expert enhancements (FT8, GridTracker, SSTV)
    sudo ./build-etc-iso.sh -r stable -a

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
    if [ -n "$BUILD_NUMBER" ]; then
        log "INFO" "  Build: $BUILD_NUMBER"
    fi
    log "INFO" "  Date: $DATE_VERSION"
    
    return 0
}

# ============================================================================
# Prerequisites Check
# ============================================================================

# shellcheck disable=SC2120
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
    unsquashfs -d "$squashfs_dir" -f "$squashfs_file" | while IFS= read -r line; do
        # Show progress lines (unsquashfs outputs percentage)
        if [[ "$line" =~ ^[0-9] ]] || [[ "$line" =~ created ]]; then
            printf "\r  %s" "$line"
        fi
    done
    echo ""  # newline after progress
    
    # Store paths for later
    ISO_EXTRACT_DIR="$iso_extract_dir"
    SQUASHFS_DIR="$squashfs_dir"
    SQUASHFS_FILE="$squashfs_file"
    
    # CRITICAL: Make boot config files writable (ISO files extract read-only)
    # Without this, sed modifications to grub.cfg silently fail!
    log "DEBUG" "Making boot configuration files writable..."
    chmod -R u+w "${iso_extract_dir}/boot" 2>/dev/null || log "WARN" "Could not set boot directory permissions"
    
    log "SUCCESS" "ISO extracted successfully"
    return 0
}

# ============================================================================
# ETC Installation (chroot)
# ============================================================================

setup_chroot_mounts() {
    # Set up bind mounts for chroot environment
    log "DEBUG" "Setting up chroot bind mounts..."
    
    # Check if already mounted to avoid double-mounting
    if mountpoint -q "${SQUASHFS_DIR}/dev" 2>/dev/null; then
        log "DEBUG" "Chroot mounts already active, skipping"
        return 0
    fi
    
    mount --bind /dev "${SQUASHFS_DIR}/dev" || { log "WARN" "Failed to mount /dev"; return 1; }
    mount --bind /dev/pts "${SQUASHFS_DIR}/dev/pts" || { log "WARN" "Failed to mount /dev/pts"; }
    mount --bind /proc "${SQUASHFS_DIR}/proc" || { log "WARN" "Failed to mount /proc"; return 1; }
    mount --bind /sys "${SQUASHFS_DIR}/sys" || { log "WARN" "Failed to mount /sys"; return 1; }
    mount --bind /run "${SQUASHFS_DIR}/run" 2>/dev/null || true  # /run may not exist
    
    # Copy resolv.conf for network access
    cp /etc/resolv.conf "${SQUASHFS_DIR}/etc/resolv.conf" 2>/dev/null || true
    
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
    
    # Source secrets for map configuration
    # shellcheck source=/dev/null
    source "$SECRETS_FILE"
    
    # Extract ETC tarball to a temp location in the chroot
    local etc_install_dir="${SQUASHFS_DIR}/tmp/etc-installer"
    log "DEBUG" "Extracting ETC installer to: $etc_install_dir"
    
    mkdir -p "$etc_install_dir"
    tar -xzf "$ETC_TARBALL_PATH" -C "$etc_install_dir" --strip-components=1
    
    # Verify extraction - GitHub tarballs have a nested structure
    # After --strip-components=1, we should have scripts/install.sh
    if [ ! -d "${etc_install_dir}/scripts" ]; then
        log "ERROR" "ETC tarball extraction failed - scripts/ directory not found"
        log "DEBUG" "Contents of $etc_install_dir:"
        find "$etc_install_dir" -maxdepth 1 -exec ls -ld {} \; 2>&1 | while read -r line; do log "DEBUG" "  $line"; done
        # Try to find install.sh anywhere
        local found_install
        found_install=$(find "$etc_install_dir" -name "install.sh" -type f 2>/dev/null | head -1)
        if [ -n "$found_install" ]; then
            log "ERROR" "Found install.sh at: $found_install"
            log "ERROR" "GitHub tarball may have different structure - please report this issue"
        fi
        return 1
    fi
    log "DEBUG" "Tarball extracted successfully, scripts/ directory found"
    
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
    
    # Install build dependencies needed by ETC installer scripts
    log "INFO" "Installing build dependencies for ETC..."
    chroot "${SQUASHFS_DIR}" /bin/bash -c "
        apt-get update
        apt-get install -y curl git build-essential make
    " || { log "WARN" "Failed to install some build dependencies, continuing..."; }
    
    # Patch known download scripts to use secrets.env values when configured.
    # If a variable is NOT set, the original script runs unchanged (dialog passes through).
    # This ensures future ETC versions with new dialogs still work interactively.
    
    log "INFO" "Patching ETC download scripts (configured values only)..."
    
    # Patch download-osm-maps.sh ONLY if OSM_MAP_STATE is configured
    # If not set, leave original script intact (dialog will pass through to terminal)
    if [[ -n "${OSM_MAP_STATE:-}" ]]; then
        log "INFO" "OSM_MAP_STATE=${OSM_MAP_STATE} - will download state map automatically"
        cat > "${etc_install_dir}/scripts/download-osm-maps.sh" <<OSMSCRIPT
#!/bin/bash
# Patched by EmComm Tools Customizer - uses OSM_MAP_STATE from secrets.env
set -e

PBF_MAP_DIR=/etc/skel/my-maps
[ ! -e \${PBF_MAP_DIR} ] && mkdir -v \${PBF_MAP_DIR}

STATE_NAME="${OSM_MAP_STATE}"
download_file="\${STATE_NAME}-latest.osm.pbf"
download_url="http://download.geofabrik.de/north-america/us/\${download_file}"

if [ -e "\${PBF_MAP_DIR}/\${download_file}" ]; then
    et-log "\${download_file} already exists. Skipping download."
else
    et-log "Downloading \${download_url}..."
    curl -L -f -O "\${download_url}"
    
    if [ -e "\${download_file}" ]; then
        navit_osm_bin_file="\${STATE_NAME}-latest.osm.bin"
        navit_osm_bin_file_path="/etc/skel/.navit/maps/\${navit_osm_bin_file}"
        et-log "Generating OSM map for Navit: \${navit_osm_bin_file_path}"
        maptool --protobuf -i "\${download_file}" "\${navit_osm_bin_file_path}"
        
        et-log "Moving OSM .pbf to \${PBF_MAP_DIR}"
        mv -v "\${download_file}" "\${PBF_MAP_DIR}"
    fi
fi
OSMSCRIPT
        chmod +x "${etc_install_dir}/scripts/download-osm-maps.sh"
    else
        log "INFO" "OSM_MAP_STATE not set - original dialog will be shown"
    fi
    
    # Patch download-et-maps.sh ONLY if ET_MAP_REGION is configured
    # If not set, leave original script intact (dialog will pass through to terminal)
    if [[ -n "${ET_MAP_REGION:-}" ]]; then
        log "INFO" "ET_MAP_REGION=${ET_MAP_REGION} - will download pre-rendered tiles automatically"
        # Validate region before patching
        case "${ET_MAP_REGION}" in
            us|ca|world)
                local et_map_file
                case "${ET_MAP_REGION}" in
                    us) et_map_file="osm-us-zoom0to11-20251120.mbtiles" ;;
                    ca) et_map_file="osm-ca-zoom0to10-20251120.mbtiles" ;;
                    world) et_map_file="osm-world-zoom0to7-20251121.mbtiles" ;;
                esac
                cat > "${etc_install_dir}/scripts/download-et-maps.sh" <<ETMAPSCRIPT
#!/bin/bash
# Patched by EmComm Tools Customizer - uses ET_MAP_REGION from secrets.env
set -e

BASE_URL="https://github.com/thetechprepper/emcomm-tools-os-community/releases/download"
RELEASE="emcomm-tools-os-community-20251128-r5-final-5.0.0"
TILESET_DIR="/etc/skel/.local/share/emcomm-tools/mbtileserver/tilesets"

[ ! -e "\${TILESET_DIR}" ] && mkdir -vp "\${TILESET_DIR}"

DOWNLOAD_FILE="${et_map_file}"
DOWNLOAD_URL="\${BASE_URL}/\${RELEASE}/\${DOWNLOAD_FILE}"

if [[ -e "\${TILESET_DIR}/\${DOWNLOAD_FILE}" ]]; then
    et-log "\${DOWNLOAD_FILE} already exists. Skipping download."
else
    et-log "Downloading \${DOWNLOAD_URL}..."
    curl -L -f -o "\${DOWNLOAD_FILE}" "\${DOWNLOAD_URL}"
    
    et-log "Moving \${DOWNLOAD_FILE} to \${TILESET_DIR}"
    mv -v "\${DOWNLOAD_FILE}" "\${TILESET_DIR}"
fi
ETMAPSCRIPT
                chmod +x "${etc_install_dir}/scripts/download-et-maps.sh"
                ;;
            *)
                log "WARN" "Invalid ET_MAP_REGION='${ET_MAP_REGION}' - must be us, ca, or world. Dialog will be shown."
                ;;
        esac
    else
        log "INFO" "ET_MAP_REGION not set - original dialog will be shown"
    fi
    
    # Patch download-wikipedia.sh ONLY if WIKIPEDIA_SECTIONS is configured
    # Note: This script only runs if ET_EXPERT is set during install
    if [[ -n "${WIKIPEDIA_SECTIONS:-}" ]]; then
        log "INFO" "WIKIPEDIA_SECTIONS=${WIKIPEDIA_SECTIONS} - will download Wikipedia sections automatically"
        # Convert comma-separated list to space-separated for the script
        local wiki_sections_escaped="${WIKIPEDIA_SECTIONS//,/ }"
        cat > "${etc_install_dir}/scripts/download-wikipedia.sh" <<WIKIPEDIASCRIPT
#!/bin/bash
# Patched by EmComm Tools Customizer - uses WIKIPEDIA_SECTIONS from secrets.env
set -e

URL="http://download.kiwix.org/zim/wikipedia"
ZIM_DIR="/etc/skel/wikipedia"
HTML="/tmp/kiwix.html"

[ ! -e "\${ZIM_DIR}" ] && mkdir -v "\${ZIM_DIR}"

# Download the index page to find exact filenames
et-log "Downloading Wikipedia file index..."
curl -s -L -f -o "\${HTML}" "\${URL}"
if [ \$? -ne 0 ]; then
    et-log "Can't download list of files from \${URL}. Exiting..."
    exit 1
fi

# Download each configured section
for section in ${wiki_sections_escaped}; do
    et-log "Looking for Wikipedia section: \${section}"
    
    # Find the latest nopic file matching this section
    zim_file=\$(grep -o 'href="wikipedia_en_[^"]*'"\${section}"'[^"]*_nopic[^"]*\\.zim"' "\${HTML}" | \\
               sed 's/href="//; s/"\$//' | sort -V | tail -1)
    
    if [[ -n "\$zim_file" ]]; then
        download_url="\${URL}/\${zim_file}"
        if [[ -e "\${ZIM_DIR}/\${zim_file}" ]]; then
            et-log "\${zim_file} already exists. Skipping."
        else
            et-log "Downloading \${download_url}..."
            curl -L -f -O "\${download_url}" && mv "\${zim_file}" "\${ZIM_DIR}"
        fi
    else
        et-log "Warning: Could not find Wikipedia section '\${section}'"
    fi
done

rm -f "\${HTML}"
WIKIPEDIASCRIPT
        chmod +x "${etc_install_dir}/scripts/download-wikipedia.sh"
    else
        log "INFO" "WIKIPEDIA_SECTIONS not set - original dialog will be shown (if ET_EXPERT is set)"
    fi
    
    # Verify the ETC installer was extracted correctly
    if [ ! -f "${etc_install_dir}/scripts/install.sh" ]; then
        log "ERROR" "ETC install.sh not found at expected location!"
        log "ERROR" "Expected: ${etc_install_dir}/scripts/install.sh"
        log "DEBUG" "Contents of etc_install_dir:"
        find "${etc_install_dir}" -maxdepth 1 -exec ls -ld {} \; 2>&1 | while read -r line; do log "DEBUG" "  $line"; done
        if [ -d "${etc_install_dir}/scripts" ]; then
            log "DEBUG" "Contents of scripts/:"
            find "${etc_install_dir}/scripts" -maxdepth 1 -exec ls -ld {} \; 2>&1 | while read -r line; do log "DEBUG" "  $line"; done
        fi
        cleanup_chroot_mounts
        trap - EXIT
        return 1
    fi
    log "DEBUG" "Verified install.sh exists at: ${etc_install_dir}/scripts/install.sh"
    
    log "INFO" "Running ETC installer (this takes a while)..."
    log "INFO" "NOTE: If map variables are not configured, dialog prompts will appear."
    log "INFO" "      Configure OSM_MAP_STATE, ET_MAP_REGION in secrets.env for automated builds."
    if [[ -n "${ET_EXPERT:-}" ]]; then
        log "INFO" "      ET_EXPERT is set - Wikipedia download dialog will be shown (or auto if WIKIPEDIA_SECTIONS set)."
    fi
    
    # Determine if we need interactive mode (any unconfigured dialogs)
    local needs_interactive=0
    [[ -z "${OSM_MAP_STATE:-}" ]] && needs_interactive=1
    [[ -z "${ET_MAP_REGION:-}" ]] && needs_interactive=1
    # Wikipedia dialog only shows with ET_EXPERT set
    if [[ -n "${ET_EXPERT:-}" ]] && [[ -z "${WIKIPEDIA_SECTIONS:-}" ]]; then
        needs_interactive=1
    fi
    
    # Pass ET_EXPERT through if set (controls Wikipedia download in ETC)
    local et_expert_val="${ET_EXPERT:-}"
    
    # Use a temp file to capture exit code since pipelines lose it
    local exit_code_file="${WORK_DIR}/etc_install_exit_code"
    
    if [[ $needs_interactive -eq 1 ]]; then
        log "INFO" "Some map variables not configured - dialogs will be shown interactively"
        # Run with terminal attached so dialog can work
        # Use subshell to capture exit code properly
        (
            chroot "${SQUASHFS_DIR}" /bin/bash -c "
                export DEBIAN_FRONTEND=noninteractive
                export NEEDRESTART_MODE=a
                export ET_EXPERT='${et_expert_val}'
                cd /tmp/etc-installer/scripts
                ./install.sh
            " 2>&1 | tee -a "${LOG_FILE}" | while IFS= read -r line; do
                echo "[ETC] $line"
            done
            echo "${PIPESTATUS[0]}" > "$exit_code_file"
        )
    else
        log "INFO" "All map variables configured - running fully automated"
        # Use subshell to capture exit code properly
        (
            chroot "${SQUASHFS_DIR}" /bin/bash -c "
                export DEBIAN_FRONTEND=noninteractive
                export NEEDRESTART_MODE=a
                export ET_EXPERT='${et_expert_val}'
                cd /tmp/etc-installer/scripts
                ./install.sh
            " </dev/null 2>&1 | tee -a "${LOG_FILE}" | while IFS= read -r line; do
                log "ETC" "$line"
            done
            echo "${PIPESTATUS[0]}" > "$exit_code_file"
        )
    fi
    
    # Read the exit code from the temp file
    local exit_code=1  # Default to failure
    if [ -f "$exit_code_file" ]; then
        exit_code=$(cat "$exit_code_file")
        rm -f "$exit_code_file"
    fi
    
    if [ "$exit_code" -ne 0 ]; then
        log "ERROR" "ETC installation failed with exit code: $exit_code"
        cleanup_chroot_mounts
        trap - EXIT
        return 1
    fi
    
    # Post-install customizations (while chroot mounts are still active)
    log "INFO" "Applying post-install customizations..."
    
    # Configure ham radio CAT control (Anytone D578UV)
    log "DEBUG" "Configuring radio CAT control..."
    customize_radio_configs_in_chroot
    
    # CHIRP and Microsoft Edge: NOW INSTALLED ON FIRST LOGIN (not during build)
    # This prevents ETC's post-install cleanup from removing them as "development" packages
    # See setup_first_login_packages() - implemented via /etc/profile.d/ startup script
    log "DEBUG" "Radio programming utilities (CHIRP, Edge) will be installed on first login"
    
    # Clean up mounts after all in-chroot work is done
    cleanup_chroot_mounts
    trap - EXIT
    
    # Remove installer files
    log "DEBUG" "Cleaning up installer files..."
    rm -rf "$etc_install_dir"
    
    # Verify ETC actually installed key components
    log "INFO" "Verifying ETC installation..."
    local verification_failed=0
    
    # Check for ETC marker files/directories
    if [ ! -d "${SQUASHFS_DIR}/opt/emcomm-tools" ]; then
        log "WARN" "ETC marker directory not found: /opt/emcomm-tools"
    else
        log "DEBUG" "Verified: /opt/emcomm-tools directory exists"
    fi
    
    if [ ! -f "${SQUASHFS_DIR}/usr/local/bin/et-user" ]; then
        log "WARN" "et-user command not found - may be installed at runtime"
        # Note: et-user is installed by ETC scripts but location may vary
    else
        log "DEBUG" "Verified: et-user command installed"
    fi
    
    # Check for key ham radio tools
    local expected_tools=("direwolf" "pat")
    for tool in "${expected_tools[@]}"; do
        if ! chroot "${SQUASHFS_DIR}" /bin/bash -c "command -v $tool" &>/dev/null; then
            log "WARN" "Expected tool not found in chroot: $tool"
            # Don't fail on individual tools, just warn
        else
            log "DEBUG" "Verified tool installed: $tool"
        fi
    done
    
    if [ "$verification_failed" -eq 1 ]; then
        log "ERROR" "ETC installation verification failed - key components missing"
        log "ERROR" "The resulting ISO would be a base Ubuntu install, not ETC!"
        return 1
    fi
    
    log "SUCCESS" "EmComm Tools Community installed and verified successfully"
    return 0
}

# ============================================================================
# Customization Functions (apply AFTER ETC is installed)
# ============================================================================


create_fresh_user_backup() {
    log "INFO" "Creating fresh user backup from running ETC system..."
    
    # Only create backup if running system has et-user-backup installed
    if ! command -v et-user-backup &> /dev/null; then
        log "INFO" "et-user-backup command not found - system not running ETC or command not in PATH"
        log "INFO" "Skipping fresh backup creation (will use existing backup if available)"
        return 0
    fi
    
    # Check for existing backup from today in home folder (et-user-backup default location)
    local today_date
    today_date=$(date +'%Y%m%d')
    local existing_backup
    existing_backup=$(find "$HOME" -maxdepth 1 -name "etc-user-backup-*-${today_date}.tar.gz" -type f 2>/dev/null | head -1)
    
    if [ -n "$existing_backup" ] && [ -f "$existing_backup" ]; then
        log "INFO" "Found existing backup from today: $(basename "$existing_backup")"
        log "INFO" "Skipping backup creation (delete file to force new backup)"
        return 0
    fi
    
    log "INFO" "Running et-user-backup (answering prompts automatically)..."
    
    # et-user-backup has interactive prompts:
    # 1. "Can [file] be overwritten? (y/n)" - if backup exists
    # 2. "Do you want see the full list of files backed up? (y/n)" - at end
    # We answer 'y' to overwrite and 'n' to skip file list
    # Use timeout to prevent infinite hangs
    if timeout 60 bash -c 'yes y | head -1; yes n | head -1' | et-user-backup 2>&1 | grep -v "^$" | tee -a "$LOG_FILE"; then
        log "DEBUG" "et-user-backup command completed"
    else
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            log "WARN" "et-user-backup timed out after 60 seconds"
        else
            log "DEBUG" "et-user-backup exited with code: $exit_code (may still have succeeded)"
        fi
    fi
    
    # Look for the backup file in home directory (where et-user-backup puts it)
    local user_backup_file
    user_backup_file=$(find "$HOME" -maxdepth 1 -name "etc-user-backup-*.tar.gz" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    
    if [ -n "$user_backup_file" ] && [ -f "$user_backup_file" ]; then
        local backup_size
        backup_size=$(du -h "$user_backup_file" | cut -f1)
        log "SUCCESS" "User backup created: $(basename "$user_backup_file") (${backup_size})"
        log "INFO" "Backup location: $user_backup_file"
        return 0
    else
        log "WARN" "et-user-backup completed but output file not found in home directory"
        return 1
    fi
}

restore_user_backup() {
    log "INFO" "Checking for ETC user backups..."
    
    local cache_dir="${SCRIPT_DIR}/cache"
    local home_dir="$HOME"
    local user_backup=""
    local wine_backup=""
    local backup_count=0
    
    # Auto-detect user backup (etc-user-backup-*.tar.gz)
    # Priority: 1) Home folder (et-user-backup default), 2) Cache folder
    # Always select the most recent (newest) backup by modification time
    if compgen -G "${home_dir}/etc-user-backup-*.tar.gz" > /dev/null 2>&1; then
        backup_count=$(find "${home_dir}" -maxdepth 1 -name 'etc-user-backup-*.tar.gz' -type f 2>/dev/null | wc -l)
        user_backup=$(find "${home_dir}" -maxdepth 1 -name 'etc-user-backup-*.tar.gz' -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
        if [ "$backup_count" -gt 1 ]; then
            log "INFO" "Found ${backup_count} user backups in home folder, using newest: $(basename "$user_backup")"
        else
            log "INFO" "Found user backup in home folder: $(basename "$user_backup")"
        fi
    elif compgen -G "${cache_dir}/etc-user-backup-*.tar.gz" > /dev/null 2>&1; then
        backup_count=$(find "${cache_dir}" -maxdepth 1 -name 'etc-user-backup-*.tar.gz' -type f 2>/dev/null | wc -l)
        user_backup=$(find "${cache_dir}" -maxdepth 1 -name 'etc-user-backup-*.tar.gz' -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
        if [ "$backup_count" -gt 1 ]; then
            log "INFO" "Found ${backup_count} user backups in cache folder, using newest: $(basename "$user_backup")"
        else
            log "INFO" "Found user backup in cache folder: $(basename "$user_backup")"
        fi
    fi
    
    # Auto-detect wine backup (etc-wine-backup-*.tar.gz)
    # Priority: 1) Home folder, 2) Cache folder
    # Always select the most recent (newest) backup by modification time
    if compgen -G "${home_dir}/etc-wine-backup-*.tar.gz" > /dev/null 2>&1; then
        backup_count=$(find "${home_dir}" -maxdepth 1 -name 'etc-wine-backup-*.tar.gz' -type f 2>/dev/null | wc -l)
        wine_backup=$(find "${home_dir}" -maxdepth 1 -name 'etc-wine-backup-*.tar.gz' -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
        if [ "$backup_count" -gt 1 ]; then
            log "INFO" "Found ${backup_count} Wine backups in home folder, using newest: $(basename "$wine_backup")"
        else
            log "INFO" "Found Wine backup in home folder: $(basename "$wine_backup")"
        fi
    elif compgen -G "${cache_dir}/etc-wine-backup-*.tar.gz" > /dev/null 2>&1; then
        backup_count=$(find "${cache_dir}" -maxdepth 1 -name 'etc-wine-backup-*.tar.gz' -type f 2>/dev/null | wc -l)
        wine_backup=$(find "${cache_dir}" -maxdepth 1 -name 'etc-wine-backup-*.tar.gz' -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
        if [ "$backup_count" -gt 1 ]; then
            log "INFO" "Found ${backup_count} Wine backups in cache folder, using newest: $(basename "$wine_backup")"
        else
            log "INFO" "Found Wine backup in cache folder: $(basename "$wine_backup")"
        fi
    fi
    
    # Check if any backups were found
    if [ -z "$user_backup" ] && [ -z "$wine_backup" ]; then
        log "DEBUG" "No backup files found in home (~/) or cache/"
        log "INFO" "To use backups, run 'et-user-backup' or place etc-user-backup-*.tar.gz in ~/ or cache/"
        return 0
    fi
    
    # Restore user backup (et-user-backup tarball)
    # Contains: .config/emcomm-tools, .local/share/emcomm-tools, .local/share/pat
    if [ -n "$user_backup" ]; then
        log "INFO" "Restoring user backup: $(basename "$user_backup")"
        
        # Verify it's a valid tarball
        if ! tar tzf "$user_backup" >/dev/null 2>&1; then
            log "ERROR" "Invalid tarball: $user_backup"
            return 1
        fi
        
        # Extract to /etc/skel with timeout and progress
        local skel_dir="${SQUASHFS_DIR}/etc/skel"
        mkdir -p "$skel_dir"
        
        log "DEBUG" "Extracting backup with timeout (300 seconds)..."
        # Use timeout to prevent hangs; extract with verbose progress
        if timeout 300 tar xzf "$user_backup" -C "$skel_dir" --checkpoint=.1000 --checkpoint-action=dot 2>&1 | tee -a "$LOG_FILE"; then
            log "SUCCESS" "User backup restored to /etc/skel"
        else
            local exit_code=$?
            if [ $exit_code -eq 124 ]; then
                log "WARN" "Backup extraction timed out (>300 sec). Extracted files will be incomplete. Will try to use what was restored."
            else
                log "ERROR" "Backup extraction failed with code $exit_code"
                return 1
            fi
        fi
        
        # Verify extraction
        if [ -d "$skel_dir/.config/emcomm-tools" ]; then
            log "SUCCESS" "ETC config restored"
        fi
        if [ -d "$skel_dir/.local/share/emcomm-tools" ]; then
            log "SUCCESS" "ETC data restored"
        fi
        if [ -d "$skel_dir/.local/share/pat" ]; then
            log "SUCCESS" "Pat configuration restored"
        fi
    fi
    
    # Wine backup handling
    # .wine32 is very large (500MB+) and should be restored post-install
    # Create a restore script that will extract it automatically on first login
    if [ -n "$wine_backup" ]; then
        log "INFO" "Wine backup found - setting up automatic restoration..."
        
        # Copy the wine backup to /etc/skel for post-login restoration
        local skel_backups="${SQUASHFS_DIR}/etc/skel/.etc-backups"
        mkdir -p "$skel_backups"
        
        local wine_backup_dest="${skel_backups}/$(basename "$wine_backup")"
        log "DEBUG" "Copying Wine backup to: $wine_backup_dest"
        
        # Copy with progress indication
        cp -v "$wine_backup" "$wine_backup_dest" | tee -a "$LOG_FILE"
        
        # Create a one-time restore script
        local restore_script="${SQUASHFS_DIR}/etc/skel/.config/emcomm-tools/restore-wine.sh"
        mkdir -p "$(dirname "$restore_script")"
        
        cat > "$restore_script" <<'WINE_RESTORE'
#!/bin/bash
# Auto-restore Wine backup on first login (self-deleting)
BACKUP_FILE="${HOME}/.etc-backups/$(basename "${1:-}")"
if [ -f "$BACKUP_FILE" ]; then
    echo "Restoring Wine/VARA configuration from backup..."
    if tar xzf "$BACKUP_FILE" -C "$HOME"; then
        echo "✓ Wine backup restored successfully"
        rm -f "$BACKUP_FILE"
        rm -f "$0"  # Self-delete
    else
        echo "✗ Failed to restore Wine backup"
    fi
fi
WINE_RESTORE
        chmod 755 "$restore_script"
        
        log "SUCCESS" "Wine backup will be restored automatically on first login"
    fi
}

customize_hostname() {
    log "INFO" "Configuring hostname..."
    
    # shellcheck source=/dev/null
    source "$SECRETS_FILE"
    log "DEBUG" "Sourced secrets file: $SECRETS_FILE"
    
    local callsign="${CALLSIGN:-N0CALL}"
    local machine_name="${MACHINE_NAME:-ETC-${callsign}}"
    log "DEBUG" "CALLSIGN=$callsign, MACHINE_NAME=$machine_name"
    
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

validate_wifi_config() {
    log "INFO" "Validating WiFi configuration..."
    
    local wifi_count=0
    local validation_errors=0
    
    # Scan for WiFi networks in secrets.env
    while IFS= read -r line; do
        if [[ "$line" =~ ^WIFI_SSID_([A-Z0-9_]+)= ]]; then
            local identifier="${BASH_REMATCH[1]}"
            
            local ssid_var="WIFI_SSID_${identifier}"
            local password_var="WIFI_PASSWORD_${identifier}"
            local ssid="${!ssid_var:-}"
            local password="${!password_var:-}"
            
            # Skip template values
            if [[ -z "$ssid" ]] || [[ "$ssid" == "YOUR_"* ]]; then
                log "DEBUG" "Skipping template SSID: '$ssid'"
                continue
            fi
            
            wifi_count=$((wifi_count + 1))
            
            # Validate SSID format
            if [ -z "$ssid" ]; then
                log "ERROR" "WiFi $identifier: SSID is empty"
                validation_errors=$((validation_errors + 1))
            elif [ ${#ssid} -gt 32 ]; then
                log "ERROR" "WiFi $identifier: SSID too long (max 32 chars): '$ssid'"
                validation_errors=$((validation_errors + 1))
            else
                log "DEBUG" "✓ WiFi $identifier SSID valid: '$ssid'"
            fi
            
            # Validate password
            if [ -z "$password" ]; then
                log "WARN" "WiFi $identifier: No password configured - will be skipped"
                validation_errors=$((validation_errors + 1))
            elif [ ${#password} -lt 8 ]; then
                log "ERROR" "WiFi $identifier: Password too short (min 8 chars for WPA2)"
                validation_errors=$((validation_errors + 1))
            elif [ ${#password} -gt 63 ]; then
                log "ERROR" "WiFi $identifier: Password too long (max 63 chars for WPA2)"
                validation_errors=$((validation_errors + 1))
            else
                log "DEBUG" "✓ WiFi $identifier password valid (${#password} chars)"
            fi
        fi
    done < "$SECRETS_FILE"
    
    if [ $wifi_count -eq 0 ]; then
        log "WARN" "No WiFi networks found in configuration"
    elif [ $validation_errors -gt 0 ]; then
        log "WARN" "WiFi validation found $validation_errors error(s) - check above"
    else
        log "SUCCESS" "All $wifi_count WiFi network(s) validated successfully"
    fi
}

customize_wifi() {
    log "INFO" "Configuring WiFi networks..."
    
    # shellcheck source=/dev/null
    source "$SECRETS_FILE"
    
    # Pre-build WiFi validation
    validate_wifi_config
    
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
            
            # Normalize autoconnect
            [[ "${autoconnect,,}" == "no" || "${autoconnect,,}" == "false" ]] && autoconnect="false" || autoconnect="true"
            
            # Generate UUID
            local uuid
            uuid=$(cat /proc/sys/kernel/random/uuid)
            log "DEBUG" "Generated UUID for $ssid: $uuid"
            
            local conn_file="${nm_dir}/${ssid}.nmconnection"
            log "DEBUG" "Creating connection file: $conn_file"
            
            # Create connection file (matching NetworkManager keyfile format)
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
auth-alg=open
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

# ============================================================================
# Update System Release Information
# ============================================================================

update_release_info() {
    log "INFO" "Updating system release information..."
    
    # RELEASE_NUMBER and BUILD_NUMBER are already set globally by download_etc_tarball()
    # Do NOT source secrets.env here - it doesn't contain these variables
    
    local lsb_release_file="${SQUASHFS_DIR}/etc/lsb-release"
    
    if [ ! -f "$lsb_release_file" ]; then
        log "WARN" "lsb-release not found at: $lsb_release_file"
        return 0
    fi
    
    # Show current state BEFORE modification
    log "DEBUG" "Current lsb-release BEFORE update:"
    grep DISTRIB "$lsb_release_file" | while IFS= read -r line; do
        log "DEBUG" "  [BEFORE] $line"
    done
    
    # Update DISTRIB_DESCRIPTION to show clean release info (what conky displays)
    # Format mirrors Cubic's official format: ETC_R5_FINAL (with customization note)
    # Reference: https://community.emcommtools.com/getting-stated/create-etc-image.html
    local release_type=""
    if [[ "$RELEASE_TAG" =~ -final ]]; then
        release_type="FINAL"
    elif [[ "$RELEASE_TAG" =~ build[0-9]+ ]]; then
        release_type="$BUILD_NUMBER"
    else
        release_type="DEV"
    fi
    
    # Uppercase the release number (r5 → R5)
    local release_number_upper="${RELEASE_NUMBER^^}"
    
    # Format: ETC_R5_FINAL (CUSTOMIZED) to indicate this is our build
    local custom_description="ETC_${release_number_upper}_${release_type} (CUSTOMIZED)"
    
    log "DEBUG" "Updating DISTRIB_DESCRIPTION to: $custom_description"
    
    # Use sed to update the DISTRIB_DESCRIPTION line
    sed -i "s|DISTRIB_DESCRIPTION=.*|DISTRIB_DESCRIPTION=\"${custom_description}\"|" "$lsb_release_file"
    
    # VERIFY the change was applied
    if grep -q "CUSTOMIZED" "$lsb_release_file"; then
        log "SUCCESS" "Release info updated successfully"
    else
        log "ERROR" "DISTRIB_DESCRIPTION update FAILED!"
        log "DEBUG" "sed command may have failed - check file permissions"
    fi
    
    log "DEBUG" "lsb-release AFTER update:"
    grep DISTRIB "$lsb_release_file" | while IFS= read -r line; do
        log "DEBUG" "  [AFTER] $line"
    done
}

customize_desktop() {
    log "INFO" "Configuring desktop preferences..."
    
    # shellcheck source=/dev/null
    source "$SECRETS_FILE"
    log "DEBUG" "Sourced secrets file for desktop config"
    
    local color_scheme="${DESKTOP_COLOR_SCHEME:-prefer-dark}"
    local scaling="${DESKTOP_SCALING_FACTOR:-1.0}"
    local disable_a11y="${DISABLE_ACCESSIBILITY:-yes}"
    local auto_brightness="${AUTOMATIC_SCREEN_BRIGHTNESS:-false}"
    local dim_screen="${DIM_SCREEN:-true}"
    local screen_blank="${SCREEN_BLANK:-true}"
    local screen_blank_timeout="${SCREEN_BLANK_TIMEOUT:-300}"
    
    log "DEBUG" "Desktop config: color_scheme=$color_scheme, scaling=$scaling"
    log "DEBUG" "Display config: auto_brightness=$auto_brightness, dim=$dim_screen, blank=$screen_blank"
    
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
always-show-universal-access-status=true

[org/gnome/desktop/a11y/applications]
screen-keyboard-enabled=false
screen-reader-enabled=false

[org/gnome/desktop/a11y/interface]
high-contrast=false
large-text=false

[org/gnome/terminal/legacy]
menu-accelerator-enabled=true

[org/gnome/desktop/interface]
text-scaling-factor=1.0

[org/gnome/settings-daemon/peripherals/keyboard]
remember-numlock-state=true
EOF
    fi

    # Add display/brightness settings
    cat >> "$dconf_file" <<EOF

# Display and brightness settings
[org/gnome/settings-daemon/plugins/power]
ambient-enabled=${auto_brightness}
idle-dim=${dim_screen}
sleep-display-ac='${screen_blank_timeout}'
sleep-display-battery='${screen_blank_timeout}'
EOF

    # Compile dconf database so GNOME recognizes the settings on first boot
    log "INFO" "Compiling dconf database..."
    
    # dconf needs the database compiled from the keyfiles for GNOME to use them
    # We attempt to run dconf update with proper error handling
    if chroot "${SQUASHFS_DIR}" command -v dconf &>/dev/null; then
        # Try to compile dconf database with timeout to prevent hangs
        if timeout 15 chroot "${SQUASHFS_DIR}" \
            sh -c 'dconf update 2>&1 || true' | tee -a "$LOG_FILE"; then
            log "DEBUG" "dconf database update completed"
        else
            log "DEBUG" "dconf update timed out (expected in chroot without full dbus)"
        fi
    else
        log "DEBUG" "dconf not available in chroot - keyfiles will be compiled on first boot"
    fi
    
    log "DEBUG" "dconf settings written to $dconf_file"
    log "SUCCESS" "Desktop preferences configured (${color_scheme}, ${scaling}x)"
}

apply_etosaddons_overlay() {
    log "INFO" "Applying et-os-addons overlay files (if available)..."
    
    local addons_dir="${CACHE_DIR}/et-os-addons-main"
    local addons_overlay="${addons_dir}/overlay"
    
    if [ ! -d "$addons_overlay" ]; then
        log "DEBUG" "et-os-addons overlay not found - skipping"
        return 0
    fi
    
    # Copy opt/emcomm-tools addons to squashfs
    if [ -d "${addons_overlay}/opt/emcomm-tools" ]; then
        log "DEBUG" "Copying et-os-addons ETC tools..."
        cp -r "${addons_overlay}/opt/emcomm-tools"/* "${SQUASHFS_DIR}/opt/emcomm-tools/" 2>/dev/null || {
            log "WARN" "Failed to copy some ETC addon files"
        }
        # Fix permissions on config templates
        chroot "${SQUASHFS_DIR}" chmod -f 664 /opt/emcomm-tools/conf/template.d/*.conf 2>/dev/null || true
    fi
    
    # Copy skel files (for new user defaults)
    if [ -d "${addons_overlay}/etc/skel" ]; then
        log "DEBUG" "Copying et-os-addons skel files..."
        cp -r "${addons_overlay}/etc/skel"/* "${SQUASHFS_DIR}/etc/skel/" 2>/dev/null || {
            log "WARN" "Failed to copy some skel addon files"
        }
    fi
    
    log "SUCCESS" "et-os-addons overlay applied"
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
    local direwolf_ptt="${DIREWOLF_PTT:-CM108}"
    
    log "DEBUG" "User config: callsign=$callsign, grid=$grid"
    log "DEBUG" "APRS config: ssid=$aprs_ssid, igate=$enable_igate, beacon=$enable_beacon"
    
    if [[ "$callsign" == "N0CALL" ]]; then
        log "WARN" "APRS not configured - callsign is N0CALL"
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
    
    # === 2. Modify ETC's direwolf APRS template ===
    # CRITICAL: ETC's et-direwolf wrapper does sed replacements on EVERY LAUNCH:
    #   sed "s|{{ET_CALLSIGN}}|${CALLSIGN}|g"
    #   sed "s|{{ET_AUDIO_DEVICE}}|${DIREWOLF_AUDIO_DEVICE}|g"
    # 
    # We MUST preserve {{ET_CALLSIGN}} and {{ET_AUDIO_DEVICE}} placeholders!
    # We ADD iGate/beacon settings as hardcoded values (sed won't touch them).
    # This means iGate server, beacon interval, and symbol are set at ISO build time
    # and persist until the next rebuild (not runtime-configurable).
    #
    # Template files:
    #   - direwolf.aprs-digipeater.conf (APRS mode only)
    #   - direwolf.packet-digipeater.conf (Packet/Winlink mode only)
    # Modifying APRS template does NOT affect Packet mode - separate templates!
    
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
        log "DEBUG" "Backed up original template to ${aprs_template}.orig"
    fi
    
    local temp_conf
    temp_conf=$(mktemp)
    
    # Start with original template
    cp "$aprs_template" "$temp_conf"
    
    # Remove any existing IGSERVER/IGLOGIN lines
    sed -i '/^IGSERVER/d' "$temp_conf"
    sed -i '/^IGLOGIN/d' "$temp_conf"
    
    # Add iGate if enabled (insert after PTT line for proper direwolf parsing)
    if [[ "$enable_igate" == "yes" ]]; then
        sed -i "/^PTT RIG 2 localhost:4532/a IGSERVER ${aprs_server}\nIGLOGIN {{ET_CALLSIGN}}-${aprs_ssid} ${aprs_passcode}" "$temp_conf"
        log "DEBUG" "Added iGate to APRS template: server=${aprs_server}, passcode=${aprs_passcode}"
    fi
    
    # Optionally modify PBEACON with custom settings
    if [[ "$enable_beacon" == "yes" ]]; then
        # Build PHG string (power/height/gain)
        local phg_string="power=${beacon_power} height=${beacon_height} gain=${beacon_gain}"
        if [[ -n "$beacon_dir" ]]; then
            phg_string="${phg_string} dir=${beacon_dir}"
        fi
        
        # Parse symbol (e.g., "/r" -> table="/", code="r")
        local symbol_table="${aprs_symbol:0:1}"
        local symbol_code="${aprs_symbol:1:1}"
        
        # Replace existing PBEACON line with custom one
        sed -i "s|^PBEACON .*|PBEACON delay=1 every=${beacon_interval} overlay=S symbol=\"${symbol_table}${symbol_code}\" ${phg_string} comment=\"${aprs_comment}\" via=${beacon_via}|" "$temp_conf"
        log "DEBUG" "Modified PBEACON: interval=${beacon_interval}s, symbol=${aprs_symbol}, phg=${phg_string}"
    fi
    
    # Move modified template into place
    mv "$temp_conf" "$aprs_template"
    chmod 644 "$aprs_template"
    
    log "SUCCESS" "Modified APRS template: ${callsign}-${aprs_ssid} (igate=${enable_igate}, beacon=${enable_beacon})"
    log "DEBUG" "Placeholders {{ET_CALLSIGN}} and {{ET_AUDIO_DEVICE}} preserved for ETC runtime substitution"
}

# Configure radio in chroot (called from within install_etc_in_chroot where mounts are already active)
customize_radio_configs_in_chroot() {
    log "DEBUG" "Configuring Anytone D578UV CAT control in chroot..."
    
    local radios_dir="${SQUASHFS_DIR}/opt/emcomm-tools/conf/radios.d"
    mkdir -p "$radios_dir"
    
    # Anytone D578UV is core - always configure it
    log "DEBUG" "Adding Anytone D578UV (DigiRig Mobile) CAT control..."
    cat > "${radios_dir}/anytone-d578uv.json" <<'EOF'
{
  "id": "anytone-d578uv",
  "vendor": "Anytone",
  "model": "D578UV (DigiRig Mobile)",
  "rigctrl": {
    "id": "301",
    "baud": "9600",
    "ptt": "CM108"
  },
  "notes": [
    "D-Star capable VHF/UHF radio with CAT control",
    "DigiRig Mobile provides USB-to-CAT interface",
    "CM108 PTT via USB audio device",
    "Supports APRS and digital modes (D-Star, DMR, YSF)",
    "Default baud rate: 9600bps"
  ],
  "fieldNotes": [
    "Connect D578UV to DigiRig Mobile 6-pin connector",
    "DigiRig USB connection to computer",
    "Serial device auto-mapped to /dev/et-cat",
    "Audio device enumerates as CM108-compatible",
    "Use et-mode to select digital mode (APRS, D-Star, etc.)",
    "Configure frequency/offset using radio display",
    "PTT control via CM108 USB audio device"
  ]
}
EOF
    
    chmod 644 "${radios_dir}/anytone-d578uv.json"
    
    # Set Anytone as active radio by default (core functionality)
    ln -sf "${radios_dir}/anytone-d578uv.json" "${radios_dir}/active-radio.json"
    log "DEBUG" "Set active radio: anytone-d578uv"
    
    # Create udev rule for /dev/et-cat symlink (predictable CAT device name)
    local udev_dir="${SQUASHFS_DIR}/etc/udev/rules.d"
    mkdir -p "$udev_dir"
    
    log "DEBUG" "Creating udev rule for /dev/et-cat symlink..."
    cat > "${udev_dir}/99-emcomm-tools-cat.rules" <<'EOF'
# EmComm Tools CAT Device Symlink
# Maps DigiRig and other CAT devices to predictable /dev/et-cat symlink

# DigiRig Mobile (CP2102 USB-UART bridge)
SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", SYMLINK+="et-cat"

# Generic CH340 (common in budget CAT cables)
SUBSYSTEM=="tty", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="7523", SYMLINK+="et-cat"

# Prolific PL2303 (common in older CAT cables)
SUBSYSTEM=="tty", ATTRS{idVendor}=="067b", ATTRS{idProduct}=="2303", SYMLINK+="et-cat"

# FTDI FT232 (common in professional CAT cables)
SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", SYMLINK+="et-cat"
EOF
    
    chmod 644 "${udev_dir}/99-emcomm-tools-cat.rules"
    
    # === CRITICAL FIX: Protect Anytone D578UV from being overwritten by rigctld ===
    # ETC's wrapper-rigctld.sh has a do_full_auto() function that destructively 
    # replaces active-radio.json when certain radios (like IC-705) are detected.
    # We patch it to preserve our Anytone D578UV configuration.
    #
    # NOTE: The sed multi-line append syntax is tricky and often fails silently.
    # This implementation uses a reliable approach: create temp file, then concatenate.
    log "DEBUG" "Patching rigctld wrapper to preserve Anytone D578UV..."
    
    local wrapper_script="${SQUASHFS_DIR}/opt/emcomm-tools/sbin/wrapper-rigctld.sh"
    if [ -f "$wrapper_script" ]; then
        # Backup the original
        cp "$wrapper_script" "${wrapper_script}.backup"
        log "DEBUG" "Backed up wrapper-rigctld.sh to ${wrapper_script}.backup"
        
        # Create the preservation code as a separate file
        local patch_code
        patch_code=$(mktemp)
        cat > "$patch_code" << 'ANYTONE_PRESERVE_EOF'
  # CUSTOM FIX: Preserve Anytone D578UV if already configured
  # Added by EmComm Tools Customizer - prevents do_full_auto() from overwriting
  if [ -L "${ET_HOME}/conf/radios.d/active-radio.json" ]; then
    if grep -q '"anytone' "${ET_HOME}/conf/radios.d/active-radio.json" 2>/dev/null; then
      et-log "Anytone D578UV is configured - preserving configuration"
      return 0
    fi
  fi
ANYTONE_PRESERVE_EOF
        
        # Find the line number of do_full_auto() function definition
        local func_line
        func_line=$(grep -n '^do_full_auto()' "$wrapper_script" | head -1 | cut -d: -f1)
        
        if [ -n "$func_line" ]; then
            # Find the next line after the function opening brace (typically line after function def)
            # The function body starts after the opening brace, usually on the line with 'et-log "Found ET_DEVICE'
            local insert_line=$((func_line + 2))
            
            # Create new wrapper script with preservation code inserted
            local new_wrapper
            new_wrapper=$(mktemp)
            
            # Copy lines 1 to insert_line-1
            head -n $((insert_line - 1)) "$wrapper_script" > "$new_wrapper"
            
            # Insert the preservation code
            cat "$patch_code" >> "$new_wrapper"
            
            # Copy remaining lines
            tail -n +$insert_line "$wrapper_script" >> "$new_wrapper"
            
            # Replace original with patched version
            mv "$new_wrapper" "$wrapper_script"
            chmod 755 "$wrapper_script"
            
            # Verify the patch was applied correctly
            if grep -q "Anytone D578UV is configured - preserving configuration" "$wrapper_script"; then
                log "SUCCESS" "wrapper-rigctld.sh successfully patched to preserve Anytone"
                log "DEBUG" "Patch inserted at line $insert_line"
                
                # Show the patched function for verification
                log "DEBUG" "Patched do_full_auto() function (first 15 lines):"
                sed -n "${func_line},$((func_line + 15))p" "$wrapper_script" | while read -r line; do
                    log "DEBUG" "  $line"
                done
            else
                log "ERROR" "Anytone preservation patch FAILED to apply!"
                log "DEBUG" "Restoring original wrapper-rigctld.sh from backup"
                cp "${wrapper_script}.backup" "$wrapper_script"
            fi
            
            rm -f "$patch_code"
        else
            log "WARN" "Could not find do_full_auto() function in wrapper-rigctld.sh"
            log "DEBUG" "Contents of wrapper-rigctld.sh (first 30 lines):"
            head -30 "$wrapper_script" | while read -r line; do
                log "DEBUG" "  $line"
            done
        fi
    else
        log "WARN" "wrapper-rigctld.sh not found at: $wrapper_script"
        log "WARN" "Radio may be overwritten by rigctld auto-configuration on boot"
    fi
    local systemd_dir="${SQUASHFS_DIR}/etc/systemd/system"
    mkdir -p "$systemd_dir"
    
    log "DEBUG" "Creating systemd service for rigctld..."
    cat > "${systemd_dir}/rigctld.service" <<'EOFSERVICE'
[Unit]
Description=HAMlib Rig Control Daemon for EmComm Tools
Documentation=https://www.hamlib.org/
Requires=network.target
After=network.target udev.service

[Service]
Type=simple
User=root
Group=root
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/emcomm-tools/bin:/opt/emcomm-tools/sbin"

# Start wrapper script which handles radio config and rigctld invocation
ExecStart=/opt/emcomm-tools/sbin/wrapper-rigctld.sh start

# Restart on failure
Restart=on-failure
RestartSec=5

# Allow time for radio to be powered on
TimeoutStartSec=10

[Install]
WantedBy=multi-user.target
EOFSERVICE
    
    chmod 644 "${systemd_dir}/rigctld.service"
    
    # Enable rigctld for auto-start at boot
    chroot "${SQUASHFS_DIR}" systemctl enable rigctld.service 2>/dev/null || \
        log "WARN" "Could not enable rigctld in chroot (service will start on first boot)"
    
    log "DEBUG" "Anytone D578UV CAT control configured"
}

# Configure radio AFTER ETC is installed (as customization step)
customize_radio_configs() {
    log "INFO" "Radio configs applied (completed during ETC post-install phase)..."
    # NOTE: Radio configs are now written in-chroot immediately after install.sh
    # This stub function is retained for API compatibility
    return 0
}

# ============================================================================
# Integrate et-os-addons Optional Features
# ============================================================================

integrate_etosaddons_features() {
    log "INFO" "Integrating et-os-addons optional features..."
    
    # shellcheck source=/dev/null
    source "$SECRETS_FILE"
    log "DEBUG" "Sourced secrets file for et-os-addons config"
    
    local addons_overlay="${CACHE_DIR}/et-os-addons-main/overlay"
    
    if [ ! -d "$addons_overlay" ]; then
        log "DEBUG" "et-os-addons overlay not found in cache - skipping optional features"
        return 0
    fi
    
    # === VR-N76 Old Radio Support ===
    local enable_vr_n76="${ENABLE_ETOSADDONS_VR_N76:-yes}"
    if [ "$enable_vr_n76" = "yes" ]; then
        if [ -f "${addons_overlay}/opt/emcomm-tools/bin/et-vr-n76-old" ]; then
            log "DEBUG" "Installing et-vr-n76-old launcher..."
            cp "${addons_overlay}/opt/emcomm-tools/bin/et-vr-n76-old" \
                "${SQUASHFS_DIR}/opt/emcomm-tools/bin/" 2>/dev/null && \
                chmod 755 "${SQUASHFS_DIR}/opt/emcomm-tools/bin/et-vr-n76-old" || \
                log "WARN" "Failed to copy et-vr-n76-old"
        fi
    fi
    
    # === QSSTV Optional Feature ===
    local enable_qsstv="${ENABLE_ETOSADDONS_QSSTV:-yes}"
    if [ "$enable_qsstv" = "yes" ]; then
        if [ -f "${addons_overlay}/opt/emcomm-tools/bin/et-qsstv" ]; then
            log "DEBUG" "Installing et-qsstv launcher..."
            cp "${addons_overlay}/opt/emcomm-tools/bin/et-qsstv" \
                "${SQUASHFS_DIR}/opt/emcomm-tools/bin/" 2>/dev/null && \
                chmod 755 "${SQUASHFS_DIR}/opt/emcomm-tools/bin/et-qsstv" || \
                log "WARN" "Failed to copy et-qsstv"
        fi
        if [ -f "${addons_overlay}/opt/emcomm-tools/conf/template.d/qsstv_9.0.conf" ]; then
            log "DEBUG" "Installing QSSTV config template..."
            cp "${addons_overlay}/opt/emcomm-tools/conf/template.d/qsstv_9.0.conf" \
                "${SQUASHFS_DIR}/opt/emcomm-tools/conf/template.d/" 2>/dev/null || \
                log "WARN" "Failed to copy QSSTV template"
        fi
    fi
    
    # === WSJT-X Optional Feature ===
    local enable_wsjtx="${ENABLE_ETOSADDONS_WSJTX:-yes}"
    if [ "$enable_wsjtx" = "yes" ]; then
        if [ -f "${addons_overlay}/opt/emcomm-tools/bin/et-wsjtx" ]; then
            log "DEBUG" "Installing et-wsjtx launcher..."
            cp "${addons_overlay}/opt/emcomm-tools/bin/et-wsjtx" \
                "${SQUASHFS_DIR}/opt/emcomm-tools/bin/" 2>/dev/null && \
                chmod 755 "${SQUASHFS_DIR}/opt/emcomm-tools/bin/et-wsjtx" || \
                log "WARN" "Failed to copy et-wsjtx"
        fi
        if [ -f "${addons_overlay}/opt/emcomm-tools/conf/template.d/WSJT-X.conf" ]; then
            log "DEBUG" "Installing WSJT-X config template..."
            cp "${addons_overlay}/opt/emcomm-tools/conf/template.d/WSJT-X.conf" \
                "${SQUASHFS_DIR}/opt/emcomm-tools/conf/template.d/" 2>/dev/null || \
                log "WARN" "Failed to copy WSJT-X template"
        fi
    fi
    
    # === JS8 Spotter Optional Feature ===
    local enable_js8spotter="${ENABLE_ETOSADDONS_JS8SPOTTER:-yes}"
    if [ "$enable_js8spotter" = "yes" ]; then
        if [ -f "${addons_overlay}/opt/emcomm-tools/bin/et-js8spotter" ]; then
            log "DEBUG" "Installing et-js8spotter launcher..."
            cp "${addons_overlay}/opt/emcomm-tools/bin/et-js8spotter" \
                "${SQUASHFS_DIR}/opt/emcomm-tools/bin/" 2>/dev/null && \
                chmod 755 "${SQUASHFS_DIR}/opt/emcomm-tools/bin/et-js8spotter" || \
                log "WARN" "Failed to copy et-js8spotter"
        fi
        if [ -f "${addons_overlay}/usr/share/applications/js8spotter.desktop" ]; then
            log "DEBUG" "Installing JS8Spotter desktop file..."
            mkdir -p "${SQUASHFS_DIR}/usr/share/applications"
            cp "${addons_overlay}/usr/share/applications/js8spotter.desktop" \
                "${SQUASHFS_DIR}/usr/share/applications/" 2>/dev/null || \
                log "WARN" "Failed to copy JS8Spotter desktop file"
        fi
    fi
    
    # === Network Control Optional Feature ===
    local enable_netcontrol="${ENABLE_ETOSADDONS_NETCONTROL:-yes}"
    if [ "$enable_netcontrol" = "yes" ]; then
        if [ -f "${addons_overlay}/opt/emcomm-tools/bin/et-netcontrol" ]; then
            log "DEBUG" "Installing et-netcontrol launcher..."
            cp "${addons_overlay}/opt/emcomm-tools/bin/et-netcontrol" \
                "${SQUASHFS_DIR}/opt/emcomm-tools/bin/" 2>/dev/null && \
                chmod 755 "${SQUASHFS_DIR}/opt/emcomm-tools/bin/et-netcontrol" || \
                log "WARN" "Failed to copy et-netcontrol"
        fi
        if [ -f "${addons_overlay}/usr/share/applications/netcontrol.desktop" ]; then
            log "DEBUG" "Installing NetControl desktop file..."
            mkdir -p "${SQUASHFS_DIR}/usr/share/applications"
            cp "${addons_overlay}/usr/share/applications/netcontrol.desktop" \
                "${SQUASHFS_DIR}/usr/share/applications/" 2>/dev/null || \
                log "WARN" "Failed to copy NetControl desktop file"
        fi
        if [ -f "${addons_overlay}/usr/share/pixmaps/netcontrol.png" ]; then
            log "DEBUG" "Installing NetControl icon..."
            mkdir -p "${SQUASHFS_DIR}/usr/share/pixmaps"
            cp "${addons_overlay}/usr/share/pixmaps/netcontrol.png" \
                "${SQUASHFS_DIR}/usr/share/pixmaps/" 2>/dev/null || \
                log "WARN" "Failed to copy NetControl icon"
        fi
    fi
    
    # === WiFi Hotspot Optional Feature ===
    local enable_hotspot="${ENABLE_ETOSADDONS_HOTSPOT:-yes}"
    if [ "$enable_hotspot" = "yes" ]; then
        if [ -f "${addons_overlay}/opt/emcomm-tools/bin/et-hotspot" ]; then
            log "DEBUG" "Installing et-hotspot launcher..."
            cp "${addons_overlay}/opt/emcomm-tools/bin/et-hotspot" \
                "${SQUASHFS_DIR}/opt/emcomm-tools/bin/" 2>/dev/null && \
                chmod 755 "${SQUASHFS_DIR}/opt/emcomm-tools/bin/et-hotspot" || \
                log "WARN" "Failed to copy et-hotspot"
        fi
    fi
    
    # === User Backup Manager Optional Feature ===
    local enable_userbackup="${ENABLE_ETOSADDONS_USERBACKUP:-yes}"
    if [ "$enable_userbackup" = "yes" ]; then
        if [ -f "${addons_overlay}/opt/emcomm-tools/bin/et-user-backup" ]; then
            log "DEBUG" "Installing et-user-backup utility..."
            cp "${addons_overlay}/opt/emcomm-tools/bin/et-user-backup" \
                "${SQUASHFS_DIR}/opt/emcomm-tools/bin/" 2>/dev/null && \
                chmod 755 "${SQUASHFS_DIR}/opt/emcomm-tools/bin/et-user-backup" || \
                log "WARN" "Failed to copy et-user-backup"
        fi
    fi
    
    # === Kiwix Offline Content Browser ===
    local enable_kiwix="${ENABLE_ETOSADDONS_KIWIX:-yes}"
    if [ "$enable_kiwix" = "yes" ]; then
        if [ -f "${addons_overlay}/usr/share/applications/kiwix.desktop" ]; then
            log "DEBUG" "Installing Kiwix desktop file..."
            mkdir -p "${SQUASHFS_DIR}/usr/share/applications"
            cp "${addons_overlay}/usr/share/applications/kiwix.desktop" \
                "${SQUASHFS_DIR}/usr/share/applications/" 2>/dev/null || \
                log "WARN" "Failed to copy Kiwix desktop file"
        fi
        if [ -f "${addons_overlay}/usr/share/pixmaps/kiwix-desktop.svg" ]; then
            log "DEBUG" "Installing Kiwix icon..."
            mkdir -p "${SQUASHFS_DIR}/usr/share/pixmaps"
            cp "${addons_overlay}/usr/share/pixmaps/kiwix-desktop.svg" \
                "${SQUASHFS_DIR}/usr/share/pixmaps/" 2>/dev/null || \
                log "WARN" "Failed to copy Kiwix icon"
        fi
    fi
    
    # === VGC VR-N76 Radio Config ===
    # Always include this radio option (no ENABLE variable needed)
    if [ -f "${addons_overlay}/opt/emcomm-tools/conf/radios.d/vgc-vrn76.bt.json" ]; then
        log "DEBUG" "Installing VGC VR-N76 radio config..."
        local radios_dir="${SQUASHFS_DIR}/opt/emcomm-tools/conf/radios.d"
        mkdir -p "$radios_dir"
        cp "${addons_overlay}/opt/emcomm-tools/conf/radios.d/vgc-vrn76.bt.json" \
            "${SQUASHFS_DIR}/opt/emcomm-tools/conf/radios.d/" 2>/dev/null || \
            log "WARN" "Failed to copy VGC VR-N76 radio config"
    fi
    
    log "SUCCESS" "et-os-addons features integrated"
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
    
    # Set user password by pre-hashing and writing directly
    # We avoid chroot because it requires bind mounts that can hang
    if [ -n "$password" ]; then
        log "INFO" "Setting up password for user..."
        
        # Hash the password using openssl (works without chroot)
        local hashed_password
        hashed_password=$(openssl passwd -6 "$password")
        
        if [ -n "$hashed_password" ]; then
            # Create a first-boot script that sets the password
            local firstboot_dir="${SQUASHFS_DIR}/etc/profile.d"
            local firstboot_script="${firstboot_dir}/z99-set-user-password.sh"
            
            mkdir -p "$firstboot_dir"
            
            cat > "$firstboot_script" << PWEOF
#!/bin/bash
# One-time password setup - self-deleting script
if [ "\$(id -u)" = "0" ] && [ -f "/etc/shadow" ]; then
    # Update password hash for user
    if grep -q "^${username}:" /etc/shadow 2>/dev/null; then
        sed -i "s|^${username}:[^:]*:|${username}:${hashed_password}:|" /etc/shadow
    fi
    # Self-delete
    rm -f "\$0"
fi
PWEOF
            chmod 755 "$firstboot_script"
            log "DEBUG" "Created first-boot password script"
            
            # Also try to directly modify shadow if the user exists
            local shadow_file="${SQUASHFS_DIR}/etc/shadow"
            if [ -f "$shadow_file" ] && grep -q "^${username}:" "$shadow_file" 2>/dev/null; then
                sed -i "s|^${username}:[^:]*:|${username}:${hashed_password}:|" "$shadow_file"
                log "SUCCESS" "Password hash set directly in shadow file"
                # Remove the first-boot script since we did it directly
                rm -f "$firstboot_script"
            else
                log "INFO" "User not in shadow yet - password will be set on first boot"
            fi
        else
            log "WARN" "Failed to hash password"
        fi
    else
        log "INFO" "No password configured - user will use ETC default or must set on first boot"
    fi
    
    # Pre-populate ETC's user.json with secrets (callsign, grid, Winlink password)
    # This ensures personalized config even if backup restoration is deferred
    log "INFO" "Pre-populating ETC user configuration..."
    local grid="${GRID_SQUARE:-DM33}"
    local winlink_passwd="${WINLINK_PASSWORD:-NOPASS}"
    
    local etc_config_dir="${SQUASHFS_DIR}/etc/skel/.config/emcomm-tools"
    mkdir -p "$etc_config_dir"
    
    local user_json="${etc_config_dir}/user.json"
    cat > "$user_json" <<EOF
{
  "callsign": "${callsign}",
  "grid": "${grid}",
  "winlinkPasswd": "${winlink_passwd}"
}
EOF
    chmod 644 "$user_json"
    log "DEBUG" "Pre-populated user.json: callsign=$callsign, grid=$grid"
    
    log "SUCCESS" "User account configuration complete"
}

# ============================================================================
# Partition Detection and Strategy
# ============================================================================

detect_partition_strategy() {
    # Analyze current disk layout and determine optimal partition strategy
    # Returns: partition_strategy, target_disk, ext4_size, swap_size
    # NOTE: log function redirects console output to stderr, keeping stdout clean for pipe-delimited output
    
    # Strategy values: auto-detect, use-entire-disk, use-partition, use-free-space
    local target_device="${1:-}"
    local force_strategy="${2:-}"  # Optional: force-entire-disk, force-partition, force-free-space
    
    log "INFO" "Analyzing partition strategy..."
    
    # If user explicitly configured INSTALL_DISK and it's a specific partition, use it as-is
    if [[ -n "$target_device" && "$target_device" =~ [0-9]$ ]]; then
        # Partition mode: target is a specific partition like /dev/sda5
        log "INFO" "Target is specific partition: $target_device (partition mode)"
        
        # Check if partition exists and get its size
        if [ -b "$target_device" ] 2>/dev/null; then
            local part_size_sectors
            part_size_sectors=$(blockdev --getsz "$target_device" 2>/dev/null || echo "0")
            local part_size_gb=$((part_size_sectors / 2097152))  # Convert 512-byte sectors to GB
            
            log "INFO" "Partition size: ~${part_size_gb}GB"
            echo "use-partition|$target_device|${part_size_gb}GB|calculated"
            return 0
        else
            log "WARN" "Target partition $target_device does not exist - will auto-detect"
        fi
    fi
    
    # If we reach here, either no specific partition was set, or it doesn't exist
    # Try to detect current disk layout for analysis
    
    log "INFO" "Running partition auto-detection..."
    
    # Count partitions on potential target disk
    local target_disk
    if [[ -n "$target_device" && "$target_device" =~ ^/dev/[a-z] ]]; then
        target_disk="$target_device"
    else
        # Find first non-removable disk
        target_disk=$(lsblk -d -n -o NAME,TYPE | grep "disk" | head -1 | awk '{print $1}')
        target_disk="/dev/$target_disk"
    fi
    
    if [ -z "$target_disk" ] || [ ! -b "$target_disk" ]; then
        log "WARN" "Could not determine target disk - defaulting to partition mode"
        echo "unknown|unknown|unknown|unknown"
        return 1
    fi
    
    log "DEBUG" "Target disk for analysis: $target_disk"
    
    # Analyze partition table
    local partition_count
    partition_count=$(parted -l "$target_disk" 2>/dev/null | grep -c "^ " || echo "0")
    
    local has_windows=0
    local has_linux=0
    local total_disk_gb=0
    local free_space_gb=0
    
    # Check for Windows/Linux partitions
    if parted -l "$target_disk" 2>/dev/null | grep -qi "ntfs\|fat32\|microsoft"; then
        has_windows=1
        log "INFO" "Detected Windows partition on $target_disk"
    fi
    
    if parted -l "$target_disk" 2>/dev/null | grep -qi "ext4\|ext3\|btrfs"; then
        has_linux=1
        log "INFO" "Detected Linux partition on $target_disk"
    fi
    
    # Get disk size
    if command -v blockdev &>/dev/null; then
        local disk_size_sectors
        disk_size_sectors=$(blockdev --getsz "$target_disk" 2>/dev/null || echo "0")
        total_disk_gb=$((disk_size_sectors / 2097152))  # Convert to GB
        log "DEBUG" "Total disk size: ~${total_disk_gb}GB"
    fi
    
    # Decision logic
    if [ $partition_count -eq 0 ]; then
        log "INFO" "No partitions found - entire disk available (~${total_disk_gb}GB)"
        echo "entire-disk|$target_disk|${total_disk_gb}GB|calculated"
    elif [ $has_windows -eq 1 ] && [ $has_linux -eq 0 ]; then
        log "INFO" "Windows partition(s) detected, no Linux partitions"
        # Check for free space (simplified: assume we can use parted free space)
        if parted -l "$target_disk" 2>/dev/null | grep -q "Free Space"; then
            log "INFO" "Free space available after Windows partition"
            echo "free-space|$target_disk|${total_disk_gb}GB|calculated"
        else
            log "INFO" "No free space - will need to repartition entire disk"
            echo "entire-disk|$target_disk|${total_disk_gb}GB|calculated"
        fi
    elif [ $has_linux -eq 1 ] || [ $partition_count -le 2 ]; then
        log "INFO" "Linux partition(s) or simple partition table detected"
        echo "partition|$target_disk|${total_disk_gb}GB|calculated"
    else
        log "INFO" "Complex partition table detected - defaulting to safe partition mode"
        echo "partition|$target_disk|${total_disk_gb}GB|calculated"
    fi
}

calculate_swap_size() {
    # Calculate ideal swap based on available RAM
    # Input: total_size_gb (space available for ext4+swap)
    # Output: swap_size_gb
    
    local available_gb="${1:-0}"
    local override_mb="${2:-}"  # Optional override from SWAP_SIZE_MB
    
    if [ -n "$override_mb" ] && [ "$override_mb" -gt 0 ]; then
        # User override
        local override_gb=$((override_mb / 1024))
        log "INFO" "Using user-configured swap size: ${override_gb}GB"
        echo "$override_gb"
        return 0
    fi
    
    # Auto-calculate based on available space and best practices
    # Conservative approach: use 2-4GB for modern systems, or 25% of available, whichever is less
    
    local swap_gb=$((available_gb / 4))  # 25% of available space
    
    if [ $swap_gb -lt 2 ]; then
        swap_gb=2
    elif [ $swap_gb -gt 4 ]; then
        swap_gb=4
    fi
    
    log "INFO" "Calculated swap size: ${swap_gb}GB (from ${available_gb}GB available)"
    echo "$swap_gb"
}

customize_preseed() {
    log "INFO" "Generating preseed file for automated Ubuntu installer..."
    
    # Enable error tracing for this function
    local preseed_debug=1
    
    if [ $preseed_debug -eq 1 ]; then
        log "DEBUG" "[PRESEED] Starting preseed customization"
        log "DEBUG" "[PRESEED] ISO_EXTRACT_DIR=$ISO_EXTRACT_DIR"
    fi
    
    # shellcheck source=/dev/null
    if ! source "$SECRETS_FILE"; then
        log "ERROR" "[PRESEED] Failed to source secrets file: $SECRETS_FILE"
        return 1
    fi
    log "DEBUG" "Sourced secrets file for preseed config"
    
    local callsign="${CALLSIGN:-N0CALL}"
    local machine_name="${MACHINE_NAME:-ETC-${callsign}}"
    local fullname="${USER_FULLNAME:-EmComm User}"
    local username="${USER_USERNAME:-${callsign,,}}"
    local password="${USER_PASSWORD:-}"
    local timezone="${TIMEZONE:-America/Denver}"
    local keyboard_layout="${KEYBOARD_LAYOUT:-us}"
    local locale="${LOCALE:-en_US.UTF-8}"
    
    # Partition strategy variables (new)
    local partition_strategy="${PARTITION_STRATEGY:-auto-detect}"
    local install_disk="${INSTALL_DISK:-}"           # May be empty for auto-detect
    local swap_size_mb="${SWAP_SIZE_MB:-}"
    local ext4_size_mb="${EXT4_SIZE_MB:-}"
    local confirm_entire_disk="${CONFIRM_ENTIRE_DISK:-no}"
    
    log "DEBUG" "Partition strategy: $partition_strategy"
    
    # Detect partition strategy based on current disk layout
    local strategy_result strategy_mode target_disk target_size target_calc
    local calculated_swap_gb calculated_ext4_gb
    
    if [[ "$partition_strategy" == "auto-detect" ]]; then
        log "INFO" "Running auto-detect partition strategy..."
        strategy_result=$(detect_partition_strategy "$install_disk" 2>/dev/null || echo "unknown|unknown|unknown|unknown")
        IFS='|' read -r strategy_mode target_disk target_size target_calc <<< "$strategy_result"
        log "INFO" "Auto-detect result: mode=$strategy_mode, disk=$target_disk, size=$target_size"
        
        # Calculate swap size based on detected partition size if in auto mode
        if [[ "$target_size" != "auto" ]] && [[ -n "$swap_size_mb" ]] && [ "$swap_size_mb" -gt 0 ]; then
            calculated_swap_gb=$((swap_size_mb / 1024))
            log "INFO" "Using user-configured swap: ${calculated_swap_gb}GB (${swap_size_mb}MB)"
        elif [[ "$target_size" != "auto" ]] && [[ "$target_size" =~ ^([0-9]+)GB ]]; then
            # Extract numeric GB from target_size (e.g., "50GB" -> 50)
            local available_gb="${BASH_REMATCH[1]}"
            calculated_swap_gb=$(calculate_swap_size "$available_gb" "$swap_size_mb")
            log "INFO" "Calculated swap size: ${calculated_swap_gb}GB from available ${available_gb}GB"
        fi
    else
        strategy_mode="$partition_strategy"
        target_disk="$install_disk"
        log "INFO" "Using explicit partition strategy: $strategy_mode"
        
        # Calculate swap for explicit strategy if user provided overrides
        if [ -n "$swap_size_mb" ] && [ "$swap_size_mb" -gt 0 ]; then
            calculated_swap_gb=$((swap_size_mb / 1024))
            log "INFO" "Using user-configured swap: ${calculated_swap_gb}GB (${swap_size_mb}MB)"
        fi
    fi
    
    # Map strategy names to actions
    case "$strategy_mode" in
        use-partition|partition|force-partition)
            log "INFO" "Using partition mode (safe for dual-boot)"
            strategy_mode="partition"
            ;;
        use-entire-disk|entire-disk|force-entire-disk)
            log "WARN" "Using entire-disk mode (DESTRUCTIVE)"
            if [[ "$confirm_entire_disk" != "yes" ]]; then
                log "ERROR" "Entire-disk mode requires CONFIRM_ENTIRE_DISK=\"yes\" in secrets.env"
                log "ERROR" "This will ERASE all partitions. Please review carefully and confirm."
                return 1
            fi
            strategy_mode="entire-disk"
            ;;
        use-free-space|free-space|force-free-space)
            log "INFO" "Using free-space mode (create partitions in available space)"
            strategy_mode="free-space"
            ;;
        *)
            log "WARN" "Unknown strategy: $strategy_mode - defaulting to partition mode"
            strategy_mode="partition"
            ;;
    esac
    
    log "DEBUG" "Preseed config: hostname='$machine_name', username='$username', timezone='$timezone'"
    log "DEBUG" "Partition strategy: $strategy_mode, target_disk='$target_disk', target_size='${target_size:-auto}'"
    if [ -n "$calculated_swap_gb" ]; then
        log "DEBUG" "Swap calculation: ${calculated_swap_gb}GB"
    fi
    if [ -n "$ext4_size_mb" ] && [ "$ext4_size_mb" -gt 0 ]; then
        calculated_ext4_gb=$((ext4_size_mb / 1024))
        log "DEBUG" "Ext4 size override: ${calculated_ext4_gb}GB (${ext4_size_mb}MB)"
    fi
    
    # Create preseed directory in ISO ROOT (not in squashfs)
    # The preseed file must be accessible from GRUB bootloader BEFORE squashfs is mounted
    # Location: /preseed.cfg on the ISO, accessed via preseed/file=/cdrom/preseed.cfg
    local preseed_dir="${ISO_EXTRACT_DIR}"
    log "DEBUG" "Creating preseed file in ISO root: $preseed_dir"
    
    if [ -z "$ISO_EXTRACT_DIR" ]; then
        log "ERROR" "[PRESEED] ISO_EXTRACT_DIR is not set!"
        return 1
    fi
    
    # Generate preseed file with strategy-based partitioning
    local preseed_file="${preseed_dir}/preseed.cfg"
    log "DEBUG" "Generating preseed file: $preseed_file"
    log "DEBUG" "[PRESEED] About to create preseed with cat heredoc"
    
    # Hash password for preseed (format: SHA512 hash prefixed with $6$)
    local hashed_password=""
    if [ -n "$password" ]; then
        log "DEBUG" "[PRESEED] Hashing password with openssl..."
        if ! hashed_password=$(openssl passwd -6 "$password" 2>&1); then
            log "ERROR" "[PRESEED] Password hashing failed: $hashed_password"
            return 1
        fi
        log "DEBUG" "[PRESEED] Password hash generated successfully"
    else
        log "WARN" "[PRESEED] No password configured - preseed will skip password setup"
    fi
    
    # Create preseed file for Ubiquity (Ubuntu Desktop installer)
    # CRITICAL: Ubuntu Desktop uses Ubiquity, NOT debian-installer (d-i)!
    # Reference: https://wiki.ubuntu.com/UbiquityAutomation
    #
    # Ubiquity IGNORES these d-i directives:
    #   - netcfg (network configuration)
    #   - LVM and RAID partitioning
    #   - base-installer
    #   - pkgsel/tasksel
    #   - finish-install
    #
    # Ubiquity HONORS these d-i directives:
    #   - keyboard-configuration
    #   - passwd (user account setup)
    #   - time/zone
    #   - localechooser/languagechooser/countrychooser
    #
    # Ubiquity-specific keys use "ubiquity/" prefix
    
    log "DEBUG" "[PRESEED] Creating Ubiquity-compatible preseed file..."
    cat > "$preseed_file" <<'EOF'
# Ubiquity Preseed File for Automated Ubuntu Desktop Installation
# Generated by EmComm Tools Customizer
# Reference: https://wiki.ubuntu.com/UbiquityAutomation
#
# IMPORTANT: This preseed is for Ubiquity (Ubuntu Desktop graphical installer).
# Boot with "automatic-ubiquity only-ubiquity noprompt" parameters to enable automation.
# In automatic mode, Ubiquity respects the 'seen' flag for preseeded values.

### Ubiquity-specific settings
# Skip the summary/confirmation page before installation begins
ubiquity ubiquity/summary boolean true

# Automatically reboot when installation completes
ubiquity ubiquity/reboot boolean true

# Power off instead of reboot (set to false for reboot)
ubiquity ubiquity/poweroff boolean false

# Command to run on successful installation (runs outside /target, but /target is mounted)
ubiquity ubiquity/success_command string \
    sed -i 's/DISTRIB_DESCRIPTION=.*/DISTRIB_DESCRIPTION="RELEASE_DESCRIPTION_VAR"/' /target/etc/lsb-release || true

### Language and Locale (Ubiquity honors these)
# Language selection
languagechooser languagechooser/language-name select English

# Country/territory selection
countrychooser countrychooser/shortlist select US

# Additional locales to support
localechooser localechooser/supported-locales multiselect LOCALE_VAR

# Console keyboard layout
console-setup console-setup/ask_detect boolean false
console-setup console-setup/layoutcode string KEYBOARD_LAYOUT_VAR

# Keyboard configuration (Ubiquity honors this)
d-i keyboard-configuration/layoutcode string KEYBOARD_LAYOUT_VAR
d-i keyboard-configuration/xkb-keymap select KEYBOARD_LAYOUT_VAR
keyboard-configuration keyboard-configuration/layoutcode string KEYBOARD_LAYOUT_VAR
keyboard-configuration keyboard-configuration/xkb-keymap select KEYBOARD_LAYOUT_VAR

### Timezone (Ubiquity honors this)
d-i time/zone string TIMEZONE_VAR
d-i clock-setup/utc boolean true

### User Account Setup (Ubiquity honors these)
# Disable root login - use sudo instead
d-i passwd/root-login boolean false

# Create user account
d-i passwd/user-fullname string FULLNAME_VAR
d-i passwd/username string USERNAME_VAR
d-i passwd/user-password-crypted password PASSWORD_HASH_VAR
d-i user-setup/allow-password-weak boolean true
d-i user-setup/encrypt-home boolean false

# Also set via passwd/* for compatibility
passwd passwd/user-fullname string FULLNAME_VAR
passwd passwd/username string USERNAME_VAR
passwd passwd/user-password-crypted password PASSWORD_HASH_VAR
passwd passwd/user-default-groups string adm cdrom dip lpadmin plugdev sambashare sudo

### Partitioning - NOTE: Ubiquity has LIMITED preseed support for partitioning
# Ubiquity ignores LVM/RAID partitioning preseeds!
# For automated partitioning, Ubiquity uses its own simpler method.
# The user will still see the partitioning screen unless we use a specific recipe.
#
# These are provided for reference but may not fully automate partitioning:
PARTMAN_MODE_PLACEHOLDER

### Bootloader (limited support in Ubiquity)
d-i grub-installer/only_debian boolean true
d-i grub-installer/with_other_os boolean true
d-i grub-installer/bootdev string INSTALL_DISK_VAR

### Popularity contest
popularity-contest popularity-contest/participate boolean false
EOF
    
    if [ $? -ne 0 ]; then
        log "ERROR" "[PRESEED] Failed to create preseed file with cat heredoc (exit code: $?)"
        return 1
    fi
    log "DEBUG" "[PRESEED] Preseed file created with cat heredoc"
    
    # Verify preseed file was actually created
    if [ ! -f "$preseed_file" ]; then
        log "ERROR" "[PRESEED] Preseed file not found after creation: $preseed_file"
        return 1
    fi
    log "DEBUG" "[PRESEED] Preseed file verified at: $preseed_file"

    # Substitute variables into preseed file
    log "DEBUG" "[PRESEED] Starting variable substitution in preseed..."
    
    if ! sed -i "s|KEYBOARD_LAYOUT_VAR|$keyboard_layout|g" "$preseed_file"; then
        log "ERROR" "[PRESEED] sed failed on KEYBOARD_LAYOUT_VAR"
        return 1
    fi
    sed -i "s|LOCALE_VAR|$locale|g" "$preseed_file"
    sed -i "s|TIMEZONE_VAR|$timezone|g" "$preseed_file"
    sed -i "s|HOSTNAME_VAR|$machine_name|g" "$preseed_file"
    sed -i "s|FULLNAME_VAR|$fullname|g" "$preseed_file"
    sed -i "s|USERNAME_VAR|$username|g" "$preseed_file"
    sed -i "s|PASSWORD_HASH_VAR|$hashed_password|g" "$preseed_file"
    sed -i "s|INSTALL_DISK_VAR|${target_disk:-/dev/sda}|g" "$preseed_file"
    
    # Build release description for late_command (same format as update_release_info)
    local release_type=""
    if [[ "$RELEASE_TAG" =~ -final ]]; then
        release_type="FINAL"
    elif [[ "$RELEASE_TAG" =~ build[0-9]+ ]]; then
        release_type="$BUILD_NUMBER"
    else
        release_type="DEV"
    fi
    local release_number_upper="${RELEASE_NUMBER^^}"
    local release_description="ETC_${release_number_upper}_${release_type} (CUSTOMIZED)"
    sed -i "s|RELEASE_DESCRIPTION_VAR|$release_description|g" "$preseed_file"
    log "DEBUG" "[PRESEED] Release description for late_command: $release_description"
    
    log "DEBUG" "[PRESEED] Variable substitution completed"
    
    # Generate partitioning preseed based on detected strategy
    log "DEBUG" "[PRESEED] Creating partman configuration temp file..."
    local partman_config_file
    if ! partman_config_file=$(mktemp); then
        log "ERROR" "[PRESEED] Failed to create temp file for partman config"
        return 1
    fi
    log "DEBUG" "[PRESEED] Temp file created: $partman_config_file"
    
    case "$strategy_mode" in
        partition)
            log "INFO" "Configuring preseed for partition mode (existing partition, safe for dual-boot)"
            log "WARN" "NOTE: Ubiquity has LIMITED partitioning preseed support - user may still see partition screen"
            cat > "$partman_config_file" << 'PARTMAN_CONFIG'
# Partition mode: Use existing partition
# NOTE: Ubiquity ignores most partman preseeds - these are best-effort
# The user may still need to confirm partitioning manually
d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic
d-i partman/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true
PARTMAN_CONFIG
            ;;
        entire-disk)
            log "INFO" "Configuring preseed for entire-disk mode (DESTRUCTIVE - will format entire disk)"
            log "WARN" "NOTE: Ubiquity has LIMITED partitioning preseed support - user may still see partition screen"
            cat > "$partman_config_file" << 'PARTMAN_CONFIG'
# Entire-disk mode: Format entire disk
# NOTE: Ubiquity IGNORES LVM preseed directives!
# These are best-effort settings
d-i partman-auto/disk string INSTALL_DISK_VAR
d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic
d-i partman/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true
PARTMAN_CONFIG
            ;;
        free-space)
            log "INFO" "Configuring preseed for free-space mode (create partitions in available space)"
            log "WARN" "NOTE: Ubiquity has LIMITED partitioning preseed support - user may still see partition screen"
            cat > "$partman_config_file" << 'PARTMAN_CONFIG'
# Free-space mode: Create partitions in available space
# NOTE: Ubiquity ignores most partman preseeds - these are best-effort
d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic
d-i partman/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true
PARTMAN_CONFIG
            ;;
        *)
            log "WARN" "Unknown partition strategy: $strategy_mode - using safe partition mode"
            cat > "$partman_config_file" << 'PARTMAN_CONFIG'
# Default partition mode (best-effort for Ubiquity)
d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic
d-i partman/confirm_write_new_label boolean true
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true
PARTMAN_CONFIG
            ;;
    esac
    
    # Replace partitioning placeholder with strategy-specific config
    log "DEBUG" "[PRESEED] Inserting partman config into preseed file..."
    if ! sed -i '/PARTMAN_MODE_PLACEHOLDER/r '"$partman_config_file" "$preseed_file"; then
        log "ERROR" "[PRESEED] Failed to insert partman config with sed"
        rm -f "$partman_config_file"
        return 1
    fi
    
    if ! sed -i '/PARTMAN_MODE_PLACEHOLDER/d' "$preseed_file"; then
        log "ERROR" "[PRESEED] Failed to delete placeholder with sed"
        rm -f "$partman_config_file"
        return 1
    fi
    log "DEBUG" "[PRESEED] Partman config insertion completed"
    
    rm -f "$partman_config_file"
    
    if ! chmod 644 "$preseed_file"; then
        log "ERROR" "[PRESEED] Failed to set permissions on preseed file"
        return 1
    fi
    log "DEBUG" "[PRESEED] Preseed file written successfully"
    
    log "SUCCESS" "Preseed file created at: /preseed.cfg"
    log "INFO" "Partition strategy: $strategy_mode"
    log "DEBUG" "[PRESEED] customize_preseed function completed successfully"
}

update_grub_for_preseed() {
    log "INFO" "Updating GRUB boot parameters for automated installation..."
    
    # GRUB config is in the extracted ISO directory (not in squashfs)
    # Location: .work/iso/boot/grub/grub.cfg
    # Reference: https://wiki.ubuntu.com/UbiquityAutomation
    #
    # CRITICAL: Ubuntu Desktop ISOs use Casper (live boot) + Ubiquity (installer)
    # For AUTOMATED installation, we need these boot parameters:
    #
    #   1. only-ubiquity    = Skip live desktop, boot directly to Ubiquity installer
    #   2. automatic-ubiquity = Enable preseed automation (respect 'seen' flag)
    #   3. noprompt         = Skip "please remove the disc" prompt after install
    #   4. quiet splash     = Normal boot appearance
    #
    # WITHOUT automatic-ubiquity, Ubiquity IGNORES preseed values because it:
    #   "ignores the 'seen' flag...by default" (Ubuntu wiki)
    #
    # Final boot line should look like:
    #   linux /casper/vmlinuz file=/cdrom/preseed.cfg automatic-ubiquity only-ubiquity noprompt quiet splash ---
    #
    # CRITICAL: Must also update loopback.cfg for Ventoy/GRUB loopback boot!
    # The loopback.cfg is used when booting the ISO via Ventoy or grub loopback
    
    local grub_cfg="${ISO_EXTRACT_DIR}/boot/grub/grub.cfg"
    local loopback_cfg="${ISO_EXTRACT_DIR}/boot/grub/loopback.cfg"
    
    # Helper function to apply preseed modifications to a GRUB config file
    apply_preseed_modifications() {
        local cfg_file="$1"
        local cfg_name="$2"
        
        if [ ! -f "$cfg_file" ]; then
            log "WARN" "$cfg_name not found at: $cfg_file"
            return 1
        fi
        
        # CRITICAL: ISO extracted files are READ-ONLY by default!
        # Make writable before attempting sed modifications
        chmod +w "$cfg_file" 2>/dev/null || {
            log "ERROR" "Cannot make $cfg_name writable - sed will silently fail!"
            return 1
        }
        
        log "DEBUG" "Modifying $cfg_name: $cfg_file"
        log "DEBUG" "$cfg_name BEFORE modifications:"
        grep "linux.*vmlinuz" "$cfg_file" 2>/dev/null | head -5 | while read -r line; do
            log "DEBUG" "  $line"
        done
        
        # Step 1: Update preseed path in ALL entries (from ubuntu.seed to preseed.cfg)
        # This catches: file=/cdrom/preseed/ubuntu.seed -> file=/cdrom/preseed.cfg
        sed -i 's|file=/cdrom/preseed/ubuntu\.seed|file=/cdrom/preseed.cfg|g' "$cfg_file"
        
        # Step 2: Replace maybe-ubiquity with automatic-ubiquity only-ubiquity noprompt
        # CRITICAL: Ubuntu wiki states we need these parameters:
        #   - only-ubiquity = Skip live desktop, boot directly to installer
        #   - automatic-ubiquity = Enable preseed automation (respect 'seen' flag)
        #   - noprompt = Skip "please remove the disc" usplash prompt
        # Without automatic-ubiquity, preseed values are IGNORED!
        # Reference: https://wiki.ubuntu.com/UbiquityAutomation
        sed -i 's|maybe-ubiquity|automatic-ubiquity only-ubiquity noprompt|g' "$cfg_file"
        
        # Step 3: Add automation params to entries that have preseed but missing params
        # Pattern: "file=/cdrom/preseed.cfg quiet" -> "file=/cdrom/preseed.cfg automatic-ubiquity only-ubiquity noprompt quiet"
        sed -i 's|file=/cdrom/preseed\.cfg quiet|file=/cdrom/preseed.cfg automatic-ubiquity only-ubiquity noprompt quiet|g' "$cfg_file"
        sed -i 's|file=/cdrom/preseed\.cfg iso-scan|file=/cdrom/preseed.cfg automatic-ubiquity only-ubiquity noprompt iso-scan|g' "$cfg_file"
        
        # Step 4: Handle nomodeset (safe graphics) entry specifically
        sed -i 's|nomodeset file=/cdrom/preseed\.cfg quiet|nomodeset file=/cdrom/preseed.cfg automatic-ubiquity only-ubiquity noprompt quiet|g' "$cfg_file"
        sed -i 's|nomodeset file=/cdrom/preseed\.cfg iso-scan|nomodeset file=/cdrom/preseed.cfg automatic-ubiquity only-ubiquity noprompt iso-scan|g' "$cfg_file"
        
        # Step 5: Update existing only-ubiquity (without automatic-ubiquity) to include all params
        # This handles OEM install entry that already has only-ubiquity
        sed -i 's|preseed\.cfg only-ubiquity|preseed.cfg automatic-ubiquity only-ubiquity noprompt|g' "$cfg_file"
        
        # Step 6: Clean up any duplicate parameters
        sed -i 's|automatic-ubiquity automatic-ubiquity|automatic-ubiquity|g' "$cfg_file"
        sed -i 's|only-ubiquity only-ubiquity|only-ubiquity|g' "$cfg_file"
        sed -i 's|noprompt noprompt|noprompt|g' "$cfg_file"
        
        # Step 7: Add noprompt if it's missing but other params are present
        # Check if line has automatic-ubiquity but missing noprompt
        sed -i 's|automatic-ubiquity only-ubiquity quiet|automatic-ubiquity only-ubiquity noprompt quiet|g' "$cfg_file"
        sed -i 's|automatic-ubiquity only-ubiquity iso-scan|automatic-ubiquity only-ubiquity noprompt iso-scan|g' "$cfg_file"
        
        log "DEBUG" "$cfg_name AFTER modifications:"
        grep "linux.*vmlinuz" "$cfg_file" 2>/dev/null | head -5 | while read -r line; do
            log "DEBUG" "  $line"
        done
        
        # Verify the changes took effect - must have all THREE automation params
        if grep -q "automatic-ubiquity" "$cfg_file" && grep -q "only-ubiquity" "$cfg_file" && grep -q "noprompt" "$cfg_file" && grep -q "file=/cdrom/preseed.cfg" "$cfg_file"; then
            log "SUCCESS" "$cfg_name configured for automatic Ubiquity installation"
            return 0
        else
            log "WARN" "$cfg_name update may have failed - missing automation parameters"
            log "WARN" "  Has automatic-ubiquity: $(grep -c 'automatic-ubiquity' "$cfg_file" 2>/dev/null || echo 0)"
            log "WARN" "  Has only-ubiquity: $(grep -c 'only-ubiquity' "$cfg_file" 2>/dev/null || echo 0)"
            log "WARN" "  Has noprompt: $(grep -c 'noprompt' "$cfg_file" 2>/dev/null || echo 0)"
            log "WARN" "  Has preseed.cfg: $(grep -c 'preseed.cfg' "$cfg_file" 2>/dev/null || echo 0)"
            return 1
        fi
    }
    
    # Update main grub.cfg (used for direct BIOS/EFI boot)
    apply_preseed_modifications "$grub_cfg" "grub.cfg"
    local grub_result=$?
    
    # Update loopback.cfg (used for Ventoy and GRUB loopback boot)
    # This is CRITICAL for users booting via Ventoy USB drives!
    apply_preseed_modifications "$loopback_cfg" "loopback.cfg"
    local loopback_result=$?
    
    if [ $grub_result -eq 0 ] && [ $loopback_result -eq 0 ]; then
        log "SUCCESS" "Both grub.cfg and loopback.cfg configured for preseed"
        log "DEBUG" "Boot parameters: file=/cdrom/preseed.cfg automatic-ubiquity only-ubiquity noprompt"
    elif [ $grub_result -eq 0 ]; then
        log "WARN" "grub.cfg updated but loopback.cfg failed - Ventoy boot may not use preseed"
    else
        log "ERROR" "GRUB configuration failed"
    fi
    
    # Warn user if we detect other OSes in GRUB menu
    if grep -iq "windows\|boot.*windows\|other os" "$grub_cfg" 2>/dev/null; then
        log "WARN" "Detected other OSes in GRUB menu - they should not be affected by preseed changes"
    fi
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
    local power_mode="${POWER_MODE:-balanced}"
    local lid_close_ac="${POWER_LID_CLOSE_AC:-suspend}"
    local lid_close_battery="${POWER_LID_CLOSE_BATTERY:-suspend}"
    local power_button="${POWER_BUTTON_ACTION:-interactive}"
    local idle_ac="${POWER_IDLE_AC:-nothing}"
    local idle_battery="${POWER_IDLE_BATTERY:-suspend}"
    local idle_timeout="${POWER_IDLE_TIMEOUT:-900}"
    local auto_power_saver="${AUTOMATIC_POWER_SAVER:-true}"
    local auto_suspend="${AUTOMATIC_SUSPEND:-true}"
    
    log "DEBUG" "Power settings: mode=$power_mode, lid_ac=$lid_close_ac, lid_battery=$lid_close_battery, button=$power_button"
    log "DEBUG" "Idle settings: ac=$idle_ac, battery=$idle_battery, timeout=$idle_timeout"
    log "DEBUG" "Auto settings: power_saver=$auto_power_saver, suspend=$auto_suspend"
    
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
power-profile-daemon='${power_mode}'
lid-close-ac-action='${lid_close_ac}'
lid-close-battery-action='${lid_close_battery}'
power-button-action='${power_button}'
sleep-inactive-ac-type='${idle_ac}'
sleep-inactive-battery-type='${idle_battery}'
sleep-inactive-ac-timeout=${idle_timeout}
sleep-inactive-battery-timeout=${idle_timeout}

[org/gnome/settings-daemon/plugins/power/battery-saver]
enable-battery-saver=${auto_power_saver}

[org/gnome/desktop/session]
auto-save-session-timeout=${auto_suspend}
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

customize_timezone() {
    log "INFO" "Configuring system timezone..."
    
    # shellcheck source=/dev/null
    source "$SECRETS_FILE"
    log "DEBUG" "Sourced secrets file for timezone config"
    
    local timezone="${TIMEZONE:-America/Denver}"
    log "DEBUG" "Timezone: $timezone"
    
    # Set system timezone using timedatectl in chroot
    log "INFO" "Setting timezone to $timezone"
    
    setup_chroot_mounts
    trap 'cleanup_chroot_mounts' EXIT
    
    # Use chroot to set timezone (timedatectl won't work in chroot, so use ln)
    rm -f "${SQUASHFS_DIR}/etc/localtime"
    ln -s "/usr/share/zoneinfo/${timezone}" "${SQUASHFS_DIR}/etc/localtime" || {
        log "WARN" "Failed to set timezone symlink - timezone may not be configured"
    }
    
    # Also set timezone in /etc/timezone for compatibility
    echo "$timezone" > "${SQUASHFS_DIR}/etc/timezone"
    
    cleanup_chroot_mounts
    trap - EXIT
    
    log "SUCCESS" "Timezone configured: $timezone"
}

customize_additional_packages() {
    log "INFO" "Installing additional system packages..."
    
    # shellcheck source=/dev/null
    source "$SECRETS_FILE"
    log "DEBUG" "Sourced secrets file for package config"
    
    # Core development packages (always installed)
    local core_packages="code nodejs npm"
    
    # Additional packages from secrets.env
    local additional_packages="${ADDITIONAL_PACKAGES:-}"
    
    # Combine core + additional packages
    local all_user_packages="$core_packages"
    if [ -n "$additional_packages" ]; then
        all_user_packages="$all_user_packages $additional_packages"
    fi
    
    log "DEBUG" "Packages to install: $all_user_packages"
    
    # Install packages in chroot
    setup_chroot_mounts
    trap 'cleanup_chroot_mounts' EXIT
    
    # CRITICAL: Fix Ubuntu 22.10 EOL apt sources BEFORE any apt operations
    log "INFO" "Fixing Ubuntu 22.10 (Kinetic) EOL apt sources..."
    chroot "${SQUASHFS_DIR}" sed -i 's/archive.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list
    chroot "${SQUASHFS_DIR}" sed -i 's/security.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list
    
    # Remove problematic Brave repo and conflicting Edge repos
    log "INFO" "Removing Brave browser and conflicting Microsoft Edge repositories..."
    rm -f "${SQUASHFS_DIR}/etc/apt/sources.list.d/brave-browser-release.sources"
    rm -f "${SQUASHFS_DIR}/etc/apt/sources.list.d/brave-browser-release.list"
    rm -f "${SQUASHFS_DIR}/etc/apt/sources.list.d/microsoft-edge-release.sources"
    rm -f "${SQUASHFS_DIR}/etc/apt/sources.list.d/microsoft-edge-dev.list"
    
    # Update apt cache first (before any repos are added)
    log "INFO" "Updating package cache..."
    chroot "${SQUASHFS_DIR}" apt-get update 2>&1 | tail -5 | tee -a "$LOG_FILE"
    
    # Install packages from standard repos (Edge not available in old-releases)
    local all_packages="${all_user_packages}"
    log "INFO" "Installing packages: $all_packages"
    # Use -y to auto-confirm, -qq for less output
    # Note: DO NOT quote $all_packages - we need word splitting for separate package names
    if chroot "${SQUASHFS_DIR}" apt-get install -y -qq $all_packages 2>&1 | tail -10 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "Packages installed successfully"
    else
        log "WARN" "Some packages may have failed to install - see log for details"
    fi
    
    # === CHIRP Installation Setup ===
    # Can't build CHIRP from source in chroot (numpy wheel build fails with old-releases)
    # Install via post-install script that runs on first boot instead
    log "INFO" "Setting up CHIRP installation for first boot..."
    local chirp_install_script="${SQUASHFS_DIR}/usr/local/bin/install-chirp-first-boot.sh"
    mkdir -p "$(dirname "$chirp_install_script")"
    cat > "$chirp_install_script" <<'CHIRP_SCRIPT'
#!/bin/bash
# Install CHIRP on first boot - avoids build issues in chroot
set -e
MARKER="/var/lib/emcomm-chirp-installed"
if [ -f "$MARKER" ]; then
    exit 0
fi
apt-get update > /dev/null 2>&1 || true
apt-get install -y python3-pip > /dev/null 2>&1 || true
python3 -m pip install --upgrade pip setuptools wheel > /dev/null 2>&1 || true
python3 -m pip install chirp > /dev/null 2>&1 && touch "$MARKER" || true
CHIRP_SCRIPT
    chmod +x "$chirp_install_script"
    log "DEBUG" "CHIRP first-boot script created"
    
    # === Microsoft Edge Installation Setup ===
    # Edge repo has GPG issues with old-releases, use post-install instead
    log "INFO" "Setting up Microsoft Edge installation for first boot..."
    local edge_install_script="${SQUASHFS_DIR}/usr/local/bin/install-edge-first-boot.sh"
    mkdir -p "$(dirname "$edge_install_script")"
    cat > "$edge_install_script" <<'EDGE_SCRIPT'
#!/bin/bash
# Install Microsoft Edge on first boot
set -e
MARKER="/var/lib/emcomm-edge-installed"
if [ -f "$MARKER" ]; then
    exit 0
fi
apt-get update > /dev/null 2>&1 || true
# Try to install from Debian packages directly (avoids repo issues)
wget -q https://packages.microsoft.com/repos/edge/pool/main/m/microsoft-edge-stable/microsoft-edge-stable_latest_amd64.deb -O /tmp/edge.deb 2>/dev/null && \
    dpkg -i /tmp/edge.deb > /dev/null 2>&1 && rm -f /tmp/edge.deb && touch "$MARKER" || {
    # Fallback: use apt with repo
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | apt-key add - > /dev/null 2>&1 || true
    echo 'deb [arch=amd64] https://packages.microsoft.com/repos/edge stable main' > /etc/apt/sources.list.d/microsoft-edge.list
    apt-get update > /dev/null 2>&1 || true
    apt-get install -y microsoft-edge-stable > /dev/null 2>&1 && touch "$MARKER" || true
}
EDGE_SCRIPT
    chmod +x "$edge_install_script"
    log "DEBUG" "Edge first-boot script created"
    
    # Create systemd service to run both scripts on first boot
    local first_boot_service="${SQUASHFS_DIR}/etc/systemd/system/emcomm-first-boot-apps.service"
    mkdir -p "$(dirname "$first_boot_service")"
    cat > "$first_boot_service" <<'SERVICE_EOF'
[Unit]
Description=EmComm Tools First Boot Application Installation
After=network-online.target
Wants=network-online.target
ConditionPathExists=!/var/lib/emcomm-first-boot-apps-done

[Service]
Type=oneshot
ExecStart=/bin/bash -c '/usr/local/bin/install-chirp-first-boot.sh && /usr/local/bin/install-edge-first-boot.sh && touch /var/lib/emcomm-first-boot-apps-done'
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE_EOF
    chroot "${SQUASHFS_DIR}" systemctl enable emcomm-first-boot-apps.service 2>/dev/null || log "WARN" "Could not enable systemd service"
    log "DEBUG" "First-boot systemd service created and enabled"
    
    log "SUCCESS" "CHIRP and Microsoft Edge will be installed on first boot"
    
    cleanup_chroot_mounts
    trap - EXIT
}

setup_first_login_packages() {
    log "INFO" "Setting up first-login services (Anytone restoration, CHIRP, Microsoft Edge)..."
    
    # CRITICAL: Anytone radio config MUST be restored via systemd service on first boot
    # (NOT via profile.d because bash profile scripts don't run reliably on GUI logins)
    # Profile.d script alone was unreliable - replaced with systemd service that runs early
    
    local systemd_dir="${SQUASHFS_DIR}/etc/systemd/system"
    local service_file="${systemd_dir}/emcomm-first-boot.service"
    local service_script="${SQUASHFS_DIR}/usr/local/bin/emcomm-first-boot.sh"
    local profile_d_script="${SQUASHFS_DIR}/etc/profile.d/99-install-chirp-edge.sh"
    
    mkdir -p "$systemd_dir"
    
    # === CREATE PROFILE.D SCRIPT AT BUILD TIME (Fallback) ===
    # Even if systemd service fails, users can still get CHIRP/Edge on login
    log "DEBUG" "Creating profile.d script for CHIRP/Edge installation (fallback)..."
    mkdir -p "$(dirname "$profile_d_script")"
    cat > "$profile_d_script" <<'PROFILE_EOF'
#!/bin/bash
# Install CHIRP and Microsoft Edge on first user login
# Fallback script in case systemd service doesn't run
# Only runs for 'ubuntu' user, only once
# CRITICAL: Ubuntu 22.10 is EOL - must fix apt sources first!

MARKER_FILE="${HOME}/.etc-install-chirp-edge-done"
if [ -f "$MARKER_FILE" ]; then
    return 0 2>/dev/null || exit 0
fi

if [ "$(id -un)" != "ubuntu" ]; then
    return 0
fi

# Only run in interactive shells
[[ $- == *i* ]] || return 0

# Run in background so it doesn't block login
(
    sleep 2  # Wait for system to settle after login
    touch "$MARKER_FILE"
    
    echo ""
    echo "====== EmComm Tools: Installing Packages ======"
    echo ""
    
    # CRITICAL: Fix apt sources for Ubuntu 22.10 (Kinetic) EOL
    # Archive has moved to old-releases.ubuntu.com
    echo "Fixing apt sources for Ubuntu 22.10 (EOL)..."
    if grep -q "archive.ubuntu.com" /etc/apt/sources.list 2>/dev/null; then
        sudo sed -i 's/archive.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list
        sudo sed -i 's/security.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list
        echo "✓ Apt sources updated to old-releases.ubuntu.com"
    fi
    
    echo "Updating package lists (this may take a minute)..."
    if sudo apt-get update -qq 2>/dev/null; then
        echo "✓ Package lists updated"
        
        # CHIRP
        echo "Installing CHIRP..."
        if sudo apt-get install -y -qq chirp 2>/dev/null; then
            echo "✓ CHIRP installed"
        else
            echo "✗ CHIRP failed (can install manually: sudo apt-get install chirp)"
        fi
    else
        echo "✗ apt-get update failed - check network connectivity"
        echo "  Manual fix: sudo apt-get update && sudo apt-get install chirp"
    fi
    
    # Microsoft Edge (downloaded directly, doesn't need apt sources)
    echo "Installing Microsoft Edge..."
    EDGE_DEB="/tmp/microsoft-edge-stable.deb"
    if wget -q --timeout=30 --tries=3 "https://packages.microsoft.com/repos/edge/pool/main/m/microsoft-edge-stable/microsoft-edge-stable_latest_amd64.deb" -O "$EDGE_DEB" 2>/dev/null && [ -f "$EDGE_DEB" ] && [ -s "$EDGE_DEB" ]; then
        if sudo dpkg -i "$EDGE_DEB" >/dev/null 2>&1; then
            sudo apt-get install -y -f >/dev/null 2>&1
            echo "✓ Microsoft Edge installed"
        else
            echo "✗ Edge dpkg install failed"
        fi
        rm -f "$EDGE_DEB"
    else
        echo "✗ Edge download failed (install from https://www.microsoft.com/edge)"
    fi
    
    echo ""
    echo "====== Package Installation Complete ======"
    echo "Log: /var/log/emcomm-first-boot.log"
    echo ""
) &
disown 2>/dev/null

return 0 2>/dev/null || true
PROFILE_EOF
    chmod 755 "$profile_d_script"
    log "SUCCESS" "Fallback profile.d script created at build time"
    
    mkdir -p "$systemd_dir"
    
    log "DEBUG" "Creating first-boot systemd service script: $service_script"
    
    # Create the executable script that systemd will run
    cat > "$service_script" <<'FIRSTBOOT_SCRIPT_EOF'
#!/bin/bash
# EmComm Tools Customizer - First Boot Service
# CRITICAL: Restores Anytone radio config BEFORE user login
# Also installs CHIRP and Edge on first user login
# Runs as root, early in boot process

set -e

LOGFILE="/var/log/emcomm-first-boot.log"
{
    echo "[$(date)] EmComm first-boot service starting..."
    
    # === PHASE 1: Anytone Restoration (runs at boot, root access) ===
    # This must happen early, before user login or ETC post-install resets it
    
    RADIOS_DIR="/opt/emcomm-tools/conf/radios.d"
    MARKER_FILE="/var/lib/emcomm-first-boot-done"
    
    # Only run once
    if [ -f "$MARKER_FILE" ]; then
        echo "[$(date)] First-boot already completed (marker file exists)"
        exit 0
    fi
    
    if [ -f "${RADIOS_DIR}/anytone-d578uv.json" ]; then
        echo "[$(date)] Restoring Anytone D578UV as active radio..."
        if ln -sf "${RADIOS_DIR}/anytone-d578uv.json" "${RADIOS_DIR}/active-radio.json" 2>&1; then
            echo "[$(date)] ✓ Anytone D578UV linked as active-radio.json"
        else
            echo "[$(date)] ✗ Failed to link Anytone (may already be correct)"
        fi
    else
        echo "[$(date)] ✗ Anytone radio config not found at ${RADIOS_DIR}/anytone-d578uv.json"
    fi
    
    # === PHASE 2: Schedule first-login package install ===
    # Create profile.d script for CHIRP/Edge that runs on first user login
    # (This is AFTER Anytone is already restored)
    
    mkdir -p /etc/profile.d
    
    cat > /etc/profile.d/99-install-chirp-edge.sh <<'PROFILE_EOF'
#!/bin/bash
# Install CHIRP and Microsoft Edge on first user login
# Only runs for 'ubuntu' user, only once
# CRITICAL: Ubuntu 22.10 is EOL - must fix apt sources first!

MARKER_FILE="${HOME}/.etc-install-chirp-edge-done"
if [ -f "$MARKER_FILE" ]; then
    return 0 2>/dev/null || exit 0
fi

if [ "$(id -un)" != "ubuntu" ]; then
    return 0
fi

# Only run in interactive shells
[[ $- == *i* ]] || return 0

# Run in background so it doesn't block login
(
    sleep 2  # Wait for system to settle after login
    touch "$MARKER_FILE"
    
    echo ""
    echo "====== EmComm Tools: Installing Packages ======"
    echo ""
    
    # CRITICAL: Fix apt sources for Ubuntu 22.10 (Kinetic) EOL
    # Archive has moved to old-releases.ubuntu.com
    echo "Fixing apt sources for Ubuntu 22.10 (EOL)..."
    if grep -q "archive.ubuntu.com" /etc/apt/sources.list 2>/dev/null; then
        sudo sed -i 's/archive.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list
        sudo sed -i 's/security.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list
        echo "✓ Apt sources updated to old-releases.ubuntu.com"
    fi
    
    echo "Updating package lists (this may take a minute)..."
    if sudo apt-get update -qq 2>/dev/null; then
        echo "✓ Package lists updated"
        
        # CHIRP
        echo "Installing CHIRP..."
        if sudo apt-get install -y -qq chirp 2>/dev/null; then
            echo "✓ CHIRP installed"
        else
            echo "✗ CHIRP failed (can install manually: sudo apt-get install chirp)"
        fi
    else
        echo "✗ apt-get update failed - check network connectivity"
        echo "  Manual fix: sudo apt-get update && sudo apt-get install chirp"
    fi
    
    # Microsoft Edge (downloaded directly, doesn't need apt sources)
    echo "Installing Microsoft Edge..."
    EDGE_DEB="/tmp/microsoft-edge-stable.deb"
    if wget -q --timeout=30 --tries=3 "https://packages.microsoft.com/repos/edge/pool/main/m/microsoft-edge-stable/microsoft-edge-stable_latest_amd64.deb" -O "$EDGE_DEB" 2>/dev/null && [ -f "$EDGE_DEB" ] && [ -s "$EDGE_DEB" ]; then
        if sudo dpkg -i "$EDGE_DEB" >/dev/null 2>&1; then
            sudo apt-get install -y -f >/dev/null 2>&1
            echo "✓ Microsoft Edge installed"
        else
            echo "✗ Edge dpkg install failed"
        fi
        rm -f "$EDGE_DEB"
    else
        echo "✗ Edge download failed (install from https://www.microsoft.com/edge)"
    fi
    
    echo ""
    echo "====== Package Installation Complete ======"
    echo "Log: /var/log/emcomm-first-boot.log"
    echo ""
) &
disown 2>/dev/null

return 0 2>/dev/null || true
PROFILE_EOF
    
    chmod 755 /etc/profile.d/99-install-chirp-edge.sh
    echo "[$(date)] Created /etc/profile.d/99-install-chirp-edge.sh for CHIRP/Edge installation"
    
    # === PHASE 3: Mark first-boot as complete ===
    touch "$MARKER_FILE"
    echo "[$(date)] ✓ First-boot service completed successfully"
    
} >> "$LOGFILE" 2>&1

exit 0
FIRSTBOOT_SCRIPT_EOF
    
    chmod 755 "$service_script"
    
    log "DEBUG" "Creating systemd service file: $service_file"
    
    # Create the systemd service that calls the script
    cat > "$service_file" <<'SYSTEMD_SERVICE_EOF'
[Unit]
Description=EmComm Tools First Boot Setup
After=network.target
Before=getty.target
DefaultDependencies=no

[Service]
Type=oneshot
User=root
ExecStart=/usr/local/bin/emcomm-first-boot.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SYSTEMD_SERVICE_EOF
    
    chmod 644 "$service_file"
    log "SUCCESS" "First-boot systemd service created"
    log "DEBUG" "Service will run on first boot with root privileges"
    log "DEBUG" "Logs available in: /var/log/emcomm-first-boot.log"
    log "DEBUG" "User packages (CHIRP, Edge) installed on first login via profile.d"
    
    # Enable the service so it runs automatically on boot
    log "DEBUG" "Enabling systemd service for first-boot..."
    setup_chroot_mounts
    trap 'cleanup_chroot_mounts' EXIT
    chroot "${SQUASHFS_DIR}" systemctl enable emcomm-first-boot.service 2>&1 | sed 's/^/  [systemctl] /' | tee -a "$LOG_FILE"
    cleanup_chroot_mounts
    trap - EXIT
    log "DEBUG" "Systemd service enabled"
}


setup_vscode_workspace() {
    log "INFO" "Setting up VS Code workspace and project structure..."
    
    local skel_dir="${SQUASHFS_DIR}/etc/skel"
    local projects_dir="${skel_dir}/.config/emcomm-tools/Projects"
    local workspace_dir="${skel_dir}/.config/emcomm-tools"
    
    log "DEBUG" "Creating projects directory: $projects_dir"
    mkdir -p "$projects_dir"
    
    # Create a standard VS Code workspace file that includes the projects directory
    local workspace_file="${workspace_dir}/emcomm-tools.code-workspace"
    log "DEBUG" "Creating VS Code workspace file: $workspace_file"
    
    cat > "$workspace_file" <<'WORKSPACE_EOF'
{
    "folders": [
        {
            "path": "${userHome}/.config/emcomm-tools/Projects",
            "name": "Projects"
        },
        {
            "path": "${userHome}/.config/emcomm-tools",
            "name": "Config"
        }
    ],
    "settings": {
        "files.exclude": {
            "**/.git": false,
            "**/node_modules": true,
            "**/__pycache__": true
        },
        "python.defaultInterpreterPath": "/usr/bin/python3",
        "python.linting.enabled": true,
        "python.linting.pylintEnabled": true,
        "[json]": {
            "editor.defaultFormatter": "esbenp.prettier-vscode",
            "editor.formatOnSave": true
        }
    },
    "extensions": {
        "recommendations": [
            "ms-python.python",
            "ms-python.vscode-pylance",
            "ms-vscode.cpptools",
            "esbenp.prettier-vscode",
            "eamodio.gitlens",
            "ms-vscode.remote-explorer"
        ]
    }
}
WORKSPACE_EOF
    
    log "DEBUG" "VS Code workspace created"
    
    # Create a README in the Projects folder to guide users
    local projects_readme="${projects_dir}/README.md"
    cat > "$projects_readme" <<'README_EOF'
# Projects Directory

This is the default location for all your development projects and repositories.

## Usage

1. **Open in VS Code**: Open the workspace file `~/.config/emcomm-tools/emcomm-tools.code-workspace`
2. **Clone or create projects** in this directory
3. **All files are preserved** across ISO rebuilds (backed up in et-user-backup)

## Project Organization

Suggest organizing projects like:
```
Projects/
├── ham-radio/          # Ham radio related projects
├── emcomm/             # EmComm Tools customizations
├── scripts/            # Utility scripts
└── personal/           # Personal projects
```

## Backup & Restore

Projects in this directory are automatically included in `et-user-backup` during ISO builds:
- Run: `tar -czf ~/etc-user-backup-$(date +%Y%m%d).tar.gz ~/.config/`
- Place in `cache/etc-user-backup-*.tar.gz` before building
- New ISO will restore all your projects on first login
README_EOF
    
    log "SUCCESS" "VS Code workspace setup completed at: $workspace_file"
    log "SUCCESS" "Projects directory created at: $projects_dir"
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
    if [ -n "$emcomm_gateway" ]; then
        log "INFO" "  Default gateway: $emcomm_gateway"
    fi
}

setup_wikipedia_tools() {
    log "INFO" "Setting up Wikipedia offline tools..."
    
    # shellcheck source=/dev/null
    source "$SECRETS_FILE"
    log "DEBUG" "Sourced secrets file for Wikipedia config"
    
    # Get custom articles - handle both array and pipe-separated formats
    local custom_articles=""
    
    # Check if WIKIPEDIA_ARTICLES is an array (bash 4+)
    if declare -p WIKIPEDIA_ARTICLES 2>/dev/null | grep -q 'declare -a'; then
        # It's an array - join with pipes
        if [ ${#WIKIPEDIA_ARTICLES[@]} -gt 0 ]; then
            custom_articles=$(IFS='|'; echo "${WIKIPEDIA_ARTICLES[*]}")
            log "DEBUG" "Wikipedia articles from array: ${#WIKIPEDIA_ARTICLES[@]} articles"
        fi
    elif [ -n "${WIKIPEDIA_ARTICLES:-}" ]; then
        # It's a string (legacy pipe-separated format)
        custom_articles="$WIKIPEDIA_ARTICLES"
        log "DEBUG" "Wikipedia articles from string: $custom_articles"
    fi
    
    # Create add-ons directory for Wikipedia tools
    local addon_dir="${SQUASHFS_DIR}/etc/skel/add-ons/wikipedia"
    mkdir -p "$addon_dir"
    log "DEBUG" "Created Wikipedia add-ons dir: $addon_dir"
    
    # Copy the ZIM creator script from post-install/
    local source_script="${SCRIPT_DIR}/post-install/create-ham-wikipedia-zim.sh"
    if [ -f "$source_script" ]; then
        cp "$source_script" "$addon_dir/"
        chmod +x "$addon_dir/create-ham-wikipedia-zim.sh"
        log "DEBUG" "Copied create-ham-wikipedia-zim.sh"
    else
        log "WARN" "Wikipedia ZIM creator script not found: $source_script"
        return 0
    fi
    
    # Create a wrapper script with custom articles if configured
    local wrapper_script="${addon_dir}/create-my-wikipedia.sh"
    
    if [ -n "$custom_articles" ]; then
        # User specified custom articles
        cat > "$wrapper_script" <<EOF
#!/bin/bash
# Auto-generated by build-etc-iso.sh
# Creates a custom Wikipedia ZIM with your configured articles

SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"

echo "Creating custom Wikipedia ZIM with your configured articles..."
echo ""

"\$SCRIPT_DIR/create-ham-wikipedia-zim.sh" --articles "${custom_articles}"
EOF
        local article_count
        article_count=$(echo "$custom_articles" | tr '|' '\n' | grep -c .)
        log "SUCCESS" "Custom Wikipedia articles configured: $article_count articles"
    else
        # Use default ham radio articles
        cat > "$wrapper_script" <<EOF
#!/bin/bash
# Auto-generated by build-etc-iso.sh
# Creates a custom Wikipedia ZIM with ham radio articles

SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"

echo "Creating Wikipedia ZIM with default ham radio articles..."
echo "(2m, 70cm, GMRS, FRS, APRS, Winlink, DMR, D-STAR, etc.)"
echo ""

"\$SCRIPT_DIR/create-ham-wikipedia-zim.sh"
EOF
        log "DEBUG" "Using default ham radio article list"
    fi
    
    chmod +x "$wrapper_script"
    
    # Create README
    cat > "$addon_dir/README.md" <<'EOF'
# Wikipedia Offline Tools

This directory contains tools for creating custom offline Wikipedia content.

## Quick Start

Run the wrapper script to create a Wikipedia ZIM file with ham radio articles:

```bash
./create-my-wikipedia.sh
```

The script will:
1. Download Wikipedia articles about ham radio topics
2. Create a .zim file in ~/wikipedia/
3. The .zim file can be viewed with Kiwix

## Custom Articles

To download specific articles, run:

```bash
./create-ham-wikipedia-zim.sh --articles "Article1|Article2|Article3"
```

Article names are Wikipedia page titles with spaces replaced by underscores.

## Viewing the Content

After creating the .zim file:

```bash
# Start local Kiwix server
kiwix-serve --port=8080 ~/wikipedia/ham-radio-wikipedia_*.zim

# Open browser to http://localhost:8080
```

Or use the Kiwix desktop app to browse the .zim file.

## Note About ETC's Wikipedia Downloads

ETC's `download-wikipedia.sh` (runs when ET_EXPERT=yes) downloads LARGE
pre-built collections from kiwix.org (computer, medicine, etc. - 100s of MB each).

This script creates SMALL, targeted ZIM files with just the articles you need.
EOF

    log "SUCCESS" "Wikipedia tools installed in ~/add-ons/wikipedia/"
    log "INFO" "  Run ~/add-ons/wikipedia/create-my-wikipedia.sh after first boot"
}

install_gridtracker() {
    log "INFO" "Installing GridTracker 2..."
    
    local gridtracker_url="https://download2.gridtracker.org/GridTracker2-2.250901.0-amd64.deb"
    local tmp_file="${SQUASHFS_DIR}/tmp/gridtracker-tmp.deb"
    
    mkdir -p "${SQUASHFS_DIR}/tmp"
    
    # Download GridTracker DEB
    if ! chroot "${SQUASHFS_DIR}" bash -c "curl -s -L -o /tmp/gridtracker-tmp.deb --fail '$gridtracker_url'"; then
        log "WARN" "GridTracker download failed - skipping"
        return 0
    fi
    
    # Install DEB
    if chroot "${SQUASHFS_DIR}" dpkg -i /tmp/gridtracker-tmp.deb 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "GridTracker 2 installed"
    else
        log "WARN" "GridTracker installation had issues"
    fi
    
    rm -f "$tmp_file"
}

install_wsjtx_improved() {
    log "INFO" "Installing WSJT-X Improved..."
    
    local wsjtx_url="https://downloads.sourceforge.net/project/wsjt-x-improved/WSJT-X_v2.8.0/Linux/wsjtx_2.8.0_improved_PLUS_250501_amd64.deb"
    local tmp_file="${SQUASHFS_DIR}/tmp/wsjtx-tmp.deb"
    
    mkdir -p "${SQUASHFS_DIR}/tmp"
    
    # Download WSJT-X DEB
    if ! chroot "${SQUASHFS_DIR}" bash -c "curl -L -o /tmp/wsjtx-tmp.deb --fail '$wsjtx_url'"; then
        log "WARN" "WSJT-X Improved download failed - skipping"
        return 0
    fi
    
    # Remove old docs to avoid conflicts
    rm -rf "${SQUASHFS_DIR}/usr/share/doc/wsjtx"
    
    # Install DEB and fix dependencies
    chroot "${SQUASHFS_DIR}" bash -c "dpkg -i /tmp/wsjtx-tmp.deb; apt install --fix-broken -y -qq" 2>&1 | tail -5 | tee -a "$LOG_FILE"
    
    # Customize desktop file to use et-wsjtx wrapper
    local desktop_file="${SQUASHFS_DIR}/usr/share/applications/wsjtx.desktop"
    if [ -f "$desktop_file" ]; then
        if ! grep -q "Exec=et-wsjtx" "$desktop_file"; then
            sed -i "s/^Exec=.*$/Exec=et-wsjtx start/" "$desktop_file"
        fi
    fi
    
    log "SUCCESS" "WSJT-X Improved installed"
    rm -f "$tmp_file"
}

install_qsstv() {
    log "INFO" "Installing QSSTV (SSTV transmission/reception)..."
    
    local qsstv_url="https://www.qsl.net/on4qz/qsstv/qsstv109.tgz"
    local tmp_dir="${SQUASHFS_DIR}/tmp/qsstv-build"
    
    mkdir -p "$tmp_dir"
    
    # Download QSSTV source
    if ! chroot "${SQUASHFS_DIR}" bash -c "cd /tmp && curl -L -o qsstv.tgz --fail '$qsstv_url'"; then
        log "WARN" "QSSTV download failed - skipping"
        return 0
    fi
    
    # Extract and build (simplified - requires build tools in chroot)
    if chroot "${SQUASHFS_DIR}" bash -c "cd /tmp && tar -xzf qsstv.tgz && cd qsstv* && ./configure --prefix=/usr && make && make install" 2>&1 | tail -10 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "QSSTV installed"
    else
        log "WARN" "QSSTV build had issues - may need manual setup"
    fi
}

install_xygrib() {
    log "INFO" "Installing XYGrib (weather/GRIB data)..."
    
    # XYGrib is available from standard repos
    if chroot "${SQUASHFS_DIR}" apt-get install -y -qq xygrib 2>&1 | tail -3 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "XYGrib installed"
    else
        log "WARN" "XYGrib installation had issues"
    fi
}

install_kiwix() {
    log "INFO" "Installing Kiwix (offline Wikipedia/docs)..."
    
    # Kiwix is available from snap or repos
    # Try apt first
    if chroot "${SQUASHFS_DIR}" apt-get install -y -qq kiwix-tools 2>&1 | tail -3 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "Kiwix installed via apt"
    else
        log "WARN" "Kiwix via apt had issues - skipping"
    fi
}

setup_wifi_diagnostics() {
    log "INFO" "Creating WiFi diagnostic tools..."
    
    local addon_dir="${SQUASHFS_DIR}/etc/skel/add-ons/network"
    mkdir -p "$addon_dir"
    
    # Create WiFi diagnostics script
    local diag_script="${addon_dir}/wifi-diagnostics.sh"
    log "DEBUG" "Creating WiFi diagnostics script: $diag_script"
    
    cat > "$diag_script" <<'WIFI_DIAG_EOF'
#!/bin/bash
# WiFi Diagnostics Tool
# Check status and troubleshoot WiFi network connections

set -e

echo "=== EmComm Tools WiFi Diagnostics ==="
echo ""

# Check if NetworkManager is running
echo "1. Checking NetworkManager status..."
if systemctl is-active --quiet NetworkManager; then
    echo "   ✓ NetworkManager is running"
else
    echo "   ✗ NetworkManager is NOT running - starting..."
    sudo systemctl start NetworkManager
fi

# List configured connections
echo ""
echo "2. Configured WiFi Networks:"
nmcli connection show --active | grep -i wifi || echo "   (No active WiFi connections)"
echo ""
echo "   All connections:"
nmcli connection show | grep wifi || echo "   (No WiFi connections configured)"

# List available networks
echo ""
echo "3. Available WiFi Networks:"
echo "   (Scan will take a moment...)"
nmcli device wifi list || echo "   (Unable to scan - check WiFi hardware)"

# Check WiFi device status
echo ""
echo "4. WiFi Device Status:"
nmcli device status | grep -i wifi || echo "   (No WiFi devices found)"

# Check connection files
echo ""
echo "5. Connection Files in NetworkManager:"
if [ -d /etc/NetworkManager/system-connections ]; then
    echo "   Files found:"
    ls -lh /etc/NetworkManager/system-connections/ 2>/dev/null || echo "   (No files)"
else
    echo "   ✗ Connection directory not found"
fi

# Test connectivity
echo ""
echo "6. Connectivity Test:"
if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
    echo "   ✓ Internet connectivity verified"
else
    echo "   ✗ No internet connectivity"
fi

# Check system logs
echo ""
echo "7. Recent NetworkManager Logs:"
journalctl -u NetworkManager -n 10 --no-pager 2>/dev/null || echo "   (Unable to read logs)"

# Recommendations
echo ""
echo "=== Troubleshooting Tips ==="
echo ""
echo "If WiFi is not connecting:"
echo "  1. Check SSID and password in /etc/NetworkManager/system-connections/"
echo "  2. Restart NetworkManager: sudo systemctl restart NetworkManager"
echo "  3. Check device: nmcli device wifi"
echo "  4. View detailed logs: journalctl -u NetworkManager -f"
echo ""
echo "To manually add a network:"
echo "  nmcli device wifi connect SSID --ask"
echo ""
echo "To modify an existing connection:"
echo "  nmcli connection edit <connection-name>"
echo ""
WIFI_DIAG_EOF
    chmod 755 "$diag_script"
    log "DEBUG" "WiFi diagnostics script created"
    
    # Create WiFi connection validation script
    local validate_script="${addon_dir}/validate-wifi-config.sh"
    log "DEBUG" "Creating WiFi validation script: $validate_script"
    
    cat > "$validate_script" <<'WIFI_VALIDATE_EOF'
#!/bin/bash
# Validate WiFi Configuration
# Compare build configuration against installed system

echo "=== WiFi Configuration Validation ==="
echo ""

# Check if connection files exist
CONN_DIR="/etc/NetworkManager/system-connections"
if [ ! -d "$CONN_DIR" ]; then
    echo "✗ Connection directory not found: $CONN_DIR"
    exit 1
fi

echo "Checking configured WiFi networks:"
CONN_COUNT=$(find "$CONN_DIR" -name "*.nmconnection" -type f | wc -l)

if [ $CONN_COUNT -eq 0 ]; then
    echo "  ✗ No WiFi networks configured!"
    exit 1
fi

echo "  Found $CONN_COUNT connection(s)"
echo ""

# Check each connection
for conn_file in "$CONN_DIR"/*.nmconnection; do
    if [ ! -f "$conn_file" ]; then
        continue
    fi
    
    basename=$(basename "$conn_file")
    ssid=$(grep "^ssid=" "$conn_file" 2>/dev/null || echo "UNKNOWN")
    autoconnect=$(grep "^autoconnect=" "$conn_file" 2>/dev/null || echo "unknown")
    
    echo "Connection: $basename"
    echo "  SSID: $ssid"
    echo "  Autoconnect: $autoconnect"
    echo ""
done

echo "=== Verification Steps ==="
echo ""
echo "1. Check if networks are available:"
echo "   nmcli device wifi list"
echo ""
echo "2. Manually connect to test:"
echo "   nmcli connection up <connection-name>"
echo ""
echo "3. View connection details:"
echo "   nmcli connection show <connection-name>"
echo ""
echo "4. Check NetworkManager status:"
echo "   systemctl status NetworkManager"
echo ""
WIFI_VALIDATE_EOF
    chmod 755 "$validate_script"
    log "DEBUG" "WiFi validation script created"
    
    # Create README
    local readme="${addon_dir}/README-WIFI.md"
    log "DEBUG" "Creating WiFi documentation: $readme"
    
    cat > "$readme" <<'WIFI_README_EOF'
# WiFi Configuration & Troubleshooting

This directory contains tools for WiFi network configuration and diagnostics.

## Scripts

### wifi-diagnostics.sh
Comprehensive WiFi troubleshooting tool. Shows:
- NetworkManager status
- Configured networks and connections
- Available WiFi networks
- Connection status
- System logs and error messages
- Troubleshooting tips

**Usage:**
```bash
~/add-ons/network/wifi-diagnostics.sh
```

### validate-wifi-config.sh
Validates that WiFi networks were correctly configured from the build.

**Usage:**
```bash
~/add-ons/network/validate-wifi-config.sh
```

## Manual WiFi Configuration

### Add a new network
```bash
nmcli device wifi connect SSID --ask
```

### List available networks
```bash
nmcli device wifi list
```

### Connect to a saved network
```bash
nmcli connection up <connection-name>
```

### Edit existing connection
```bash
nmcli connection edit <connection-name>
```

### Delete a connection
```bash
nmcli connection delete <connection-name>
```

## Connection Files

WiFi networks are stored in `/etc/NetworkManager/system-connections/` as `.nmconnection` files.

Example structure:
```
[connection]
id=MyNetwork
type=wifi
autoconnect=true

[wifi]
ssid=MyNetwork

[wifi-security]
key-mgmt=wpa-psk
psk=password123

[ipv4]
method=auto

[ipv6]
method=auto
```

## Common Issues

### Networks not showing up
1. Check NetworkManager is running: `systemctl status NetworkManager`
2. Restart NetworkManager: `sudo systemctl restart NetworkManager`
3. Check logs: `journalctl -u NetworkManager -f`

### Can't connect to network
1. Verify password is correct
2. Check SSID spelling (case-sensitive)
3. Ensure WiFi hardware is enabled: `nmcli radio wifi on`
4. Check RF interference/channel conflicts

### Connection drops frequently
1. Check WiFi signal strength: `nmcli device wifi list`
2. Update network drivers if needed
3. Check for interference (2.4GHz is crowded, try 5GHz)
4. Review NetworkManager logs: `journalctl -u NetworkManager -f`

## Security Notes

- Passwords in connection files are readable by root only
- Use WPA2/WPA3 encryption (not WEP)
- Keep authentication credentials secure
- Review build logs if connection fails mysteriously

## References

- nmcli reference: `man nmcli`
- NetworkManager docs: https://networkmanager.dev/
- WiFi security: https://en.wikipedia.org/wiki/IEEE_802.11
WIFI_README_EOF
    chmod 644 "$readme"
    log "DEBUG" "WiFi documentation created"
    
    log "SUCCESS" "WiFi diagnostics tools created in ~/add-ons/network/"
    log "INFO" "  Use ~/add-ons/network/wifi-diagnostics.sh to troubleshoot"
}

embed_cache_files() {
    # Embed cache files into the ISO so they're available for future builds
    # This is for users who build on the same machine they install to
    
    if [ $MINIMAL_BUILD -eq 1 ]; then
        log "INFO" "Minimal build - skipping cache embedding"
        return 0
    fi
    
    log "INFO" "Embedding cache files and build logs for future builds..."
    
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
    
    # Copy Wine backup if present
    local wine_backup
    wine_backup=$(find "$CACHE_DIR" -maxdepth 1 -name "etc-wine-backup*.tar.gz" -type f | sort -r | head -1)
    if [ -n "$wine_backup" ] && [ -f "$wine_backup" ]; then
        log "DEBUG" "Copying Wine backup to embedded cache..."
        cp -v "$wine_backup" "$target_cache/"
        log "SUCCESS" "Wine backup embedded"
    else
        log "DEBUG" "No Wine backup found in cache"
    fi
    
    # Copy secrets.env for future builds
    if [ -f "$SECRETS_FILE" ]; then
        log "DEBUG" "Copying secrets.env to embedded cache..."
        cp -v "$SECRETS_FILE" "$target_cache/"
        log "SUCCESS" "secrets.env embedded for future builds"
    else
        log "DEBUG" "No secrets.env found"
    fi
    
    # Embed build logs for debugging and diagnostics
    log "INFO" "Embedding build logs for post-install diagnostics..."
    local target_logs="${SQUASHFS_DIR}/opt/emcomm-customizer-cache/logs"
    mkdir -p "$target_logs"
    
    if [ -d "$LOG_DIR" ]; then
        log "DEBUG" "Copying build logs to embedded cache..."
        cp -v "$LOG_DIR"/*.log "$target_logs/" 2>/dev/null || log "DEBUG" "No log files to copy"
        
        # Create a manifest of this build
        cat > "$target_logs/BUILD_MANIFEST.txt" <<BUILD_EOF
EmComm Tools Customizer - Build Manifest
=========================================

Build Date: $(date +'%Y-%m-%d %H:%M:%S %Z')
Build Mode: $RELEASE_MODE
ETC Version: $RELEASE_TAG
Ubuntu ISO: $UBUNTU_ISO_FILE
Script Version: $(git -C "$SCRIPT_DIR" describe --tags --always 2>/dev/null || echo 'unknown')

Configuration Summary:
- Callsign: ${CALLSIGN:-N0CALL}
- Hostname: ${MACHINE_NAME:-ETC-${CALLSIGN:-N0CALL}}
- Username: ${USER_USERNAME:-${CALLSIGN,,}}
- Timezone: ${TIMEZONE:-America/Denver}
- WiFi Networks: $(grep -c "WIFI_SSID_" "$SECRETS_FILE" 2>/dev/null || echo 'unknown')
- APRS Enabled: $([ -n "${ENABLE_APRS_IGATE:-}" ] && echo 'yes' || echo 'no')
- Autologin: ${ENABLE_AUTOLOGIN:-no}
- Additional Packages: ${ADDITIONAL_PACKAGES:-none}

Build Log Locations:
- All logs: ./logs/
- Latest log: $LOG_FILE
- On installed system: /opt/emcomm-customizer-cache/logs/
- User copy location: ~/.emcomm-customizer/logs/ (after first boot)

To access these logs post-install:
  mkdir -p ~/.emcomm-customizer/logs
  cp /opt/emcomm-customizer-cache/logs/* ~/.emcomm-customizer/logs/
  less ~/.emcomm-customizer/logs/BUILD_MANIFEST.txt

Build Steps Completed:
BUILD_EOF

        # Count successful log entries to show what completed
        grep -c "\[SUCCESS\]" "$LOG_FILE" 2>/dev/null | xargs -I {} echo "  - {} successful operations" >> "$target_logs/BUILD_MANIFEST.txt"
        grep "\[SUCCESS\]" "$LOG_FILE" 2>/dev/null | sed 's/^/    /' >> "$target_logs/BUILD_MANIFEST.txt" || true
        
        log "SUCCESS" "Build logs and manifest embedded"
    else
        log "DEBUG" "No log directory found"
    fi
    
    # Create a README explaining the cache
    cat > "$target_cache/README.txt" <<EOF
EmComm Tools Customizer - Embedded Cache
=========================================

These files were embedded during ISO build so you can rebuild without
re-downloading large files, and for diagnosing build issues.

To use this cache for your next build:
  cp -r /opt/emcomm-customizer-cache/* ~/emcomm-tools-customizer/cache/

Or run build-etc-iso.sh from /opt/emcomm-customizer-cache directly.

Build Logs & Diagnostics:
  - View build manifest: less /opt/emcomm-customizer-cache/logs/BUILD_MANIFEST.txt
  - View full build log: less /opt/emcomm-customizer-cache/logs/*.log
  - After first boot, copy to user home: cp -r /opt/emcomm-customizer-cache/logs ~/.emcomm-customizer/

Files:
$(find "$target_cache" -maxdepth 1 -type f ! -name 'README*' -exec ls -lh {} \; 2>/dev/null)

Build date: $(date +'%Y-%m-%d %H:%M:%S')
EOF
    
    log "SUCCESS" "Cache files and build logs embedded (use -m for minimal build without cache)"
}

verify_customizations() {
    # Final verification of all critical customizations BEFORE ISO creation
    # This catches issues that would otherwise only be discovered after booting
    log "INFO" "=== VERIFYING CRITICAL CUSTOMIZATIONS ==="
    
    local errors=0
    local warnings=0
    
    # 1. Verify wrapper-rigctld.sh is patched for Anytone preservation
    log "INFO" "Checking Anytone radio preservation patch..."
    local wrapper_script="${SQUASHFS_DIR}/opt/emcomm-tools/sbin/wrapper-rigctld.sh"
    if [ -f "$wrapper_script" ]; then
        if grep -q "Anytone D578UV is configured - preserving configuration" "$wrapper_script"; then
            log "SUCCESS" "  ✓ wrapper-rigctld.sh patched for Anytone preservation"
        else
            log "ERROR" "  ✗ wrapper-rigctld.sh NOT patched! Radio will be overwritten on boot!"
            ((errors++))
        fi
    else
        log "WARN" "  ⚠ wrapper-rigctld.sh not found (may be okay if ETC version changed)"
        ((warnings++))
    fi
    
    # 2. Verify active-radio.json symlink points to Anytone
    log "INFO" "Checking active-radio.json symlink..."
    local active_radio="${SQUASHFS_DIR}/opt/emcomm-tools/conf/radios.d/active-radio.json"
    if [ -L "$active_radio" ]; then
        local target
        target=$(readlink "$active_radio")
        if [[ "$target" =~ anytone ]]; then
            log "SUCCESS" "  ✓ active-radio.json → $target"
        else
            log "WARN" "  ⚠ active-radio.json points to: $target (not Anytone)"
            ((warnings++))
        fi
    else
        log "WARN" "  ⚠ active-radio.json is not a symlink"
        ((warnings++))
    fi
    
    # 3. Verify anytone-d578uv.json exists
    log "INFO" "Checking Anytone radio config file..."
    local anytone_config="${SQUASHFS_DIR}/opt/emcomm-tools/conf/radios.d/anytone-d578uv.json"
    if [ -f "$anytone_config" ]; then
        log "SUCCESS" "  ✓ anytone-d578uv.json exists"
    else
        log "ERROR" "  ✗ anytone-d578uv.json NOT found!"
        ((errors++))
    fi
    
    # 4. Verify lsb-release has CUSTOMIZED
    log "INFO" "Checking release info..."
    local lsb_release="${SQUASHFS_DIR}/etc/lsb-release"
    if [ -f "$lsb_release" ]; then
        if grep -q "CUSTOMIZED" "$lsb_release"; then
            local description
            description=$(grep "DISTRIB_DESCRIPTION" "$lsb_release" | cut -d= -f2 | tr -d '"')
            log "SUCCESS" "  ✓ Release: $description"
        else
            log "ERROR" "  ✗ lsb-release does NOT contain 'CUSTOMIZED'!"
            log "DEBUG" "    Current value: $(grep 'DISTRIB_DESCRIPTION' "$lsb_release")"
            ((errors++))
        fi
    else
        log "ERROR" "  ✗ lsb-release file not found!"
        ((errors++))
    fi
    
    # 5. Verify profile.d script for CHIRP/Edge exists
    log "INFO" "Checking CHIRP/Edge installation script..."
    local profile_script="${SQUASHFS_DIR}/etc/profile.d/99-install-chirp-edge.sh"
    if [ -f "$profile_script" ]; then
        if grep -q "old-releases.ubuntu.com" "$profile_script"; then
            log "SUCCESS" "  ✓ CHIRP/Edge script exists with apt source fix"
        else
            log "WARN" "  ⚠ CHIRP/Edge script exists but missing apt source fix"
            ((warnings++))
        fi
    else
        log "WARN" "  ⚠ CHIRP/Edge profile.d script not found"
        ((warnings++))
    fi
    
    # 6. Verify first-boot systemd service
    log "INFO" "Checking first-boot systemd service..."
    local service_file="${SQUASHFS_DIR}/etc/systemd/system/emcomm-first-boot.service"
    if [ -f "$service_file" ]; then
        log "SUCCESS" "  ✓ emcomm-first-boot.service exists"
    else
        log "WARN" "  ⚠ First-boot service not found"
        ((warnings++))
    fi
    
    # 7. Verify udev rules for CAT device
    log "INFO" "Checking CAT udev rules..."
    local udev_rules="${SQUASHFS_DIR}/etc/udev/rules.d/99-emcomm-tools-cat.rules"
    if [ -f "$udev_rules" ]; then
        log "SUCCESS" "  ✓ CAT udev rules exist"
    else
        log "WARN" "  ⚠ CAT udev rules not found"
        ((warnings++))
    fi
    
    # Summary
    log "INFO" ""
    log "INFO" "=== VERIFICATION SUMMARY ==="
    if [ $errors -gt 0 ]; then
        log "ERROR" "  ERRORS: $errors (build may produce broken ISO)"
    else
        log "SUCCESS" "  ERRORS: 0"
    fi
    if [ $warnings -gt 0 ]; then
        log "WARN" "  WARNINGS: $warnings (review above)"
    else
        log "SUCCESS" "  WARNINGS: 0"
    fi
    log "INFO" ""
    
    # Return error code if there were critical failures
    if [ $errors -gt 0 ]; then
        log "ERROR" "Critical errors detected! Review logs before proceeding."
        log "INFO" "Build will continue but ISO may not work correctly."
    fi
    
    return 0  # Don't fail the build, just warn
}

create_build_manifest() {
    log "INFO" "Creating build manifest..."
    
    # shellcheck source=/dev/null
    source "$SECRETS_FILE"
    log "DEBUG" "Sourced secrets file for manifest"
    
    local manifest_file="${SQUASHFS_DIR}/etc/emcomm-customizations-manifest.txt"
    log "DEBUG" "Manifest file: $manifest_file"
    
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
    # Source secrets for compression setting
    # shellcheck source=/dev/null
    source "$SECRETS_FILE"
    
    # Compression options: zstd (default), xz, gzip, lz4
    local compression="${SQUASHFS_COMPRESSION:-zstd}"
    
    # Validate compression option
    case "$compression" in
        xz|zstd|gzip|lz4)
            ;;
        *)
            log "WARN" "Unknown compression '$compression', using zstd"
            compression="zstd"
            ;;
    esac
    
    # Estimate build time based on compression
    local time_estimate
    case "$compression" in
        xz)   time_estimate="80-120 minutes" ;;
        zstd) time_estimate="15-25 minutes" ;;
        gzip) time_estimate="30-45 minutes" ;;
        lz4)  time_estimate="5-10 minutes" ;;
    esac
    
    log "INFO" "Rebuilding squashfs filesystem (compression: $compression, estimated: $time_estimate)..."
    
    local new_squashfs="${WORK_DIR}/filesystem.squashfs.new"
    log "DEBUG" "Creating new squashfs: $new_squashfs"
    log "DEBUG" "Source directory: $SQUASHFS_DIR"
    log "DEBUG" "Compression: $compression, block size: 1M"
    
    # Build mksquashfs command based on compression type
    local mksquashfs_args=(
        "$SQUASHFS_DIR"
        "$new_squashfs"
        -comp "$compression"
        -b 1M
        -noappend
        -progress
    )
    
    # Add compression-specific options
    case "$compression" in
        xz)
            # xz-specific: BCJ filter for x86 improves compression of executables
            mksquashfs_args+=(-Xbcj x86)
            ;;
        zstd)
            # zstd-specific: compression level (default 15, max 22)
            # Level 19 gives near-xz compression with much better speed
            mksquashfs_args+=(-Xcompression-level 19)
            ;;
    esac
    
    # Create new squashfs with compression - show progress
    mksquashfs "${mksquashfs_args[@]}" 2>&1 | while IFS= read -r line; do
        # mksquashfs outputs progress on stderr
        if [[ "$line" =~ ^\[ ]] || [[ "$line" =~ % ]]; then
            printf "\r  %s" "$line"
        fi
    done
    echo ""  # newline after progress
    log "DEBUG" "mksquashfs completed with $compression compression"
    
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
    
    # Calculate MD5 sums
    log "INFO" "Calculating checksums..."
    log "DEBUG" "Running md5sum on all files in ISO"
    (cd "$ISO_EXTRACT_DIR" && find . -type f -print0 | xargs -0 md5sum > md5sum.txt) 2>/dev/null || true
    log "DEBUG" "Checksums calculated"
    
    # Rebuild ISO with xorriso for UEFI-only boot
    # Using -iso-level 3 to allow files over 4GB (embedded cache makes squashfs large)
    log "INFO" "Creating UEFI bootable ISO image..."
    log "DEBUG" "Output ISO: $OUTPUT_ISO"
    log "DEBUG" "ISO label: ETC_${RELEASE_NUMBER^^}_CUSTOM"
    
    # Check if EFI boot image exists
    local efi_boot_img="$ISO_EXTRACT_DIR/boot/grub/efi.img"
    
    if [ ! -f "$efi_boot_img" ]; then
        log "DEBUG" "EFI boot image not found, creating minimal stub..."
        mkdir -p "$(dirname "$efi_boot_img")"
        dd if=/dev/zero of="$efi_boot_img" bs=512 count=2880 2>/dev/null || true
    fi
    
    # Create UEFI-only ISO (no MBR, no legacy boot)
    xorriso -as mkisofs \
        -r -V "ETC_${RELEASE_NUMBER^^}_CUSTOM" \
        -iso-level 3 \
        -J -joliet-long \
        -l \
        -eltorito-alt-boot \
        -e boot/grub/efi.img \
        -no-emul-boot \
        -append_partition 2 0xef "$efi_boot_img" \
        -o "$OUTPUT_ISO" \
        "$ISO_EXTRACT_DIR" 2>&1 | tee -a "$LOG_FILE"
    
    # Strict check - UEFI-only ISO creation must succeed
    if [ ! -f "$OUTPUT_ISO" ] || [ ! -s "$OUTPUT_ISO" ]; then
        log "ERROR" "UEFI-only ISO creation failed (no fallback to MBR)"
        return 1
    fi
    
    local iso_size
    iso_size=$(du -h "$OUTPUT_ISO" | cut -f1)
    local iso_size_bytes
    iso_size_bytes=$(stat -f%z "$OUTPUT_ISO" 2>/dev/null || stat -c%s "$OUTPUT_ISO" 2>/dev/null)
    
    # Estimate final size with component breakdown
    log "INFO" "=== ISO Size Breakdown ==="
    
    local ubuntu_size=0
    local ubuntu_iso="${CACHE_DIR}/${UBUNTU_ISO_FILE}"
    if [ -f "$ubuntu_iso" ]; then
        ubuntu_size=$(stat -c%s "$ubuntu_iso" 2>/dev/null || stat -f%z "$ubuntu_iso" 2>/dev/null)
        log "INFO" "  Ubuntu ISO embedded: $(numfmt --to=iec-i --suffix=B $ubuntu_size 2>/dev/null || echo "~4GB")"
    fi
    
    local wine_size=0
    local wine_backup
    wine_backup=$(find "$CACHE_DIR" -maxdepth 1 -name "etc-wine-backup*.tar.gz" -type f | sort -r | head -1)
    if [ -n "$wine_backup" ] && [ -f "$wine_backup" ]; then
        wine_size=$(stat -c%s "$wine_backup" 2>/dev/null || stat -f%z "$wine_backup" 2>/dev/null)
        log "INFO" "  Wine backup: $(numfmt --to=iec-i --suffix=B $wine_size 2>/dev/null || du -h "$wine_backup" | cut -f1)"
    fi
    
    local secrets_size=0
    if [ -f "$SECRETS_FILE" ]; then
        secrets_size=$(stat -c%s "$SECRETS_FILE" 2>/dev/null || stat -f%z "$SECRETS_FILE" 2>/dev/null)
        log "INFO" "  secrets.env: $(numfmt --to=iec-i --suffix=B $secrets_size 2>/dev/null || du -h "$SECRETS_FILE" | cut -f1)"
    fi
    
    log "INFO" "  Final ISO: $iso_size"
    log "INFO" "========================================="
    
    log "SUCCESS" "ISO created: $OUTPUT_ISO"
    log "INFO" "Copy to Ventoy/Balena Etcher: cp \"$OUTPUT_ISO\" /media/\$USER/Ventoy/"
}

# ============================================================================
# Ventoy Configuration Generator
# ============================================================================
# CRITICAL: Ventoy does NOT use the ISO's grub.cfg boot parameters!
# When booting via Ventoy, the automatic-ubiquity and preseed parameters
# in our ISO's grub.cfg are IGNORED. Ventoy has its own boot system.
#
# To enable automated installation with Ventoy, we must:
#   1. Create ventoy.json with auto_install and boot_conf plugins
#   2. Copy preseed.cfg to the output directory for placement on Ventoy USB
#   3. Provide clear instructions for setting up the Ventoy USB
#
# Reference: https://www.ventoy.net/en/plugin_autoinstall.html

generate_ventoy_config() {
    log "INFO" "Generating Ventoy configuration for automated installation..."
    
    local iso_filename
    iso_filename=$(basename "$OUTPUT_ISO")
    local ventoy_dir="${OUTPUT_DIR}/ventoy"
    
    # Create ventoy directory in output
    mkdir -p "$ventoy_dir"
    
    # Copy preseed.cfg from ISO work directory
    local preseed_src="${ISO_EXTRACT_DIR}/preseed.cfg"
    local preseed_dst="${ventoy_dir}/preseed.cfg"
    
    if [ -f "$preseed_src" ]; then
        cp "$preseed_src" "$preseed_dst"
        log "DEBUG" "Copied preseed.cfg to $preseed_dst"
    else
        log "WARN" "Preseed file not found at $preseed_src - Ventoy auto-install may not work"
    fi
    
    # Generate ventoy.json
    local ventoy_json="${ventoy_dir}/ventoy.json"
    
    cat > "$ventoy_json" <<EOF
{
    "control": [
        { "VTOY_DEFAULT_MENU_MODE": "1" }
    ],
    "auto_install": [
        {
            "image": "/${iso_filename}",
            "template": "/ventoy/preseed.cfg"
        }
    ],
    "conf_replace": [
        {
            "image": "/${iso_filename}",
            "org": "/boot/grub/loopback.cfg",
            "new": "/ventoy/loopback.cfg"
        }
    ]
}
EOF
    log "DEBUG" "Generated ventoy.json at $ventoy_json"
    
    # Generate a custom loopback.cfg with automation parameters
    # This replaces the ISO's loopback.cfg when booted via Ventoy
    local loopback_cfg="${ventoy_dir}/loopback.cfg"
    cat > "$loopback_cfg" <<'EOF'
# Ventoy-compatible loopback.cfg for EmComm Tools automated installation
# This file is injected by Ventoy to enable preseed automation
#
# CRITICAL: Ventoy sets ${iso_path} and ${vtoy_iso_part} automatically
# We use file= to point to the preseed on the Ventoy USB drive

set timeout=5
set default=0

menuentry "Install EmComm Tools (Automated)" {
    linux /casper/vmlinuz file=/cdrom/preseed.cfg automatic-ubiquity only-ubiquity noprompt quiet splash --- 
    initrd /casper/initrd
}

menuentry "Install EmComm Tools (Safe Graphics - Automated)" {
    linux /casper/vmlinuz nomodeset file=/cdrom/preseed.cfg automatic-ubiquity only-ubiquity noprompt quiet splash ---
    initrd /casper/initrd
}

menuentry "Try EmComm Tools without installing" {
    linux /casper/vmlinuz maybe-ubiquity quiet splash ---
    initrd /casper/initrd
}

menuentry "Check disc for defects" {
    linux /casper/vmlinuz integrity-check quiet splash ---
    initrd /casper/initrd
}
EOF
    log "DEBUG" "Generated custom loopback.cfg at $loopback_cfg"
    
    # Generate README for Ventoy setup
    local ventoy_readme="${ventoy_dir}/README.txt"
    cat > "$ventoy_readme" <<EOF
============================================================
   EmComm Tools Custom ISO - Ventoy Setup (OPTIONAL)
============================================================

NOTE: If you're writing the ISO directly with dd, you DON'T need
any of these files! The ISO works correctly when written with:

   sudo dd if=<iso-file> of=/dev/sdX bs=4M status=progress conv=fsync

This directory is ONLY needed if you're using Ventoy.

WHY VENTOY NEEDS EXTRA CONFIG:
------------------------------
Ventoy has its own boot system that IGNORES the ISO's grub.cfg 
boot parameters. Without these files, Ventoy won't pass the 
preseed and automation parameters to the installer.

QUICK SETUP (run this script):
------------------------------
   ./copy-to-ventoy.sh /path/to/ventoy/mount

MANUAL SETUP STEPS:
-------------------

1. Copy the ISO to your Ventoy USB:
   cp "${OUTPUT_ISO}" /path/to/ventoy/

2. Create the ventoy directory on your Ventoy USB:
   mkdir -p /path/to/ventoy/ventoy

3. Copy all files from this directory to the Ventoy USB:
   cp -r ${ventoy_dir}/* /path/to/ventoy/ventoy/

Final structure on Ventoy USB:
   /your-ventoy-mount/
   ├── ${iso_filename}
   └── ventoy/
       ├── ventoy.json
       ├── preseed.cfg
       ├── loopback.cfg
       └── README.txt

4. Safely eject and boot from the Ventoy USB

WHAT THIS DOES:
---------------
- ventoy.json: Tells Ventoy to use preseed.cfg for auto-installation
- preseed.cfg: Contains your user account, timezone, and partition settings
- loopback.cfg: Boot menu with automation parameters

NOTE: Partitioning still requires confirmation in the installer due to
Ubuntu Desktop (Ubiquity) limitations with preseed automation.

============================================================
Generated by EmComm Tools Customizer on $(date)
============================================================
EOF
    log "DEBUG" "Generated README at $ventoy_readme"
    
    # Generate convenience copy script
    local copy_script="${OUTPUT_DIR}/copy-to-ventoy.sh"
    cat > "$copy_script" <<EOF
#!/bin/bash
# Copy EmComm Tools ISO and Ventoy config to a Ventoy USB drive
# Generated by EmComm Tools Customizer
#
# NOTE: This is only needed if using Ventoy. If you write the ISO
# directly with dd, it works without any extra config files.

set -e

VENTOY_MOUNT="\$1"
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
ISO_FILE="${OUTPUT_ISO}"
VENTOY_DIR="\${SCRIPT_DIR}/ventoy"

echo "========================================"
echo "EmComm Tools - Copy to Ventoy (Optional)"
echo "========================================"
echo ""

if [[ -z "\$VENTOY_MOUNT" ]]; then
    echo "Usage: \$0 <VENTOY_MOUNT_PATH>"
    echo ""
    echo "Example: \$0 /media/\$USER/Ventoy"
    echo "         \$0 /mnt/usb"
    echo ""
    echo "This script copies the ISO and Ventoy config files."
    echo "Only needed if using Ventoy (not for dd-written USB)."
    exit 1
fi

# Check if target exists
if [[ ! -d "\$VENTOY_MOUNT" ]]; then
    echo "ERROR: Target path not found: \$VENTOY_MOUNT"
    echo ""
    echo "Make sure your Ventoy USB is mounted first!"
    exit 1
fi

# Check for ISO file
if [[ ! -f "\$ISO_FILE" ]]; then
    echo "ERROR: ISO file not found: \$ISO_FILE"
    exit 1
fi

# Check for ventoy config directory
if [[ ! -d "\$VENTOY_DIR" ]]; then
    echo "ERROR: Ventoy config directory not found: \$VENTOY_DIR"
    exit 1
fi

echo "Source ISO: \$ISO_FILE"
echo "Source config: \$VENTOY_DIR"
echo "Target: \$VENTOY_MOUNT"
echo ""

# Copy ISO
echo "Copying ISO (this may take a few minutes)..."
cp -v "\$ISO_FILE" "\$VENTOY_MOUNT/"
echo ""

# Create ventoy directory and copy config
echo "Copying Ventoy configuration..."
mkdir -p "\$VENTOY_MOUNT/ventoy"
cp -v "\$VENTOY_DIR/"* "\$VENTOY_MOUNT/ventoy/"
echo ""

# Sync to ensure all data is written
echo "Syncing..."
sync
echo ""

echo "========================================"
echo "SUCCESS! Files copied to Ventoy USB"
echo "========================================"
echo ""
echo "You can now safely eject the USB and boot from it."
echo ""
echo "When you boot, select '${iso_filename}' from the Ventoy menu."
echo "The installer will run in semi-automated mode."
echo ""
EOF
    chmod +x "$copy_script"
    log "DEBUG" "Generated copy script at $copy_script"
    
    log "SUCCESS" "Ventoy configuration generated at: $ventoy_dir (for Ventoy users only)"
}

# ============================================================================
# USB Write Functions
# ============================================================================

# Detect and select a USB device interactively
# Returns the selected device path in the global variable SELECTED_USB_DEVICE
select_usb_device() {
    local devices=()
    local device_info=()
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║   Detecting USB Devices                                       ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Find removable block devices (USB drives)
    # Look for devices where removable=1 or hotplug transport
    while IFS= read -r line; do
        local dev_name dev_size dev_model dev_tran dev_rm
        dev_name=$(echo "$line" | awk '{print $1}')
        dev_size=$(echo "$line" | awk '{print $2}')
        dev_tran=$(echo "$line" | awk '{print $3}')
        dev_rm=$(echo "$line" | awk '{print $4}')
        dev_model=$(echo "$line" | awk '{$1=$2=$3=$4=""; print $0}' | xargs)
        
        # Skip if not a disk
        [[ -z "$dev_name" ]] && continue
        
        # Skip nvme devices (system drives)
        [[ "$dev_name" == nvme* ]] && continue
        
        # Include if removable=1 OR transport is usb
        if [[ "$dev_rm" == "1" ]] || [[ "$dev_tran" == "usb" ]]; then
            devices+=("/dev/$dev_name")
            device_info+=("$dev_size  $dev_model")
        fi
    done < <(lsblk -d -n -o NAME,SIZE,TRAN,RM,MODEL 2>/dev/null | grep -E "^sd|^hd")
    
    # Check if any USB devices found
    if [[ ${#devices[@]} -eq 0 ]]; then
        log "ERROR" "No USB devices detected!"
        echo ""
        echo "  Make sure your USB drive is plugged in."
        echo "  If it's a new drive, it may need to be formatted first."
        echo ""
        echo "  All detected disks:"
        lsblk -d -o NAME,SIZE,TRAN,RM,MODEL 2>/dev/null | head -20
        echo ""
        return 1
    fi
    
    # Display menu
    echo "  Available USB devices:"
    echo ""
    for i in "${!devices[@]}"; do
        printf "    [%d] %-12s %s\n" "$((i+1))" "${devices[$i]}" "${device_info[$i]}"
    done
    echo ""
    echo "    [0] Cancel"
    echo ""
    
    # Get user selection
    local selection
    while true; do
        read -r -p "  Select device [1-${#devices[@]}]: " selection
        
        if [[ "$selection" == "0" ]]; then
            log "INFO" "USB write cancelled by user"
            return 1
        fi
        
        if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le ${#devices[@]} ]]; then
            SELECTED_USB_DEVICE="${devices[$((selection-1))]}"
            log "INFO" "Selected: $SELECTED_USB_DEVICE"
            return 0
        fi
        
        echo "  Invalid selection. Enter 1-${#devices[@]} or 0 to cancel."
    done
}

# Write ISO directly to USB with dd and eject when complete
# This is the RECOMMENDED method - preserves grub.cfg boot parameters
write_to_usb() {
    local device="$1"
    local iso_file="$2"
    
    # If device is empty or "auto", run interactive selection
    if [[ -z "$device" ]] || [[ "$device" == "auto" ]]; then
        if ! select_usb_device; then
            return 1
        fi
        device="$SELECTED_USB_DEVICE"
    fi
    
    # Validate device parameter (should not happen after selection, but safety check)
    if [[ -z "$device" ]]; then
        log "ERROR" "No USB device specified for --write-to"
        return 1
    fi
    
    # Validate ISO file
    if [[ ! -f "$iso_file" ]]; then
        log "ERROR" "ISO file not found: $iso_file"
        return 1
    fi
    
    # Safety checks for device
    if [[ ! -b "$device" ]]; then
        log "ERROR" "Not a block device: $device"
        log "ERROR" "Expected something like /dev/sdb, /dev/sdc, etc."
        return 1
    fi
    
    # Prevent writing to nvme drives (likely system drives)
    if [[ "$device" == *nvme* ]]; then
        log "ERROR" "Refusing to write to NVMe device: $device"
        log "ERROR" "NVMe devices are typically system drives, not USB devices"
        return 1
    fi
    
    # Prevent writing to partition (should be whole disk like /dev/sdb, not /dev/sdb1)
    if [[ "$device" =~ [0-9]$ ]]; then
        log "ERROR" "Device appears to be a partition: $device"
        log "ERROR" "Use the whole disk device (e.g., /dev/sdb not /dev/sdb1)"
        return 1
    fi
    
    # Get device info for confirmation
    local device_name
    device_name=$(basename "$device")
    local device_size=""
    local device_model=""
    
    if [[ -f "/sys/block/${device_name}/size" ]]; then
        local size_sectors
        size_sectors=$(cat "/sys/block/${device_name}/size" 2>/dev/null || echo "0")
        device_size="$((size_sectors * 512 / 1024 / 1024 / 1024))GB"
    fi
    
    if [[ -f "/sys/block/${device_name}/device/model" ]]; then
        device_model=$(cat "/sys/block/${device_name}/device/model" 2>/dev/null | xargs)
    fi
    
    # Confirm with user (this is destructive!)
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║   ⚠️  WARNING: USB WRITE WILL ERASE ALL DATA ⚠️               ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Device: $device"
    [[ -n "$device_size" ]] && echo "  Size:   $device_size"
    [[ -n "$device_model" ]] && echo "  Model:  $device_model"
    echo ""
    echo "  ISO:    $(basename "$iso_file")"
    echo "  Size:   $(du -h "$iso_file" | cut -f1)"
    echo ""
    echo "  ALL DATA ON $device WILL BE DESTROYED!"
    echo ""
    
    # Check if device has mounted partitions
    local mounted_parts
    mounted_parts=$(mount | grep "^${device}" | awk '{print $1 " mounted at " $3}' || true)
    if [[ -n "$mounted_parts" ]]; then
        echo "  MOUNTED PARTITIONS DETECTED:"
        echo "$mounted_parts" | sed 's/^/    /'
        echo ""
        log "INFO" "Unmounting partitions on $device..."
        # Unmount all partitions on this device
        for part in $(mount | grep "^${device}" | awk '{print $1}'); do
            log "DEBUG" "Unmounting $part"
            if ! umount "$part" 2>/dev/null; then
                log "ERROR" "Failed to unmount $part"
                log "ERROR" "Please manually unmount before running build"
                return 1
            fi
        done
        log "SUCCESS" "All partitions unmounted"
        echo ""
    fi
    
    read -r -p "Type 'YES' to confirm write to $device: " confirm
    echo ""
    
    if [[ "$confirm" != "YES" ]]; then
        log "INFO" "USB write cancelled by user"
        return 0
    fi
    
    # Write ISO with dd
    log "INFO" "Writing ISO to $device (this will take several minutes)..."
    log "INFO" "You can monitor progress in the terminal"
    echo ""
    
    if ! dd if="$iso_file" of="$device" bs=4M status=progress conv=fsync 2>&1; then
        log "ERROR" "Failed to write ISO to $device"
        return 1
    fi
    
    echo ""
    log "SUCCESS" "ISO written to $device"
    
    # Sync to ensure all data is flushed
    log "INFO" "Syncing data..."
    sync
    
    # Eject the device
    log "INFO" "Ejecting $device..."
    if eject "$device" 2>/dev/null; then
        log "SUCCESS" "USB device ejected - safe to remove!"
    else
        log "WARN" "Could not auto-eject device. Please eject manually before removing."
    fi
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║   ✅ USB WRITE COMPLETE                                       ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Your bootable USB is ready!"
    echo "  Insert into target computer and boot from USB."
    echo ""
    
    return 0
}

# Copy ISO and Ventoy config to a mounted Ventoy USB
# Use this ONLY if you prefer Ventoy over dd
copy_to_ventoy() {
    local ventoy_mount="$1"
    local iso_file="$2"
    local ventoy_config_dir="${OUTPUT_DIR}/ventoy"
    
    # Validate parameters
    if [[ -z "$ventoy_mount" ]]; then
        log "ERROR" "No Ventoy mount path specified"
        return 1
    fi
    
    if [[ ! -d "$ventoy_mount" ]]; then
        log "ERROR" "Ventoy mount path not found: $ventoy_mount"
        log "ERROR" "Make sure your Ventoy USB is mounted"
        return 1
    fi
    
    if [[ ! -f "$iso_file" ]]; then
        log "ERROR" "ISO file not found: $iso_file"
        return 1
    fi
    
    if [[ ! -d "$ventoy_config_dir" ]]; then
        log "ERROR" "Ventoy config directory not found: $ventoy_config_dir"
        log "ERROR" "This should have been generated during build"
        return 1
    fi
    
    # Check for ventoy.json (indicates this is a Ventoy USB)
    local existing_ventoy="${ventoy_mount}/ventoy"
    
    log "INFO" "Copying ISO to Ventoy USB..."
    echo ""
    echo "  Source: $(basename "$iso_file") ($(du -h "$iso_file" | cut -f1))"
    echo "  Target: $ventoy_mount/"
    echo ""
    
    # Copy ISO
    if ! cp -v "$iso_file" "$ventoy_mount/"; then
        log "ERROR" "Failed to copy ISO to $ventoy_mount"
        return 1
    fi
    
    # Create ventoy config directory
    log "INFO" "Copying Ventoy configuration..."
    mkdir -p "$ventoy_mount/ventoy"
    
    # Copy all Ventoy config files
    if ! cp -v "$ventoy_config_dir/"* "$ventoy_mount/ventoy/"; then
        log "ERROR" "Failed to copy Ventoy config files"
        return 1
    fi
    
    # Sync to ensure data is written
    log "INFO" "Syncing..."
    sync
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║   ✅ VENTOY COPY COMPLETE                                     ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Files copied to Ventoy USB:"
    echo "    - $(basename "$iso_file")"
    echo "    - ventoy/ventoy.json"
    echo "    - ventoy/preseed.cfg"
    echo "    - ventoy/loopback.cfg"
    echo ""
    echo "  You can safely eject the USB and boot from it."
    echo "  Select the ISO from Ventoy's boot menu."
    echo ""
    
    return 0
}

# ============================================================================
# Cleanup
# ============================================================================

cleanup_work_dir() {
    if [ "$KEEP_WORK" -eq 1 ]; then
        log "INFO" "Keeping work directory for debugging (-k flag)"
        log "INFO" "  Location: $WORK_DIR"
        log "INFO" "  To clean manually: sudo rm -rf $WORK_DIR"
        return 0
    fi
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
    
    # Capture fresh user backup from running system BEFORE build
    log "INFO" "Capturing fresh user backup from running system..."
    if ! create_fresh_user_backup; then
        log "WARN" "Failed to create fresh user backup - will use cached backup if available"
        # Don't fail the build, just warn
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
        # cleanup_work_dir  # DISABLED: Keep work directory for debugging
        exit 1
    fi
    
    if ! download_etc_installer; then
        # cleanup_work_dir  # DISABLED: Keep work directory for debugging
        exit 1
    fi
    
    # NOTE: et-os-addons functionality is now integrated directly via ENABLE_ETOSADDONS_* variables
    # The old et-os-addons repo overlay approach has been replaced with selective feature installation
    # See integrate_etosaddons_features() for the current implementation
    
    # Extract ISO
    if ! extract_iso; then
        # cleanup_work_dir  # DISABLED: Keep work directory for debugging
        exit 1
    fi
    
    # Install ETC in chroot (this is the main installation)
    if ! install_etc_in_chroot; then
        # cleanup_work_dir  # DISABLED: Keep work directory for debugging
        exit 1
    fi
    
    # NOTE: et-os-addons integration now happens selectively via ENABLE_ETOSADDONS_* variables
    # The old overlay merge approach has been replaced (see integrate_etosaddons_features)
    
    # Apply customizations (AFTER ETC is installed)
    log "INFO" ""
    log "INFO" "=== Applying Customizations ==="
    log "DEBUG" "Starting customization phase..."
    
    # Note: et-os-addons overlay NO LONGER applied as a separate layer
    # Instead, we integrate specific functionality directly into our build steps
    # to avoid overwrites and maintain control over execution order
    
    log "DEBUG" "Step 1/14: customize_hostname"
    customize_hostname
    log "DEBUG" "Step 1/14: customize_hostname COMPLETED"
    
    log "DEBUG" "Step 2/14: restore_user_backup"
    restore_user_backup        # Restore user configs from backup (user: fast with timeout, wine: deferred to first login)
    log "DEBUG" "Step 2/14: restore_user_backup COMPLETED"
    
    log "DEBUG" "Step 3/14: customize_wifi"
    customize_wifi
    log "DEBUG" "Step 3/14: customize_wifi COMPLETED"
    
    log "DEBUG" "Step 4/14: customize_desktop"
    customize_desktop
    log "DEBUG" "Step 4/14: customize_desktop COMPLETED"
    
    log "DEBUG" "Step 4a/14: update_release_info"
    update_release_info
    log "DEBUG" "Step 4a/14: update_release_info COMPLETED"
    
    log "DEBUG" "Step 5/14: customize_aprs"
    customize_aprs
    log "DEBUG" "Step 5/14: customize_aprs COMPLETED"
    
    log "DEBUG" "Step 6/14: customize_radio_configs"
    customize_radio_configs
    log "DEBUG" "Step 6/14: customize_radio_configs COMPLETED"
    
    log "DEBUG" "Step 6a/14: integrate_etosaddons_features"
    integrate_etosaddons_features
    log "DEBUG" "Step 6a/14: integrate_etosaddons_features COMPLETED"
    
    log "DEBUG" "Step 7/14: customize_user_and_autologin"
    customize_user_and_autologin
    log "DEBUG" "Step 7/14: customize_user_and_autologin COMPLETED"
    
    log "DEBUG" "Step 8/14: customize_preseed"
    customize_preseed
    log "DEBUG" "Step 8/14: customize_preseed COMPLETED"
    

    
    log "DEBUG" "Step 10/14: customize_pat"
    customize_pat
    log "DEBUG" "Step 10/14: customize_pat COMPLETED"
    
    log "DEBUG" "Step 11/14: setup_wikipedia_tools"
    setup_wikipedia_tools
    log "DEBUG" "Step 11/14: setup_wikipedia_tools COMPLETED"
    
    log "DEBUG" "Step 12/14: setup_wifi_diagnostics"
    setup_wifi_diagnostics
    log "DEBUG" "Step 12/14: setup_wifi_diagnostics COMPLETED"
    
    log "DEBUG" "Step 13/14: customize_git_config"
    customize_git_config
    log "DEBUG" "Step 13/14: customize_git_config COMPLETED"
    
    log "DEBUG" "Step 13a/14: setup_first_login_packages"
    setup_first_login_packages
    log "DEBUG" "Step 13a/14: setup_first_login_packages COMPLETED"
    
    log "DEBUG" "Step 14/14: setup_vscode_workspace"
    setup_vscode_workspace
    log "DEBUG" "Step 14/14: setup_vscode_workspace COMPLETED"
    
    log "DEBUG" "Step 15/14: customize_additional_packages"
    customize_additional_packages
    log "DEBUG" "Step 15/14: customize_additional_packages COMPLETED"
    
    log "DEBUG" "Step 15/19: install_gridtracker"
    setup_chroot_mounts
    trap 'cleanup_chroot_mounts' EXIT
    install_gridtracker
    cleanup_chroot_mounts
    trap - EXIT
    log "DEBUG" "Step 15/19: install_gridtracker COMPLETED"
    
    log "DEBUG" "Step 16/19: install_wsjtx_improved"
    setup_chroot_mounts
    trap 'cleanup_chroot_mounts' EXIT
    install_wsjtx_improved
    cleanup_chroot_mounts
    trap - EXIT
    log "DEBUG" "Step 16/19: install_wsjtx_improved COMPLETED"
    
    log "DEBUG" "Step 17/19: install_qsstv"
    setup_chroot_mounts
    trap 'cleanup_chroot_mounts' EXIT
    install_qsstv
    cleanup_chroot_mounts
    trap - EXIT
    log "DEBUG" "Step 17/19: install_qsstv COMPLETED"
    
    log "DEBUG" "Step 18/19: install_xygrib_and_kiwix"
    setup_chroot_mounts
    trap 'cleanup_chroot_mounts' EXIT
    install_xygrib
    install_kiwix
    cleanup_chroot_mounts
    trap - EXIT
    log "DEBUG" "Step 18/19: install_xygrib_and_kiwix COMPLETED"
    
    log "DEBUG" "Step 19/19: embed_cache_files"
    embed_cache_files
    log "DEBUG" "Step 19/19: embed_cache_files COMPLETED"
    
    log "DEBUG" "Step 20/22: create_build_manifest"
    create_build_manifest
    log "DEBUG" "Step 20/22: create_build_manifest COMPLETED"
    
    log "DEBUG" "Step 21/22: update_grub_for_preseed"
    update_grub_for_preseed
    log "DEBUG" "Step 21/22: update_grub_for_preseed COMPLETED"
    
    log "DEBUG" "Step 22/22: Final cleanup"
    log "DEBUG" "Step 22/22: Final cleanup COMPLETED"
    
    # VERIFY all customizations before ISO creation
    verify_customizations
    
    # Rebuild ISO
    log "INFO" ""
    log "INFO" "=== Rebuilding ISO ==="
    
    if ! rebuild_squashfs; then
        # cleanup_work_dir  # DISABLED: Keep work directory for debugging
        exit 1
    fi
    if ! rebuild_iso; then
        # cleanup_work_dir  # DISABLED: Keep work directory for debugging
        exit 1
    fi
    
    # Generate Ventoy configuration files (optional - only needed if using Ventoy)
    # When booting via dd-written USB, the ISO's grub.cfg works correctly.
    # Ventoy ignores ISO boot parameters, so it needs separate config files.
    generate_ventoy_config
    
    # Write to USB if --write-to specified (recommended method)
    if [[ -n "$WRITE_TO_USB" ]]; then
        log "INFO" ""
        log "INFO" "=== Writing ISO to USB Device ==="
        if ! write_to_usb "$WRITE_TO_USB" "$OUTPUT_ISO"; then
            log "ERROR" "USB write failed"
            exit 1
        fi
    # Copy to Ventoy if --ventoy specified (alternative method)
    elif [[ -n "$VENTOY_MOUNT" ]]; then
        log "INFO" ""
        log "INFO" "=== Copying to Ventoy USB ==="
        if ! copy_to_ventoy "$VENTOY_MOUNT" "$OUTPUT_ISO"; then
            log "ERROR" "Ventoy copy failed"
            exit 1
        fi
    fi
    
    # Cleanup
    # cleanup_work_dir  # DISABLED: Keep work directory for debugging
    
    # Summary
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║   Build Complete!                                            ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    log "SUCCESS" "Custom ISO: $OUTPUT_ISO"
    
    # Show appropriate next steps based on what was done
    if [[ -n "$WRITE_TO_USB" ]]; then
        log "INFO" "USB device ready at: $WRITE_TO_USB"
    elif [[ -n "$VENTOY_MOUNT" ]]; then
        log "SUCCESS" "Copied to Ventoy at: $VENTOY_MOUNT"
    else
        # No USB write requested - show manual instructions
        log "INFO" ""
        log "INFO" "=== Next Steps: Write ISO to USB ==="
        log "INFO" ""
        log "INFO" "OPTION 1 - Write directly (recommended):"
        log "INFO" "  # Find your USB device (BE CAREFUL - this erases the drive!)"
        log "INFO" "  lsblk"
        log "INFO" ""
        log "INFO" "  # Write ISO to USB (replace sdX with your device)"
        log "INFO" "  sudo dd if=\"$OUTPUT_ISO\" of=/dev/sdX bs=4M status=progress conv=fsync"
        log "INFO" ""
        log "INFO" "  # Safely eject"
        log "INFO" "  sudo eject /dev/sdX"
        log "INFO" ""
        log "INFO" "OPTION 2 - Use Ventoy (requires extra config):"
        log "INFO" "  Ventoy ignores ISO boot params, so use the copy script:"
        log "INFO" "  ${OUTPUT_DIR}/copy-to-ventoy.sh /media/\$USER/Ventoy"
    fi
    log "INFO" ""
    log "INFO" "Build log: $LOG_FILE"
}

# ============================================================================
# Parse Arguments
# ============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        -r)
            RELEASE_MODE="$2"
            if [[ ! "$RELEASE_MODE" =~ ^(stable|latest|tag)$ ]]; then
                echo "ERROR: Invalid release mode: $RELEASE_MODE" >&2
                echo "Must be: stable, latest, or tag" >&2
                usage
                exit 1
            fi
            shift 2
            ;;
        -t)
            SPECIFIED_TAG="$2"
            shift 2
            ;;
        -l)
            list_available_versions
            exit 0
            ;;
        -d)
            DEBUG_MODE=1
            log "INFO" "Debug mode enabled - showing DEBUG messages"
            shift
            ;;
        -k)
            KEEP_WORK=1
            log "INFO" "Keep mode - .work directory will be preserved for debugging"
            shift
            ;;
        -m)
            MINIMAL_BUILD=1
            log "INFO" "Minimal build - cache files will not be embedded in ISO"
            shift
            ;;
        -v)
            set -x
            shift
            ;;
        --write-to)
            # Check if next arg is a device path or another option/missing
            if [[ -n "$2" ]] && [[ "$2" != -* ]]; then
                WRITE_TO_USB="$2"
                log "INFO" "ISO will be written to USB device: $WRITE_TO_USB"
                shift 2
            else
                # No device specified - will auto-detect after build
                WRITE_TO_USB="auto"
                log "INFO" "ISO will be written to USB (device auto-detect after build)"
                shift
            fi
            ;;
        --ventoy)
            VENTOY_MOUNT="$2"
            if [[ -z "$VENTOY_MOUNT" ]]; then
                echo "ERROR: --ventoy requires a mount path argument" >&2
                usage
                exit 1
            fi
            log "INFO" "ISO will be copied to Ventoy at: $VENTOY_MOUNT"
            shift 2
            ;;
        -h)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
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
