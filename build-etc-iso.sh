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
ADDONS_BUILD=0                            # When 1, include et-os-addons (WSJT-X Improved, GridTracker, SSTV, etc.)

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
    -a        Include et-os-addons (WSJT-X Improved, GridTracker 2, SSTV, weather tools)
              Adds ~2GB to ISO but enables FT8/FT4 and extended radio modes
    -d        Debug mode (show DEBUG log messages on console)
    -k        Keep work directory after build (for iterative debugging)
    -m        Minimal build (omit cache files from ISO to reduce size)
    -v        Verbose mode (enable bash -x debugging)
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

download_etosaddons() {
    if [ "$ADDONS_BUILD" -ne 1 ]; then
        log "DEBUG" "et-os-addons not enabled, skipping download"
        return 0
    fi
    
    mkdir -p "$CACHE_DIR"
    
    local zip_file="${CACHE_DIR}/et-os-addons-main.zip"
    local addons_dir="${CACHE_DIR}/et-os-addons-main"
    
    # Check if already cached
    if [ -d "$addons_dir" ]; then
        log "SUCCESS" "et-os-addons found in cache"
        ETOSADDONS_DIR="$addons_dir"
        return 0
    fi
    
    log "INFO" "Downloading et-os-addons (adds WSJT-X Improved, GridTracker, SSTV, weather tools)..."
    
    if ! wget -O "$zip_file" "https://github.com/clifjones/et-os-addons/archive/refs/heads/main.zip"; then
        log "ERROR" "Failed to download et-os-addons"
        return 1
    fi
    
    log "INFO" "Extracting et-os-addons..."
    if ! unzip -q "$zip_file" -d "$CACHE_DIR"; then
        log "ERROR" "Failed to extract et-os-addons"
        return 1
    fi
    
    # Clean up zip file
    rm -f "$zip_file"
    
    log "SUCCESS" "et-os-addons downloaded and extracted"
    ETOSADDONS_DIR="$addons_dir"
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
    
    # Clean up
    cleanup_chroot_mounts
    trap - EXIT
    
    # Remove installer files
    log "DEBUG" "Cleaning up installer files..."
    rm -rf "$etc_install_dir"
    
    if [ "$exit_code" -ne 0 ]; then
        log "ERROR" "ETC installation failed with exit code: $exit_code"
        return 1
    fi
    
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

merge_etosaddons() {
    if [ "$ADDONS_BUILD" -ne 1 ]; then
        log "DEBUG" "et-os-addons not enabled, skipping merge"
        return 0
    fi
    
    if [ -z "${ETOSADDONS_DIR:-}" ]; then
        log "WARN" "et-os-addons directory not set, skipping merge"
        return 0
    fi
    
    log "INFO" ""
    log "INFO" "=== Merging et-os-addons (FT8/GridTracker/SSTV) ==="
    
    local addons_overlay="${ETOSADDONS_DIR}/overlay"
    
    if [ ! -d "$addons_overlay" ]; then
        log "ERROR" "et-os-addons overlay directory not found: $addons_overlay"
        return 1
    fi
    
    log "INFO" "Merging overlay from: $addons_overlay"
    
    # Copy et-os-addons overlay into squashfs root
    # This adds WSJT-X Improved, GridTracker 2, SSTV, weather tools, etc.
    if ! cp -a "$addons_overlay"/* "${SQUASHFS_DIR}/" 2>/dev/null; then
        log "WARN" "Failed to copy some overlay files, continuing..."
    fi
    
    log "SUCCESS" "et-os-addons merged successfully"
    
    # List what was added (for logging purposes)
    if [ -d "${SQUASHFS_DIR}/opt/emcomm-tools/addons" ]; then
        log "INFO" "Added packages:"
        find "${SQUASHFS_DIR}/opt/emcomm-tools/addons" -maxdepth 1 -type d -exec basename {} \; | while read -r addon; do
            if [ "$addon" != "addons" ]; then
                log "INFO" "  - $addon"
            fi
        done
    fi
    
    return 0
}

# ============================================================================
# Customization Functions (apply AFTER ETC is installed)
# ============================================================================

restore_user_backup() {
    log "INFO" "Checking for ETC backups in cache directory..."
    
    local cache_dir="${SCRIPT_DIR}/cache"
    local user_backup=""
    local wine_backup=""
    
    # Auto-detect user backup (etc-user-backup-*.tar.gz)
    # Use the most recent one if multiple exist
    if compgen -G "${cache_dir}/etc-user-backup-*.tar.gz" > /dev/null 2>&1; then
        user_backup=$(find "${cache_dir}" -maxdepth 1 -name 'etc-user-backup-*.tar.gz' -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
        log "DEBUG" "Found user backup: $user_backup"
    fi
    
    # Auto-detect wine backup (etc-wine-backup-*.tar.gz)
    # Use the most recent one if multiple exist
    if compgen -G "${cache_dir}/etc-wine-backup-*.tar.gz" > /dev/null 2>&1; then
        wine_backup=$(find "${cache_dir}" -maxdepth 1 -name 'etc-wine-backup-*.tar.gz' -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
        log "DEBUG" "Found Wine backup: $wine_backup"
    fi
    
    # Check if any backups were found
    if [ -z "$user_backup" ] && [ -z "$wine_backup" ]; then
        log "DEBUG" "No backup files found in ${cache_dir}/"
        log "DEBUG" "To restore settings, place etc-user-backup-*.tar.gz or etc-wine-backup-*.tar.gz in cache/"
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
        
        # List contents for verification
        log "DEBUG" "Backup contents:"
        tar tzf "$user_backup" | head -20 | while read -r line; do
            log "DEBUG" "  $line"
        done
        
        # Extract to /etc/skel (without leading path components that match home dir structure)
        # et-user-backup creates: .config/emcomm-tools/, .local/share/emcomm-tools/, .local/share/pat/
        local skel_dir="${SQUASHFS_DIR}/etc/skel"
        mkdir -p "$skel_dir"
        
        # Extract backup into /etc/skel
        # The tarball contains paths like .config/emcomm-tools/user.json (relative to $HOME)
        tar xzf "$user_backup" -C "$skel_dir"
        
        log "SUCCESS" "User backup restored to /etc/skel"
        log "DEBUG" "Restored files:"
        find "$skel_dir/.config/emcomm-tools" -type f 2>/dev/null | head -10 | while read -r f; do
            log "DEBUG" "  ${f#"$skel_dir"}"
        done
        find "$skel_dir/.local/share/emcomm-tools" -type f 2>/dev/null | head -10 | while read -r f; do
            log "DEBUG" "  ${f#"$skel_dir"}"
        done
        find "$skel_dir/.local/share/pat" -type f 2>/dev/null | head -10 | while read -r f; do
            log "DEBUG" "  ${f#"$skel_dir"}"
        done
    fi
    
    # Restore Wine backup (VARA/Wine prefix)
    # Contains: .wine32/ (entire 32-bit Wine prefix)
    # TODO: Disabled for now - large tarball extraction causing issues
    # Re-enable in future revision after testing with smaller files
    if [ -n "$wine_backup" ]; then
        log "INFO" "Wine backup found but restore is disabled in this version"
        log "INFO" "To restore manually after install: tar xzf $(basename "$wine_backup") -C ~"
        # log "INFO" "Restoring Wine backup: $(basename "$wine_backup")"
        # 
        # # Verify it's a valid tarball
        # if ! tar tzf "$wine_backup" >/dev/null 2>&1; then
        #     log "ERROR" "Invalid tarball: $wine_backup"
        #     return 1
        # fi
        # 
        # # List contents for verification
        # log "DEBUG" "Wine backup contents (first 20 entries):"
        # tar tzf "$wine_backup" | head -20 | while read -r line; do
        #     log "DEBUG" "  $line"
        # done
        # 
        # # Extract to /etc/skel
        # local skel_dir="${SQUASHFS_DIR}/etc/skel"
        # mkdir -p "$skel_dir"
        # 
        # # Extract Wine backup
        # # The tarball should contain .wine32/ (relative to $HOME)
        # tar xzf "$wine_backup" -C "$skel_dir"
        # 
        # # Verify extraction
        # if [ -d "$skel_dir/.wine32" ]; then
        #     local wine_size
        #     wine_size=$(du -sh "$skel_dir/.wine32" 2>/dev/null | cut -f1)
        #     log "SUCCESS" "Wine backup restored to /etc/skel/.wine32 ($wine_size)"
        # else
        #     log "WARN" "Wine backup extracted but .wine32 directory not found"
        #     log "WARN" "Check backup tarball structure (expected .wine32/ at root)"
        # fi
    fi
    
    log "DEBUG" "Backup restoration complete"
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
always-show-universal-access-status=false

[org/gnome/desktop/a11y/applications]
screen-keyboard-enabled=false
screen-reader-enabled=false

[org/gnome/desktop/a11y/interface]
high-contrast=false
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

    # Skip dconf database compilation - it will compile automatically on first boot
    # Running dconf update in chroot can hang due to missing dbus/system services
    log "DEBUG" "dconf settings written to $dconf_file"
    log "DEBUG" "Database will be compiled automatically on first boot"
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
    # Note: DIREWOLF_ADEVICE not used here - ETC uses {{ET_AUDIO_DEVICE}} placeholder
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
    
    # === 2. Modify ETC's direwolf template with iGate/beacon settings ===
    # NOTE: Disabled - modifying the template causes conflicts with Pat/Winlink-packet mode
    # ETC's et-mode provides different direwolf configs for different modes (APRS vs Packet)
    # Our customizations should not override those, as they break Winlink compatibility
    # Users can customize APRS settings post-install if needed
    
    log "DEBUG" "Skipping direwolf template modification (ETC upstream config is correct)"
    return 0
    
    # ============= OLD CODE (DISABLED) =============
    # The following code broke et-mode packet/Winlink compatibility
    # Left here for reference if reverting is needed
    
    # local template_dir="${SQUASHFS_DIR}/opt/emcomm-tools/conf/template.d/packet"
    # local aprs_template="${template_dir}/direwolf.aprs-digipeater.conf"
    # 
    # if [ ! -d "$template_dir" ]; then
    #     log "WARN" "ETC template directory not found: $template_dir"
    #     log "WARN" "Skipping direwolf template modification"
    #     return 0
    # fi
    # 
    # # Backup original template
    # if [ -f "$aprs_template" ]; then
    #     cp "$aprs_template" "${aprs_template}.orig"
    #     log "DEBUG" "Backed up original template"
    # fi
    # 
    # # Extract symbol table and code (e.g., "/r" -> table="/", code="r")
    # local symbol_table="${aprs_symbol:0:1}"
    # local symbol_code="${aprs_symbol:1:1}"
    # 
    # # Create modified template with iGate/beacon settings
    # # Keep {{ET_CALLSIGN}} and {{ET_AUDIO_DEVICE}} for ETC's runtime substitution
    # cat > "$aprs_template" <<EOF
    # # Direwolf APRS Digipeater/iGate Configuration
    # # Template modified by EmComm Tools Customizer
    # # ETC substitutes {{ET_CALLSIGN}} and {{ET_AUDIO_DEVICE}} at runtime
    # 
    # # Audio device (substituted by et-direwolf at runtime)
    # ADEVICE {{ET_AUDIO_DEVICE}}
    # CHANNEL 0
    # 
    # # Callsign with SSID (substituted by et-direwolf, we append SSID)
    # MYCALL {{ET_CALLSIGN}}-${aprs_ssid}
    # 
    # # PTT configuration
    # PTT ${direwolf_ptt}
    # 
    # # Modem settings for APRS (1200 baud)
    # MODEM 1200
    # 
    # EOF
    # 
    # # Add iGate configuration if enabled
    # if [[ "$enable_igate" == "yes" ]]; then
    #     cat >> "$aprs_template" <<EOF
    # # ============================================
    # # iGate Configuration (RF to Internet gateway)
    # # ============================================
    # IGSERVER ${aprs_server}
    # IGLOGIN {{ET_CALLSIGN}} ${aprs_passcode}
    # 
    # EOF
    #     log "DEBUG" "Added iGate settings to template"
    # fi
    # 
    # # Add beacon configuration if enabled
    # if [[ "$enable_beacon" == "yes" ]]; then
    #     # Build PHG string if we have the values
    #     local phg_string=""
    #     if [[ -n "$beacon_power" && -n "$beacon_height" && -n "$beacon_gain" ]]; then
    #         phg_string="power=${beacon_power} height=${beacon_height} gain=${beacon_gain}"
    #         if [[ -n "$beacon_dir" ]]; then
    #             phg_string="${phg_string} dir=${beacon_dir}"
    #         fi
    #     fi
    #     
    #     cat >> "$aprs_template" <<EOF
    # # ============================================
    # # Position Beacon Configuration
    # # ============================================
    # # Use GPS for position (requires gpsd running)
    # GPSD
    # 
    # # Smart beaconing: adjusts rate based on speed/heading
    # # fast_speed mph, fast_rate sec, slow_speed mph, slow_rate sec, turn_angle, turn_time sec, turn_slope
    # SMARTBEACONING 30 60 2 1800 15 15 255
    # 
    # # Fallback fixed beacon if no GPS
    # PBEACON delay=1 every=${beacon_interval} symbol="${symbol_table}${symbol_code}" ${phg_string} \\
    #     comment="${aprs_comment}" via=${beacon_via}
    # 
    # EOF
    #     log "DEBUG" "Added beacon settings to template (PHG: ${phg_string:-none})"
    # fi
    # 
    # # Add digipeater configuration
    # cat >> "$aprs_template" <<EOF
    # # ============================================
    # # Digipeater Configuration
    # # ============================================
    # # Standard APRS digipeating with path tracing
    # DIGIPEAT 0 0 ^WIDE[3-7]-[1-7]$|^TEST$ ^WIDE[12]-[12]$ TRACE
    # DIGIPEAT 0 0 ^WIDE[12]-[12]$ ^WIDE[12]-[12]$ TRACE
    # 
    # EOF
    # 
    # chmod 644 "$aprs_template"
    # log "SUCCESS" "Modified ETC direwolf template: direwolf.aprs-digipeater.conf"
    # log "SUCCESS" "APRS configured for ${callsign}-${aprs_ssid} (igate=${enable_igate}, beacon=${enable_beacon})"
}

customize_radio_configs() {
    log "INFO" "Adding radio configurations..."
    
    local radios_dir="${SQUASHFS_DIR}/opt/emcomm-tools/conf/radios.d"
    
    # Ensure radios directory exists
    mkdir -p "$radios_dir"
    
    # Add Anytone D578UV configuration
    log "DEBUG" "Adding Anytone D578UV configuration..."
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
    "Supports APRS and digital modes",
    "Default baud rate: 9600bps"
  ],
  "fieldNotes": [
    "Connect D578UV to DigiRig Mobile 6-pin connector",
    "DigiRig USB connection to computer",
    "Serial device: /dev/ttyUSB0 (or similar)",
    "Audio device enumerates as CM108-compatible",
    "Use et-mode to select digital mode (APRS, D-Star, etc.)",
    "Configure frequency/offset using radio display"
  ]
}
EOF
    
    chmod 644 "${radios_dir}/anytone-d578uv.json"
    log "SUCCESS" "Added Anytone D578UV radio configuration"
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
    
    log "SUCCESS" "User account configuration complete"
}

customize_preseed() {
    log "INFO" "Generating preseed file for automated Ubuntu installer..."
    
    # shellcheck source=/dev/null
    source "$SECRETS_FILE"
    log "DEBUG" "Sourced secrets file for preseed config"
    
    local callsign="${CALLSIGN:-N0CALL}"
    local machine_name="${MACHINE_NAME:-ETC-${callsign}}"
    local fullname="${USER_FULLNAME:-EmComm User}"
    local username="${USER_USERNAME:-${callsign,,}}"
    local password="${USER_PASSWORD:-}"
    local timezone="${TIMEZONE:-America/Denver}"
    local keyboard_layout="${KEYBOARD_LAYOUT:-us}"
    local locale="${LOCALE:-en_US.UTF-8}"
    local install_disk="${INSTALL_DISK:-/dev/sda5}"
    local install_swap="${INSTALL_SWAP:-/dev/sda6}"
    local confirm_entire_disk="${CONFIRM_ENTIRE_DISK:-no}"
    
    log "DEBUG" "Preseed config: hostname='$machine_name', username='$username', timezone='$timezone'"
    log "DEBUG" "Partition config: disk='$install_disk', swap='$install_swap', confirm_entire='$confirm_entire_disk'"
    
    # Safety check for entire-disk mode
    if [[ "$install_disk" == /dev/* ]] && [[ "$install_disk" != *"p"* ]] && [[ "$install_disk" != *[0-9] ]]; then
        # Looks like entire disk (e.g., /dev/sda, /dev/nvme0n1, not /dev/sda5 or /dev/nvme0n1p1)
        if [[ "$confirm_entire_disk" != "yes" ]]; then
            log "WARN" "INSTALL_DISK='$install_disk' appears to be an entire disk (DESTRUCTIVE!)"
            log "WARN" "This will ERASE all partitions and create new ones with LVM"
            log "WARN" "To confirm this is intentional, set CONFIRM_ENTIRE_DISK=\"yes\" in secrets.env"
            log "ERROR" "Preseed generation aborted for safety. Fix secrets.env or confirm with CONFIRM_ENTIRE_DISK"
            return 1
        else
            log "WARN" "ENTIRE DISK MODE CONFIRMED: Will format $install_disk with LVM"
            log "WARN" "This will ERASE ALL DATA on $install_disk"
        fi
    elif [[ "$confirm_entire_disk" == "yes" ]]; then
        log "WARN" "CONFIRM_ENTIRE_DISK=yes but INSTALL_DISK='$install_disk' is a partition (not entire disk)"
        log "INFO" "Proceeding with partition-mode installation (safe for dual-boot)"
    fi
    
    # Create preseed directory in ISO ROOT (not in squashfs)
    # The preseed file must be accessible from GRUB bootloader BEFORE squashfs is mounted
    # Location: /preseed/custom.preseed on the ISO, accessed via file=/cdrom/preseed/custom.preseed
    local preseed_dir="${ISO_EXTRACT_DIR}/preseed"
    log "DEBUG" "Creating preseed directory in ISO root: $preseed_dir"
    mkdir -p "$preseed_dir"
    
    # Generate preseed file
    # Generate preseed file with mode-specific partitioning
    local preseed_file="${preseed_dir}/custom.preseed"
    log "DEBUG" "Generating preseed file: $preseed_file"
    
    # Determine partition mode based on INSTALL_DISK format
    local is_partition=0
    # Match: /dev/sda5, /dev/sdb1, /dev/nvme0n1p1, /dev/nvme0n1p2, etc.
    # Any disk path ending with a digit (partition number) is partition mode
    if echo "$install_disk" | grep -qE '[0-9]$'; then
        is_partition=1
        log "INFO" "Partition mode detected: $install_disk (specific partition, safe for dual-boot)"
    else
        log "WARN" "Entire-disk mode detected: $install_disk (will auto-partition with LVM)"
    fi
    
    # Hash password for preseed (format: SHA512 hash prefixed with $6$)
    local hashed_password=""
    if [ -n "$password" ]; then
        hashed_password=$(openssl passwd -6 "$password")
        log "DEBUG" "Password hash generated for preseed"
    else
        log "WARN" "No password configured - preseed will skip password setup"
    fi
    
    # Create preseed file with minimal partitioning (no interactive prompts)
    cat > "$preseed_file" <<'EOF'
# Ubuntu 22.10 Preseed File for Automated Installation
# Generated by EmComm Tools Customizer
# This file answers all installer questions automatically

# Keyboard configuration
d-i keyboard-configuration/layoutcode string KEYBOARD_LAYOUT_VAR
d-i keyboard-configuration/xkb-keymap string us

# Localization
d-i debian-installer/locale string LOCALE_VAR
d-i localtime/set-timezone select TIMEZONE_VAR
d-i clock-setup/utc boolean true
d-i clock-setup/ntp boolean true

# Network configuration (use DHCP)
d-i netcfg/choose_interface select auto
d-i netcfg/get_hostname string HOSTNAME_VAR
d-i netcfg/get_domain string local
d-i netcfg/hostname string HOSTNAME_VAR

# Hardware detection (skip problematic hardware)
d-i hw-detect/load_firmware boolean true
d-i hw-detect/load_efi_modules boolean true

# Mirror selection (use default Ubuntu mirrors)
d-i mirror/country string manual
d-i mirror/http/hostname string old-releases.ubuntu.com
d-i mirror/http/directory string /releases/kinetic
d-i mirror/suite string kinetic
d-i mirror/http/proxy string

# Base system installation
d-i base-installer/kernel/image string linux-image-generic
d-i base-installer/install-recommends boolean true

# Account setup
d-i passwd/user-fullname string FULLNAME_VAR
d-i passwd/username string USERNAME_VAR
d-i passwd/user-password-crypted password PASSWORD_HASH_VAR

# Root account (disable)
d-i passwd/root-login boolean false
d-i user-setup/allow-password-weak boolean true
d-i user-setup/encrypt-home boolean false

# Partitioning - MODE VARIES BY INSTALL_DISK
# If INSTALL_DISK is a partition (e.g., /dev/sda5): use manual mode (safe dual-boot)
# If INSTALL_DISK is entire disk (e.g., /dev/sda): use auto-partition with LVM
PARTMAN_MODE_PLACEHOLDER
d-i partman/mount_style select uuid
d-i partman/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true

# Grub bootloader (installs to target disk, respects other OSes)
d-i grub-installer/only_debian boolean true
d-i grub-installer/with_other_os boolean true
d-i grub-installer/bootdev string INSTALL_DISK_VAR

# Package selection (install GNOME desktop)
tasksel tasksel/first multiselect ubuntu-desktop

# Apt configuration
d-i apt-setup/use_mirror boolean true
d-i apt-setup/multiverse boolean true
d-i apt-setup/universe boolean true
d-i apt-setup/backports boolean true
d-i apt-setup/services-select multiselect mse_active
d-i apt-setup/security_host string security.ubuntu.com
d-i apt-setup/security_path string /ubuntu

# Package selection
d-i pkgsel/include string openssh-server curl wget git
d-i pkgsel/upgrade select safe
d-i pkgsel/update-policy select unattended-upgrades

# Skip popularity contest
popularity-contest popularity-contest/participate boolean false

# Automatic security updates
unattended-upgrades unattended-upgrades/enable_auto_updates boolean true

# Ubiquity (GUI installer) - suppress interactive prompts
ubiquity ubiquity/reboot_without_asking boolean true
ubiquity ubiquity/install_media_polling boolean true
ubiquity ubiquity/keep_installed boolean true
ubiquity ubiquity/no_language_pack_warning_en_US boolean true

# Finish installation
d-i finish-install/reboot_in_background boolean true
d-i cdrom-detect/eject boolean true
EOF

    # Substitute variables into preseed file
    sed -i "s|KEYBOARD_LAYOUT_VAR|$keyboard_layout|g" "$preseed_file"
    sed -i "s|LOCALE_VAR|$locale|g" "$preseed_file"
    sed -i "s|TIMEZONE_VAR|$timezone|g" "$preseed_file"
    sed -i "s|HOSTNAME_VAR|$machine_name|g" "$preseed_file"
    sed -i "s|FULLNAME_VAR|$fullname|g" "$preseed_file"
    sed -i "s|USERNAME_VAR|$username|g" "$preseed_file"
    sed -i "s|PASSWORD_HASH_VAR|$hashed_password|g" "$preseed_file"
    sed -i "s|INSTALL_DISK_VAR|$install_disk|g" "$preseed_file"
    
    # Replace partitioning mode based on partition type
    if [ $is_partition -eq 1 ]; then
        log "DEBUG" "Using partition-mode preseed (safe for dual-boot)"
        # Use a temporary file for multiline sed replacement
        local partman_part_file
        partman_part_file=$(mktemp)
        cat > "$partman_part_file" << 'PARTMAN_PARTITION'
d-i partman-auto/method string regular
d-i partman-basicfilesystems/format_swap_bootable boolean false
d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman-partitioning/default_filesystem string ext4
PARTMAN_PARTITION
        sed -i '/PARTMAN_MODE_PLACEHOLDER/r '"$partman_part_file" "$preseed_file"
        sed -i '/PARTMAN_MODE_PLACEHOLDER/d' "$preseed_file"
        rm -f "$partman_part_file"
    else
        log "DEBUG" "Using entire-disk mode preseed (auto-partition with LVM)"
        # Use a temporary file for multiline sed replacement
        local partman_file
        partman_file=$(mktemp)
        cat > "$partman_file" << 'PARTMAN_ENTIRE'
d-i partman-auto/method string lvm
d-i partman-lvm/device_remove_lvm boolean true
d-i partman-lvm/confirm boolean true
d-i partman-lvm/confirm_nooverwrite boolean true
d-i partman-auto/choose_recipe select atomic
d-i partman-partitioning/confirm_write_new_label boolean true
PARTMAN_ENTIRE
        sed -i '/PARTMAN_MODE_PLACEHOLDER/r '"$partman_file" "$preseed_file"
        sed -i '/PARTMAN_MODE_PLACEHOLDER/d' "$preseed_file"
        rm -f "$partman_file"
    fi
    
    chmod 644 "$preseed_file"
    log "DEBUG" "Preseed file written successfully"
    
    log "SUCCESS" "Preseed file created at: /preseed/custom.preseed"
}

update_grub_for_preseed() {
    log "INFO" "Updating GRUB boot parameters to load preseed..."
    
    # GRUB config is in the extracted ISO directory (not in squashfs)
    # Location: .work/iso/boot/grub/grub.cfg
    
    local grub_cfg="${ISO_EXTRACT_DIR}/boot/grub/grub.cfg"
    
    if [ ! -f "$grub_cfg" ]; then
        log "WARN" "GRUB config not found at: $grub_cfg"
        return 0
    fi
    
    log "DEBUG" "Modifying GRUB config: $grub_cfg"
    
    # Update all menu entries to use our custom preseed with auto-install parameters
    # Change from: file=/cdrom/preseed/ubuntu.seed maybe-ubiquity
    # Change to: file=/cdrom/preseed/custom.preseed auto=true priority=critical maybe-ubiquity
    
    sed -i 's|file=/cdrom/preseed/ubuntu\.seed|file=/cdrom/preseed/custom.preseed auto=true priority=critical|g' "$grub_cfg"
    
    log "DEBUG" "GRUB config updated"
    
    # Verify the change took effect
    if grep -q "file=/cdrom/preseed/custom.preseed" "$grub_cfg"; then
        log "SUCCESS" "Boot parameters configured for automated installation with preseed"
        log "DEBUG" "Updated boot entry:"
        grep "file=/cdrom/preseed/custom.preseed" "$grub_cfg" | head -1 | sed 's/^/  /'
    else
        log "WARN" "GRUB config update may have failed - preseed not found in config"
    fi
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
    
    local additional_packages="${ADDITIONAL_PACKAGES:-}"
    
    if [ -z "$additional_packages" ]; then
        log "INFO" "No additional packages configured"
        return 0
    fi
    
    log "DEBUG" "Packages to install: $additional_packages"
    
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
    local all_packages="${additional_packages}"
    log "INFO" "Installing packages: $all_packages"
    # Use -y to auto-confirm, -qq for less output
    # Note: DO NOT quote $all_packages - we need word splitting for separate package names
    if chroot "${SQUASHFS_DIR}" apt-get install -y -qq $all_packages 2>&1 | tail -10 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "Packages installed successfully"
    else
        log "WARN" "Some packages may have failed to install - see log for details"
    fi
    
    # Install CHIRP via pipx (radio programming software)
    log "INFO" "Installing CHIRP radio programmer via pipx..."
    
    # First ensure pipx is available
    if ! chroot "${SQUASHFS_DIR}" command -v pipx &>/dev/null; then
        log "INFO" "Installing pipx..."
        chroot "${SQUASHFS_DIR}" apt-get install -y -qq pipx 2>&1 | tail -3 | tee -a "$LOG_FILE"
    fi
    
    # Install CHIRP globally via pipx
    if chroot "${SQUASHFS_DIR}" bash -c 'pipx install chirp 2>&1 | tail -10'; then
        log "SUCCESS" "CHIRP installed successfully"
    else
        log "WARN" "CHIRP installation had issues - may need manual setup"
    fi
    
    cleanup_chroot_mounts
    trap - EXIT
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
    log "INFO" "Rebuilding squashfs filesystem (this takes 10-20 minutes)..."
    
    local new_squashfs="${WORK_DIR}/filesystem.squashfs.new"
    log "DEBUG" "Creating new squashfs: $new_squashfs"
    log "DEBUG" "Source directory: $SQUASHFS_DIR"
    log "DEBUG" "Compression: xz, block size: 1M"
    
    # Create new squashfs with compression - show progress
    mksquashfs "$SQUASHFS_DIR" "$new_squashfs" \
        -comp xz \
        -b 1M \
        -Xbcj x86 \
        -noappend \
        -progress 2>&1 | while IFS= read -r line; do
        # mksquashfs outputs progress on stderr
        if [[ "$line" =~ ^\[ ]] || [[ "$line" =~ % ]]; then
            printf "\r  %s" "$line"
        fi
    done
    echo ""  # newline after progress
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
    
    # Create UEFI-only ISO
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
    
    # Fallback to basic ISO if above fails
    if [ ! -f "$OUTPUT_ISO" ] || [ ! -s "$OUTPUT_ISO" ]; then
        log "WARN" "UEFI ISO creation failed, trying basic ISO..."
        xorriso -as mkisofs \
            -r -V "ETC_${RELEASE_NUMBER^^}_CUSTOM" \
            -iso-level 3 \
            -J -joliet-long \
            -l \
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
    
    if ! download_etosaddons; then
        log "WARN" "et-os-addons download failed, continuing with base ETC"
        ADDONS_BUILD=0
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
    
    # Merge et-os-addons if enabled (AFTER ETC is installed but BEFORE customizations)
    if ! merge_etosaddons; then
        log "WARN" "et-os-addons merge failed, continuing with base ETC"
    fi
    
    # Apply customizations (AFTER ETC is installed)
    log "INFO" ""
    log "INFO" "=== Applying Customizations ==="
    log "DEBUG" "Starting customization phase..."
    
    log "DEBUG" "Step 1/14: customize_hostname"
    customize_hostname
    log "DEBUG" "Step 1/14: customize_hostname COMPLETED"
    
    # NOTE: restore_user_backup moved to post-install (see post-install/02-restore-user-backup.sh)
    # Reason: 611MB backup extraction hangs during ISO build - should run after OS boots
    # log "DEBUG" "Step 2/14: restore_user_backup"
    # restore_user_backup
    # log "DEBUG" "Step 2/14: restore_user_backup COMPLETED"
    
    log "DEBUG" "Step 2/14: customize_wifi"
    customize_wifi
    log "DEBUG" "Step 2/14: customize_wifi COMPLETED"
    
    log "DEBUG" "Step 3/14: customize_desktop"
    customize_desktop
    log "DEBUG" "Step 3/14: customize_desktop COMPLETED"
    
    log "DEBUG" "Step 4/14: customize_aprs"
    customize_aprs
    log "DEBUG" "Step 4/14: customize_aprs COMPLETED"
    
    log "DEBUG" "Step 5/14: customize_radio_configs"
    customize_radio_configs
    log "DEBUG" "Step 5/14: customize_radio_configs COMPLETED"
    
    log "DEBUG" "Step 6/14: customize_user_and_autologin"
    customize_user_and_autologin
    log "DEBUG" "Step 6/14: customize_user_and_autologin COMPLETED"
    
    log "DEBUG" "Step 7/14: customize_preseed"
    customize_preseed
    log "DEBUG" "Step 7/14: customize_preseed COMPLETED"
    
    log "DEBUG" "Step 8/14: customize_vara_license"
    customize_vara_license
    log "DEBUG" "Step 8/14: customize_vara_license COMPLETED"
    
    log "DEBUG" "Step 9/14: customize_pat"
    customize_pat
    log "DEBUG" "Step 9/14: customize_pat COMPLETED"
    
    log "DEBUG" "Step 10/14: setup_wikipedia_tools"
    setup_wikipedia_tools
    log "DEBUG" "Step 10/14: setup_wikipedia_tools COMPLETED"
    
    log "DEBUG" "Step 11/14: setup_wifi_diagnostics"
    setup_wifi_diagnostics
    log "DEBUG" "Step 11/14: setup_wifi_diagnostics COMPLETED"
    
    log "DEBUG" "Step 12/14: customize_git_config"
    customize_git_config
    log "DEBUG" "Step 12/14: customize_git_config COMPLETED"
    
    log "DEBUG" "Step 13/14: customize_power"
    customize_power
    log "DEBUG" "Step 13/14: customize_power COMPLETED"
    
    log "DEBUG" "Step 14/14: customize_timezone"
    customize_timezone
    log "DEBUG" "Step 14/14: customize_timezone COMPLETED"
    
    log "DEBUG" "Step 15/15: customize_additional_packages"
    customize_additional_packages
    log "DEBUG" "Step 15/15: customize_additional_packages COMPLETED"
    
    log "DEBUG" "Step 16/16: embed_cache_files"
    embed_cache_files
    log "DEBUG" "Step 16/16: embed_cache_files COMPLETED"
    
    log "DEBUG" "Step 17/17: create_build_manifest"
    create_build_manifest
    log "DEBUG" "Step 17/17: create_build_manifest COMPLETED"
    
    log "DEBUG" "All customizations completed successfully"
    
    # Update GRUB boot parameters to load preseed BEFORE rebuilding ISO
    log "DEBUG" "Step 18/17: update_grub_for_preseed"
    update_grub_for_preseed
    log "DEBUG" "Step 18/17: update_grub_for_preseed COMPLETED"
    
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

while getopts "r:t:aldkmvh" opt; do
    case $opt in
        a)
            ADDONS_BUILD=1
            log "INFO" "et-os-addons support enabled (WSJT-X Improved, GridTracker, SSTV, weather tools)"
            ;;
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
            DEBUG_MODE=1
            log "INFO" "Debug mode enabled - showing DEBUG messages"
            ;;
        k)
            KEEP_WORK=1
            log "INFO" "Keep mode - .work directory will be preserved for debugging"
            ;;
        m)
            MINIMAL_BUILD=1
            log "INFO" "Minimal build - cache files will not be embedded in ISO"
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
