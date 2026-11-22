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

# ---------------------------------------------------------------------------
# Versioning, aligned to EmComm Tools Community's release model.
#
# ETC versions a release three ways, all visible in one tag:
#   tag    emcomm-tools-os-community-20261126-r7-final-7.0.2
#   name   2026.11.26.R7
#   semver 7.0.2
#
# This project tracks ETC rather than numbering itself independently, so the
# version is "<the ETC semver we target>-<our revision against it>". That makes
# currency obvious at a glance: if ETC's latest is 7.0.2 and this says 7.0.2-2,
# we are current. If ETC ships 7.1.0 and this still says 7.0.2-2, we are a
# release behind, and check_etc_target_drift() says so during the build.
#
# Bump CUSTOMIZER_REVISION for changes of ours; set ETC_TARGET_VERSION when
# moving to a new ETC release, after reading its notes for things we can drop.
#
# The values themselves live in lib/common.sh, sourced below, so this script
# and apply-to-live-system.sh cannot report different versions for the same
# checkout -- which they did (2.0.0 vs 2.1.0) when each kept its own literal.
# ---------------------------------------------------------------------------
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
VENTOY_MOUNT=""                           # Path to mounted Ventoy USB

# Optional (best-effort) steps that returned non-zero, reported together at the
# end of the customization sequence so a long build's warnings aren't lost in
# scrollback.
declare -a FAILED_OPTIONAL_STEPS=()

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
# Shared customization modules
# ============================================================================
# These are the SAME files apply-to-live-system.sh uses. Every customization
# lives in exactly one place so the ISO build and a live system cannot drift
# apart -- which is precisely how v1 ended up shipping a Hamlib model number
# (301) that does not exist, and an APRS beacon with no position in it.
#
# The modules operate on $ET_ROOT. Here that is the unpacked squashfs; on a
# live system it is "/". lib/common.sh must be sourced after log() above so it
# does not redefine this script's logger.

# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/customize-aprs.sh
source "${SCRIPT_DIR}/lib/customize-aprs.sh"
# shellcheck source=lib/customize-radio.sh
source "${SCRIPT_DIR}/lib/customize-radio.sh"
# shellcheck source=lib/customize-addons.sh
source "${SCRIPT_DIR}/lib/customize-addons.sh"
# shellcheck source=lib/customize-backup.sh
source "${SCRIPT_DIR}/lib/customize-backup.sh"
# shellcheck source=lib/customize-anytone-dmr.sh
source "${SCRIPT_DIR}/lib/customize-anytone-dmr.sh"

# ============================================================================
# Usage
# ============================================================================

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Builds a customized EmComm Tools Community ISO with xorriso/squashfs.
No Cubic GUI required.

The resulting ISO boots to the STANDARD Ubuntu / EmComm Tools installer
walkthrough. It contains no preseed and no automated partitioning -- you
choose the target disk and layout yourself, every time.

RELEASE OPTIONS:
    -r MODE   Release mode (default: latest)
              - stable: Latest formal GitHub Release (production-ready)
              - latest: Most recent git tag (development / beta builds)
              - tag:    Use a specific tag by name (requires -t)
    -t TAG    Specify exact tag name (use -l to list available)
    -l        List available tags and releases, then exit

BUILD OPTIONS:
    -d        Debug mode (show DEBUG log messages on console)
    -k        Keep work directory after build (for iterative debugging)
    -m        Minimal build (omit cache files from ISO to reduce size)
    -v        Verbose mode (enable bash -x debugging)
    -h        Show this help message

OUTPUT OPTIONS:
    --ventoy /path/to/ventoy
              Copy the finished ISO plus helper files to a mounted Ventoy USB.
              This is an ordinary file copy to a mounted filesystem; it does
              not write to a block device.
              Example: sudo ./build-etc-iso.sh -r stable --ventoy /media/\$USER/Ventoy

CONFIGURATION:
    Settings come from secrets.env (copy secrets.env.template to start).
    APRS, radio and et-os-addons settings are shared with
    apply-to-live-system.sh via lib/, so an ISO build and a live system
    produce identical configuration.

DIRECTORY STRUCTURE:
    cache/    Downloaded ISOs and tarballs (persistent)
              - Drop your Ubuntu ISO here to skip the download
              - ETC tarballs and et-os-addons are cached here too
    output/   Generated custom ISOs
    logs/     Build logs (DEBUG messages always written here)

BUILD SIZE:
    By default, cache files (Ubuntu ISO, ETC tarballs) are embedded in the
    output ISO so they are available for the next build on the installed
    system. Use -m for a minimal build that excludes these (saves ~4GB).

PREREQUISITES:
    sudo apt install xorriso squashfs-tools wget curl jq git

EXAMPLES:
    # List available releases (including betas)
    ./build-etc-iso.sh -l

    # Build from the newest stable release
    sudo ./build-etc-iso.sh -r stable

    # Build from a specific beta tag
    sudo ./build-etc-iso.sh -r tag -t v6.1.0-beta2

    # Build and copy to a Ventoy USB stick
    sudo ./build-etc-iso.sh -r stable --ventoy /media/\$USER/Ventoy

REMOVED IN v2.0.0:
    --write-to    dd'd the ISO to a block device, with USB auto-detection.
                  Removed; write the ISO yourself with a tool that shows you
                  the target drive. See CHANGELOG.md.
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

# Say plainly whether the ETC release being built matches the one this
# customizer was written and tested against.
#
# The point is to make staleness impossible to miss. Our customizations are
# tuned to a specific ETC release -- which settings are redundant, which
# installer scripts exist, which paths et-user-backup covers -- and ETC moves
# roughly twice a year. Silently building against an untested release is how
# you end up fighting upstream instead of extending it.
check_etc_target_drift() {
    if [ -z "${VERSION:-}" ] || [ "$VERSION" = "dev" ]; then
        log "WARN" "Could not read a semver from ${RELEASE_TAG}"
        log "WARN" "  This customizer targets ETC ${ETC_TARGET_VERSION}; verify by hand."
        return 0
    fi

    if [ "$VERSION" = "$ETC_TARGET_VERSION" ]; then
        log "SUCCESS" "ETC ${VERSION} matches this customizer's target (v${CUSTOMIZER_VERSION})"
        return 0
    fi

    # Sort the two semvers to say which direction the drift runs.
    local newest
    newest=$(printf '%s\n%s\n' "$VERSION" "$ETC_TARGET_VERSION" | sort -V | tail -1)

    log "WARN" ""
    if [ "$newest" = "$VERSION" ]; then
        log "WARN" "Building ETC ${VERSION}, but this customizer targets ${ETC_TARGET_VERSION}."
        log "WARN" "  ETC is NEWER than what these customizations were tested against."
        log "WARN" "  Read its release notes before trusting this image:"
        log "WARN" "    ${GITHUB_RELEASES_URL}"
        log "WARN" "  Things to re-check: settings ETC now handles natively, new"
        log "WARN" "  et-os-addons installers, and et-user-backup's path list."
        log "WARN" "  Then set ETC_TARGET_VERSION=${VERSION} and reset CUSTOMIZER_REVISION=1."
    else
        log "WARN" "Building ETC ${VERSION}, but this customizer targets ${ETC_TARGET_VERSION}."
        log "WARN" "  You are building an OLDER ETC than this customizer expects."
        log "WARN" "  Customizations written for ${ETC_TARGET_VERSION} may not apply."
    fi
    log "WARN" ""
    return 0
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
    
    check_etc_target_drift

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
    
    # Configure ham radio CAT control (Anytone AT-D578UVIII) via lib/
    log "DEBUG" "Configuring radio CAT control..."
    ET_ROOT="$SQUASHFS_DIR" customize_radio_configs
    
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
    
    # ETC installs et-user-backup to /opt/emcomm-tools/bin/ which may not be in PATH
    # Check both PATH and the known ETC location
    local et_user_backup_cmd=""
    if command -v et-user-backup &> /dev/null; then
        et_user_backup_cmd="et-user-backup"
    elif [ -x "/opt/emcomm-tools/bin/et-user-backup" ]; then
        et_user_backup_cmd="/opt/emcomm-tools/bin/et-user-backup"
        log "DEBUG" "Found et-user-backup at ETC install location"
    else
        log "INFO" "et-user-backup not found - system not running ETC"
        log "INFO" "Skipping fresh backup creation (will use existing backup if available)"
        return 0
    fi
    
    # Check for existing backup from today in home folder (et-user-backup default location)
    # Use SUDO_USER's home if running as root via sudo
    local real_home="${HOME}"
    if [ -n "${SUDO_USER:-}" ] && [ "$EUID" -eq 0 ]; then
        real_home=$(getent passwd "$SUDO_USER" | cut -d: -f6)
        log "DEBUG" "Running as sudo, using real user home: $real_home"
    fi
    
    local today_date
    today_date=$(date +'%Y%m%d')
    local existing_backup
    existing_backup=$(find "$real_home" -maxdepth 1 -name "etc-user-backup-*-${today_date}.tar.gz" -type f 2>/dev/null | head -1)
    
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
    # Run as the real user (not root) so backup goes to their home
    local run_cmd="$et_user_backup_cmd"
    if [ -n "${SUDO_USER:-}" ] && [ "$EUID" -eq 0 ]; then
        run_cmd="sudo -u $SUDO_USER $et_user_backup_cmd"
    fi
    
    # Use timeout to prevent infinite hangs
    if timeout 60 bash -c "yes y | head -1; yes n | head -1" | $run_cmd 2>&1 | grep -v "^$" | tee -a "$LOG_FILE"; then
        log "DEBUG" "et-user-backup command completed"
    else
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            log "WARN" "et-user-backup timed out after 60 seconds"
        else
            log "DEBUG" "et-user-backup exited with code: $exit_code (may still have succeeded)"
        fi
    fi
    
    # Look for the backup file in real user's home directory (where et-user-backup puts it)
    local user_backup_file
    user_backup_file=$(find "$real_home" -maxdepth 1 -name "etc-user-backup-*.tar.gz" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    
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
    # Use SUDO_USER's home if running as root via sudo
    local home_dir="$HOME"
    if [ -n "${SUDO_USER:-}" ] && [ "$EUID" -eq 0 ]; then
        home_dir=$(getent passwd "$SUDO_USER" | cut -d: -f6)
        log "DEBUG" "Running as sudo, looking for backups in real user home: $home_dir"
    fi
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
    
    # Restore user backup (et-user-backup tarball).
    #
    # Contents vary by which et-user-backup made it. R7's stock version covers
    # ten ETC paths; the manifest-driven one from lib/customize-backup.sh adds
    # personal directories. Only the ETC config allowlist below is unpacked
    # into /etc/skel -- see the note there.
    if [ -n "$user_backup" ]; then
        log "INFO" "Restoring user backup: $(basename "$user_backup")"
        
        # Verify it's a valid tarball
        if ! tar tzf "$user_backup" >/dev/null 2>&1; then
            log "ERROR" "Invalid tarball: $user_backup"
            return 1
        fi
        
        # Extract to /etc/skel with timeout and progress.
        local skel_dir="${SQUASHFS_DIR}/etc/skel"
        mkdir -p "$skel_dir"

        # ONLY the ETC configuration subset goes into /etc/skel.
        #
        # /etc/skel is the template for EVERY account created on the installed
        # system, and it ships inside the ISO. Extracting a whole backup here
        # was tolerable when et-user-backup only covered three ETC config
        # directories. It is not now: the manifest in lib/customize-backup.sh
        # adds Documents, notes, .fldigi and .nbems, so an unfiltered extract
        # would bake the operator's documents and message logs into the image
        # and hand a copy to every new user.
        #
        # The full archive is stashed below for restoring into a real $HOME
        # with `./post-install.sh --restore`, which is where personal data
        # belongs.
        local -a skel_paths=(
            ".config/emcomm-tools"
            ".config/partyline"
            ".local/share/emcomm-tools"
            ".local/share/pat"
            ".reticulum"
            ".reticulum-meshchat"
            ".nomadnetwork"
            "BACKUP_ITEMS.lst"
        )

        # Intersect the allowlist with what the archive actually holds: tar
        # errors out on a member that is not present.
        local -a present=()
        local listing p
        listing=$(tar tzf "$user_backup" 2>/dev/null)
        for p in "${skel_paths[@]}"; do
            if grep -qE "^\./?${p}(/|$)" <<< "$listing"; then
                present+=("$p")
            fi
        done

        if [ "${#present[@]}" -eq 0 ]; then
            log "WARN" "Backup holds none of the ETC config paths -- skipping skel restore"
        else
            log "DEBUG" "Extracting ${#present[@]} ETC config paths into /etc/skel..."
            local rc=0
            timeout 300 tar xzf "$user_backup" -C "$skel_dir" \
                --checkpoint=.1000 --checkpoint-action=dot \
                "${present[@]}" >> "$LOG_FILE" 2>&1 || rc=$?

            if [ "$rc" -eq 0 ]; then
                log "SUCCESS" "ETC config restored to /etc/skel (${present[*]})"
            elif [ "$rc" -eq 124 ]; then
                log "WARN" "Extraction timed out (>300s); skel contents may be incomplete"
            else
                log "ERROR" "Backup extraction failed with code $rc"
                return 1
            fi
        fi

        # Stash the FULL archive for restoring personal data into a real home
        # directory later, which `./post-install.sh --restore` does. Everything
        # outside the allowlist above lives only here, never in skel.
        local skel_backups="${SQUASHFS_DIR}/etc/skel/.etc-backups"
        mkdir -p "$skel_backups"
        if cp "$user_backup" "${skel_backups}/$(basename "$user_backup")"; then
            log "SUCCESS" "Full backup staged for post-install restore into \$HOME"
            log "INFO" "  On the installed system: ./post-install.sh --restore"
        else
            log "WARN" "Could not stage the full backup into /etc/skel/.etc-backups"
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
    # Carries the customizer version so `et-system-info` and conky show which
    # build is running. The literal "CUSTOMIZED" must stay -- verify_customizations()
    # greps for exactly that string.
    local custom_description="ETC_${release_number_upper}_${release_type} (CUSTOMIZED ${CUSTOMIZER_VERSION})"
    
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
    
    # All hardcoded as of 7.0.2-1 -- these are no longer secrets.env settings.
    #
    # Every value here now MATCHES ETC R7 rather than fighting it. R7 natively
    # sets brightness to 100% on login, disables automatic brightness, disables
    # dimming, and enables dark mode. The old DIM_SCREEN default of "true" was
    # re-enabling, on every build, the dimming R7 had just turned off.
    #
    # This function still creates /etc/dconf/profile/user, the database cascade
    # that any system-wide dconf default depends on. Keep it even though the
    # values below now mostly agree with R7.
    local color_scheme="prefer-dark"
    local scaling disable_a11y auto_brightness dim_screen
    scaling=$(dconf_double "1.0")
    disable_a11y="yes"
    auto_brightness=$(dconf_bool "no")
    dim_screen=$(dconf_bool "no")

    # 0 disables blanking. GNOME treats these as seconds. A field laptop
    # running a net should not blank its display.
    local screen_blank_timeout=0

    log "DEBUG" "Desktop config: color_scheme=$color_scheme, scaling=$scaling"
    log "DEBUG" "Display config: auto_brightness=$auto_brightness, dim=$dim_screen, blank_timeout=$screen_blank_timeout"
    
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

    # Add accessibility settings if disabled.
    #
    # Two fixes here. The block used to set
    # always-show-universal-access-status=true, which pins the accessibility
    # menu INTO the top bar -- the opposite of what DISABLE_ACCESSIBILITY=yes
    # asks for. And it re-declared [org/gnome/desktop/interface]
    # text-scaling-factor=1.0, which silently overrode the
    # DESKTOP_SCALING_FACTOR written above it, so that setting never worked
    # for anyone who changed it.
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
large-text=false

[org/gnome/terminal/legacy]
menu-accelerator-enabled=true

[org/gnome/settings-daemon/peripherals/keyboard]
remember-numlock-state=true
EOF
    fi

    # Add display/brightness settings.
    #
    # sleep-display-ac / sleep-display-battery are INTEGER keys. They used to
    # be written quoted ('300'), which dconf parses as a string, rejects as a
    # type mismatch, and drops -- so screen blanking was never actually
    # configured by any previous build. Unquoted here.
    cat >> "$dconf_file" <<EOF

# Display and brightness settings
[org/gnome/settings-daemon/plugins/power]
ambient-enabled=${auto_brightness}
idle-dim=${dim_screen}
sleep-display-ac=${screen_blank_timeout}
sleep-display-battery=${screen_blank_timeout}
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



# Configure radio in chroot (called from within install_etc_in_chroot where mounts are already active)

# Configure radio AFTER ETC is installed (as customization step)

# ============================================================================
# Integrate et-os-addons Optional Features
# ============================================================================


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
    
    # Hardcoded. These are build dependencies of the toolchain we ship, not a
    # user preference, so they are no longer read from secrets.env.
    #
    # NOTE: "code" is deliberately NOT in this list. Ubuntu 22.10 has no 'code'
    # package, and this function removes the Microsoft repos a few lines below,
    # so apt can never satisfy it -- the old `apt-get install code` here failed
    # on every single build and the failure was swallowed by the `|| log WARN`
    # on the install line. VS Code is installed from a .deb by install_vscode().
    #
    # Do NOT add anything ETC already ships. R7 provides thunderbird, vlc,
    # python3.11 and rust natively; kiwix since R4; wsjtx/fldigi with PnP
    # wiring. Installing over the top risks a version ETC does not expect.
    local all_user_packages="nodejs npm"

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
    
    # Install packages from standard repos.
    # Guarded: with core_packages now empty and ADDITIONAL_PACKAGES unset, an
    # unguarded `apt-get install` would run with no operands at all.
    local all_packages="${all_user_packages# }"
    if [ -n "$all_packages" ]; then
        log "INFO" "Installing packages: $all_packages"
        # Use -y to auto-confirm, -qq for less output
        # Note: DO NOT quote $all_packages - we need word splitting for separate package names
        if chroot "${SQUASHFS_DIR}" apt-get install -y -qq $all_packages 2>&1 | tail -10 | tee -a "$LOG_FILE"; then
            log "SUCCESS" "Packages installed successfully"
        else
            log "WARN" "Some packages may have failed to install - see log for details"
        fi
    else
        log "DEBUG" "No additional apt packages requested"
    fi

    # CHIRP, VS Code and anytone-cps are installed at BUILD time by their own
    # functions below, not deferred to first boot. The old first-boot approach
    # was removed because every path in it was broken:
    #
    #   - `pip install chirp` installs an unrelated 2013 BIOACOUSTICS package
    #     that happens to own the name "chirp" on PyPI. It is not CHIRP the
    #     radio programmer and never was.
    #   - Microsoft Edge was installed by two competing code paths, one using
    #     `apt-key`, which is deprecated and removed. Edge was never asked for;
    #     ETC ships the Min browser.
    #   - Every step ended in `|| true`, so all of the above failed silently
    #     and the build still reported success.
    #
    # Installing at build time means a failure breaks the build loudly, here,
    # instead of 40 minutes into a field deployment with no network.

    cleanup_chroot_mounts
    trap - EXIT
}

setup_first_login_packages() {
    # Previously 270 lines that installed CHIRP and Microsoft Edge on first
    # login via THREE overlapping mechanisms: two systemd services
    # (emcomm-first-boot.service, emcomm-first-boot-apps.service) and an
    # /etc/profile.d/99-install-chirp-edge.sh that was written twice -- once at
    # build time, then overwritten at runtime by the service. They raced, they
    # duplicated each other's work, and every failure path ended in `|| true`.
    #
    # CHIRP, VS Code and anytone-cps are now installed into the squashfs at
    # build time. All that is left is re-asserting the active radio symlink,
    # which is cheap, idempotent insurance in case anything downstream of the
    # squashfs rewrites radios.d.
    log "INFO" "Setting up first-boot active-radio guard..."

    if [ "${ENABLE_ANYTONE_D578:-yes}" != "yes" ]; then
        log "DEBUG" "ENABLE_ANYTONE_D578=no -- skipping first-boot radio guard"
        return 0
    fi

    # Single profile since 7.0.2-1 -- the commode=0 "PTT only" variant was
    # removed as a duplicate of stock ETC's digirig-mobile-no-cat.
    local default_profile="anytone-d578uv.json"

    local service_script="${SQUASHFS_DIR}/usr/local/bin/emcomm-first-boot.sh"
    local service_file="${SQUASHFS_DIR}/etc/systemd/system/emcomm-first-boot.service"
    mkdir -p "$(dirname "$service_script")" "$(dirname "$service_file")"

    cat > "$service_script" <<FIRSTBOOT_EOF
#!/bin/bash
# Re-assert the active radio symlink if it is missing or dangling.
# customize_radio_configs() already set this at build time; this only covers
# the case where something later replaced radios.d.
set -uo pipefail

RADIOS_DIR="/opt/emcomm-tools/conf/radios.d"
PROFILE="${default_profile}"
LOGFILE="/var/log/emcomm-first-boot.log"

{
    echo "[\$(date)] active-radio guard starting"

    if [ ! -d "\${RADIOS_DIR}" ]; then
        echo "[\$(date)] FAIL \${RADIOS_DIR} does not exist -- ETC not installed?"
        exit 1
    fi

    if [ ! -e "\${RADIOS_DIR}/\${PROFILE}" ]; then
        echo "[\$(date)] FAIL \${PROFILE} missing -- cannot set active radio"
        exit 1
    fi

    # -e follows symlinks, so this is false for a dangling link too.
    if [ -e "\${RADIOS_DIR}/active-radio.json" ]; then
        echo "[\$(date)] OK active-radio.json already resolves; nothing to do"
        exit 0
    fi

    # Relative, deliberately: an absolute link would embed a build path.
    if ln -sfn "\${PROFILE}" "\${RADIOS_DIR}/active-radio.json"; then
        echo "[\$(date)] OK active radio -> \${PROFILE}"
    else
        echo "[\$(date)] FAIL could not link active-radio.json"
        exit 1
    fi
} >> "\${LOGFILE}" 2>&1
FIRSTBOOT_EOF
    chmod 755 "$service_script"

    cat > "$service_file" <<'SERVICE_EOF'
[Unit]
Description=EmComm Tools Customizer active-radio guard
After=local-fs.target
ConditionPathExists=/opt/emcomm-tools/conf/radios.d

[Service]
Type=oneshot
ExecStart=/usr/local/bin/emcomm-first-boot.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE_EOF

    setup_chroot_mounts
    trap 'cleanup_chroot_mounts' EXIT
    # No tee here: piping a chrooted command through tee under sudo has hung
    # this build before. Append to the log directly.
    if chroot "${SQUASHFS_DIR}" systemctl enable emcomm-first-boot.service 2>&1 | sed 's/^/  [systemctl] /' >> "$LOG_FILE"; then
        log "SUCCESS" "active-radio guard service enabled (target: ${default_profile})"
    else
        log "WARN" "Could not enable emcomm-first-boot.service"
    fi
    cleanup_chroot_mounts
    trap - EXIT
}

# ============================================================================
# Build-time application installs
# ============================================================================
# Each of these runs INSIDE the chroot and returns non-zero on real failure, so
# main() can abort the build rather than shipping an ISO that silently lacks
# the application. That is the opposite of the old first-boot scripts, which
# swallowed every error.

install_vscode() {
    if [ "${ENABLE_VSCODE:-yes}" != "yes" ]; then
        log "DEBUG" "ENABLE_VSCODE=no -- skipping VS Code"
        return 0
    fi

    log "INFO" "Installing Visual Studio Code from .deb..."

    # Ubuntu 22.10 has no 'code' package and this build removes the Microsoft
    # apt repos, so a .deb is the only way in. Prefer a local file (the user
    # usually already has one) and fall back to downloading the current stable.
    local deb_src="${VSCODE_DEB:-}"
    local staged="${SQUASHFS_DIR}/tmp/code.deb"

    if [ -n "$deb_src" ] && [ -f "$deb_src" ]; then
        log "INFO" "  Using local .deb: $deb_src"
        cp "$deb_src" "$staged" || { log "ERROR" "Could not stage $deb_src"; return 1; }
    else
        if [ -n "$deb_src" ]; then
            log "WARN" "VSCODE_DEB set but not found: $deb_src -- falling back to download"
        fi
        local url="https://update.code.visualstudio.com/latest/linux-deb-x64/stable"
        log "INFO" "  Downloading VS Code from $url"
        if ! wget -q --show-progress --timeout=60 --tries=3 -O "$staged" "$url"; then
            log "ERROR" "VS Code download failed"
            rm -f "$staged"
            return 1
        fi
    fi

    setup_chroot_mounts
    trap 'cleanup_chroot_mounts' EXIT

    # dpkg then `apt-get -f install` to pull the .deb's dependencies, which is
    # the documented way to install a standalone .deb without a repo.
    local rc=0
    chroot "${SQUASHFS_DIR}" /bin/bash -c '
        set -o pipefail
        export DEBIAN_FRONTEND=noninteractive
        dpkg -i /tmp/code.deb || apt-get install -y -f
        command -v code >/dev/null
    ' 2>&1 | tail -15 >> "$LOG_FILE" || rc=$?

    rm -f "$staged"
    cleanup_chroot_mounts
    trap - EXIT

    if [ "$rc" -ne 0 ]; then
        log "ERROR" "VS Code install failed (rc=$rc)"
        return 1
    fi

    # dpkg-query, not `code --version`: the chroot mounts are already torn down
    # by this point, and VS Code refuses to run as root without extra flags.
    local ver
    ver=$(chroot "${SQUASHFS_DIR}" dpkg-query -W -f='${Version}' code 2>/dev/null || echo "unknown")
    log "SUCCESS" "VS Code installed (version ${ver})"
    return 0
}

install_gh() {
    if [ "${ENABLE_GH_CLI:-yes}" != "yes" ]; then
        log "DEBUG" "ENABLE_GH_CLI=no -- skipping GitHub CLI"
        return 0
    fi

    log "INFO" "Installing GitHub CLI..."

    # Why the .deb and not apt: kinetic universe has gh 2.14.4+dfsg1-1, from
    # mid-2022. For a tool whose entire job is talking to a remote API that has
    # moved on considerably since, the current release is worth 15MB. apt is
    # the fallback, so an offline or rate-limited build still gets a working gh.
    #
    # gh also solves git credentials on the installed system by itself:
    #   gh auth login && gh auth setup-git
    # registers gh as git's credential helper, so `git push` works in a plain
    # terminal. That is deliberately NOT done at build time -- it would bake a
    # personal token into a shared ISO.
    #
    # ALWAYS the latest release, resolved from the API. There is no pinned
    # GH_CLI_VERSION, and a pin here was worse than useless: the URL was
    #   /releases/latest/download/gh_<pinned>_linux_amd64.deb
    # and GitHub's /latest/download/ path only serves filenames belonging to
    # the CURRENT release. The pin therefore 404s the moment gh publishes a new
    # version -- silently falling back to apt's three-year-old build. Verified:
    # the same URL with any non-current version returns 404.
    local staged="${SQUASHFS_DIR}/tmp/gh.deb"

    setup_chroot_mounts
    trap 'cleanup_chroot_mounts' EXIT

    local url="" gh_tag=""
    local api="https://api.github.com/repos/cli/cli/releases/latest"
    local meta
    if meta=$(curl -sf --max-time 30 "$api" 2>/dev/null); then
        url=$(jq -r '.assets[]? | select(.name | test("linux_amd64\\.deb$")) | .browser_download_url' <<< "$meta" | head -1)
        gh_tag=$(jq -r '.tag_name // empty' <<< "$meta")
    fi

    if [ -z "$url" ] || [ "$url" = "null" ]; then
        log "WARN" "Could not resolve the latest gh .deb from the API -- using apt"
        url=""
    else
        log "INFO" "  Latest gh release: ${gh_tag:-unknown}"
    fi

    local rc=0
    if [ -n "$url" ] && wget -q --timeout=60 --tries=3 -O "$staged" "$url"; then
        chroot "${SQUASHFS_DIR}" /bin/bash -c '
            set -o pipefail
            export DEBIAN_FRONTEND=noninteractive
            dpkg -i /tmp/gh.deb || apt-get install -y -f
            command -v gh >/dev/null
        ' >> "$LOG_FILE" 2>&1 || rc=$?
    else
        [ -n "$url" ] && log "WARN" "gh .deb download failed"
        log "WARN" "  Falling back to apt, which on kinetic is gh 2.14.4 (mid-2022)"
        rc=1
    fi

    if [ "$rc" -ne 0 ]; then
        rc=0
        chroot "${SQUASHFS_DIR}" /bin/bash -c '
            set -o pipefail
            export DEBIAN_FRONTEND=noninteractive
            apt-get install -y -qq gh
            command -v gh >/dev/null
        ' >> "$LOG_FILE" 2>&1 || rc=$?
    fi

    rm -f "$staged"
    cleanup_chroot_mounts
    trap - EXIT

    if [ "$rc" -ne 0 ]; then
        log "WARN" "GitHub CLI install failed -- continuing without it"
        return 1
    fi

    local ver
    ver=$(chroot "${SQUASHFS_DIR}" dpkg-query -W -f='${Version}' gh 2>/dev/null || echo "unknown")
    log "SUCCESS" "GitHub CLI installed (version ${ver})"
    log "INFO" "  On the installed system: gh auth login && gh auth setup-git"
    return 0
}

install_chirp() {
    if [ "${ENABLE_CHIRP:-yes}" != "yes" ]; then
        log "DEBUG" "ENABLE_CHIRP=no -- skipping CHIRP"
        return 0
    fi

    local ref="${CHIRP_GIT_REF:-master}"
    log "INFO" "Installing CHIRP from the official git repo (ref: ${ref})..."

    # Why from git, and not any of the three obvious alternatives:
    #
    #   PyPI      -- `pip install chirp` is an unrelated 2013 bioacoustics
    #                package. This is what the old code did, on all 3 paths.
    #   chirpmyradio.com archive -- serves HTTP 403 to every non-browser
    #                request (Cloudflare), so a build cannot fetch the wheel.
    #   apt       -- kinetic ships CHIRP 20200227, six years stale, and it
    #                predates support for most current radios.
    #
    # A venv with --system-site-packages is used rather than pipx because
    # kinetic's pipx is 1.0.0 and its --system-site-packages handling is
    # unreliable. The system wxPython (python3-wxgtk4.0) MUST be visible to the
    # venv: building wxPython from source via pip is not viable here.

    setup_chroot_mounts
    trap 'cleanup_chroot_mounts' EXIT

    local rc=0
    chroot "${SQUASHFS_DIR}" /bin/bash -c "
        set -euo pipefail
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -y -qq python3-wxgtk4.0 python3-venv python3-pip git
        rm -rf /opt/chirp-venv
        python3 -m venv --system-site-packages /opt/chirp-venv
        /opt/chirp-venv/bin/pip install --upgrade pip wheel setuptools
        /opt/chirp-venv/bin/pip install 'git+https://github.com/kk7ds/chirp.git@${ref}'
        ln -sf /opt/chirp-venv/bin/chirp /usr/local/bin/chirp
        /opt/chirp-venv/bin/chirp --help >/dev/null
    " 2>&1 | tail -20 >> "$LOG_FILE" || rc=$?

    cleanup_chroot_mounts
    trap - EXIT

    if [ "$rc" -ne 0 ]; then
        log "ERROR" "CHIRP install failed (rc=$rc) -- see $LOG_FILE"
        return 1
    fi

    # Desktop entry: CHIRP's own packaging does not provide one.
    mkdir -p "${SQUASHFS_DIR}/usr/share/applications"
    cat > "${SQUASHFS_DIR}/usr/share/applications/chirp.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=CHIRP
GenericName=Radio programming
Comment=Program memory channels on amateur radios
Exec=/usr/local/bin/chirp
Icon=utilities-terminal
Terminal=false
Categories=HamRadio;Utility;
Keywords=chirp;radio;programming;memory;
EOF

    log "SUCCESS" "CHIRP installed to /opt/chirp-venv (ref ${ref})"
    log "INFO" "  NOTE: CHIRP does not support AnyTone DMR radios -- use anytone-cps for the D578/D890"
    return 0
}

install_anytone_cps() {
    if [ "${ENABLE_ANYTONE_CPS:-yes}" != "yes" ]; then
        log "DEBUG" "ENABLE_ANYTONE_CPS=no -- skipping anytone-cps"
        return 0
    fi

    log "INFO" "Building anytone-cps (xbenkozx)..."

    # Open-source CPS for AnyTone DMR radios. This matters because CHIRP does
    # not support AnyTone DMR radios at all, so without this there is no Linux
    # path to program the D578UVIII or D890UV.
    #
    # ALPHA software: D878UVII is the tested target; D890UV is listed but
    # untested upstream. A build failure here is therefore NOT fatal to the
    # ISO -- we warn and continue, because the radio still works for CAT and
    # packet without its programming software. Every other install in this
    # section is fatal; this one is deliberately not.

    setup_chroot_mounts
    trap 'cleanup_chroot_mounts' EXIT

    local rc=0
    chroot "${SQUASHFS_DIR}" /bin/bash -c '
        set -euo pipefail
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -y -qq git cmake build-essential \
            qtbase5-dev qttools5-dev-tools libqt5serialport5-dev pkg-config
        rm -rf /usr/local/src/anytone-cps
        git clone --depth 1 https://github.com/xbenkozx/anytone-cps.git \
            /usr/local/src/anytone-cps
        cd /usr/local/src/anytone-cps
        cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
        cmake --build build -j"$(nproc)"
        # Upstream has no install target defined at all stages of development,
        # so fall back to copying whatever executable the build produced.
        cmake --install build 2>/dev/null || {
            bin=$(find build -maxdepth 2 -type f -executable \
                    -name "*anytone*" -o -maxdepth 2 -type f -executable -name "*cps*" \
                  | head -1)
            [ -n "$bin" ] || { echo "no executable produced"; exit 1; }
            install -m 755 "$bin" /usr/local/bin/anytone-cps
        }
        command -v anytone-cps >/dev/null || [ -x /usr/local/bin/anytone-cps ]
    ' 2>&1 | tail -25 >> "$LOG_FILE" || rc=$?

    cleanup_chroot_mounts
    trap - EXIT

    if [ "$rc" -ne 0 ]; then
        log "WARN" "anytone-cps build failed (rc=$rc) -- continuing without it."
        log "WARN" "  It is alpha upstream; the ISO is still fully usable."
        log "WARN" "  Build it later on the installed system from /usr/local/src/anytone-cps."
        return 0
    fi

    ET_ROOT="$SQUASHFS_DIR" customize_anytone_cps_launcher

    log "SUCCESS" "anytone-cps built and installed"
    return 0
}

install_hamlib_anytone() {
    if [ "${ENABLE_HAMLIB_ANYTONE:-yes}" != "yes" ]; then
        log "WARN" "ENABLE_HAMLIB_ANYTONE=no -- the D578UVIII profiles will NOT work."
        log "WARN" "  Stock Hamlib has no AnyTone backend, so rigctld rejects model 37001."
        return 0
    fi

    log "INFO" "Building the AnyTone Hamlib backend into the ISO (this takes ~10 min)..."

    # THIS IS THE FIX FOR THE HEADLINE BUG. customize_radio_configs() writes
    # radio profiles pinned to Hamlib model 37001 (RIG_MODEL_ATD578UVIII), but
    # nothing in this build had ever installed a Hamlib that knows that model.
    # ETC ships stock Hamlib 4.5, which has no AnyTone backend whatsoever, so
    # every ISO this script produced had working-looking radio profiles and no
    # CAT control and no PTT.
    #
    # build-hamlib-anytone.sh is run INSIDE the chroot rather than
    # reimplemented here, so the ISO and the live system get byte-identical
    # Hamlib treatment -- including the symlink manifest that makes --revert
    # work on the installed system.

    local staged_repo="${SQUASHFS_DIR}/tmp/customizer"
    mkdir -p "$staged_repo/lib"
    cp "${SCRIPT_DIR}/build-hamlib-anytone.sh" "$staged_repo/" \
        || { log "ERROR" "Could not stage build-hamlib-anytone.sh"; return 1; }
    cp "${SCRIPT_DIR}/lib/common.sh" "$staged_repo/lib/" \
        || { log "ERROR" "Could not stage lib/common.sh"; return 1; }
    chmod +x "$staged_repo/build-hamlib-anytone.sh"

    setup_chroot_mounts
    trap 'cleanup_chroot_mounts' EXIT

    local rc=0
    chroot "${SQUASHFS_DIR}" /bin/bash -c '
        set -uo pipefail
        export DEBIAN_FRONTEND=noninteractive
        cd /tmp/customizer
        ./build-hamlib-anytone.sh
    ' 2>&1 | tail -30 >> "$LOG_FILE" || rc=$?

    # Confirm the backend is really there. The script self-verifies, but this
    # build has shipped a broken Hamlib before, so check independently.
    local models=""
    if [ "$rc" -eq 0 ]; then
        models=$(chroot "${SQUASHFS_DIR}" /bin/bash -c 'rigctl -l 2>/dev/null' | grep -i anytone || true)
    fi

    rm -rf "$staged_repo"
    cleanup_chroot_mounts
    trap - EXIT

    if [ "$rc" -ne 0 ]; then
        log "ERROR" "Hamlib AnyTone build failed (rc=$rc) -- see $LOG_FILE"
        log "ERROR" "  Without it the D578UVIII has no CAT control and no PTT."
        log "ERROR" "  Set ENABLE_HAMLIB_ANYTONE=no to build an ISO anyway."
        return 1
    fi

    if [ -z "$models" ]; then
        log "ERROR" "Hamlib built, but no AnyTone model is registered."
        log "ERROR" "  rigctld would reject model ${ANYTONE_MODEL_ID:-37001}."
        return 1
    fi

    log "SUCCESS" "AnyTone Hamlib backend present in ISO:"
    while IFS= read -r line; do
        [ -n "$line" ] && log "INFO" "    $(tr -s ' ' <<< "$line")"
    done <<< "$models"
    return 0
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





# install_kiwix() was REMOVED. ETC has shipped kiwix natively since R4, and
# installing kiwix-tools over the top risked a different version than the one
# ETC's own launcher and et-index integration expect. setup_wikipedia_tools()
# is separate and still needed -- it builds small targeted ZIM files, which is
# not what ETC's bundled kiwix collections do.

# ---------------------------------------------------------------------------
# chroot-mount wrappers.
#
# These four installers assume the chroot is already mounted. main() used to
# wrap each one in its own setup/cleanup_chroot_mounts + trap, inline, four
# times over. Wrapping them here keeps main()'s step table uniform -- every
# entry is just a function name -- and guarantees the mounts are torn down
# even when the installer returns non-zero.
# ---------------------------------------------------------------------------
_with_chroot_mounts() {
    local fn="$1" rc=0
    setup_chroot_mounts
    trap 'cleanup_chroot_mounts' EXIT
    "$fn" || rc=$?
    cleanup_chroot_mounts
    trap - EXIT
    return "$rc"
}

# et-os-addons now EXECS upstream's installers in the chroot rather than just
# copying files, so it needs /dev, /proc, /sys and a resolv.conf for the
# downloads. It did not need mounts when it was a pure file copy.
integrate_etosaddons_wrapped() { _with_chroot_mounts integrate_etosaddons_features; }


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
ETC Semver: ${VERSION:-unknown}  (this customizer targets ${ETC_TARGET_VERSION})
Customizer: ${CUSTOMIZER_VERSION}
Ubuntu ISO: $UBUNTU_ISO_FILE
Git Revision: $(git -C "$SCRIPT_DIR" describe --tags --always --dirty 2>/dev/null || echo 'unknown')

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
    # Final verification of all critical customizations BEFORE spending 20-40
    # minutes compressing a squashfs we are going to throw away.
    #
    # Three of the old checks tested for things this build DELIBERATELY no
    # longer does, so they fired on every single run and trained the reader to
    # ignore the whole section:
    #
    #   - a "wrapper-rigctld.sh patched for Anytone preservation" marker.
    #     lib/customize-radio.sh documents at length why that patch is wrong:
    #     it guarded do_full_auto(), which is never called. Always ERROR.
    #   - /etc/profile.d/99-install-chirp-edge.sh, which no longer exists
    #     because CHIRP is installed at build time and Edge was dropped.
    #   - /etc/udev/rules.d/99-emcomm-tools-cat.rules, which customize-radio
    #     deliberately does not create; the stock DigiRig rule already maps
    #     /dev/et-cat, and the 99- rule let an unrelated USB serial device
    #     steal it.
    log "INFO" "=== VERIFYING CRITICAL CUSTOMIZATIONS ==="

    local errors=0
    local warnings=0
    local etc_conf="${SQUASHFS_DIR}/opt/emcomm-tools/conf"

    _vc_ok()   { log "SUCCESS" "  [ OK ] $1"; }
    _vc_err()  { log "ERROR"   "  [FAIL] $1"; errors=$((errors + 1)); }
    _vc_warn() { log "WARN"    "  [WARN] $1"; warnings=$((warnings + 1)); }

    # --- 1. The AnyTone Hamlib backend ------------------------------------
    # This is the check that would have caught the headline bug: every ISO
    # this script built had D578UVIII radio profiles pinned to Hamlib model
    # 37001 and a Hamlib that had never heard of model 37001.
    log "INFO" "Checking AnyTone Hamlib backend..."
    if [ "${ENABLE_HAMLIB_ANYTONE:-yes}" != "yes" ]; then
        _vc_warn "ENABLE_HAMLIB_ANYTONE=no -- D578UVIII will have no CAT and no PTT"
    else
        local anytone_models=""
        anytone_models=$(chroot "${SQUASHFS_DIR}" /bin/bash -c 'rigctl -l 2>/dev/null' 2>/dev/null \
                         | grep -i anytone || true)
        if [ -n "$anytone_models" ]; then
            _vc_ok "Hamlib knows AnyTone: $(head -1 <<< "$anytone_models" | tr -s ' ')"
        else
            _vc_err "Hamlib has NO AnyTone backend -- rigctld will reject model 37001"
        fi
    fi

    # --- 2. Radio profiles and the active symlink -------------------------
    log "INFO" "Checking radio profiles..."
    local anytone_config="${etc_conf}/radios.d/anytone-d578uv.json"
    if [ -f "$anytone_config" ]; then
        if command -v jq >/dev/null 2>&1 && ! jq -e . "$anytone_config" >/dev/null 2>&1; then
            _vc_err "anytone-d578uv.json exists but is not valid JSON"
        else
            _vc_ok "anytone-d578uv.json present and parses"
        fi
    else
        _vc_err "anytone-d578uv.json NOT found"
    fi

    local active_radio="${etc_conf}/radios.d/active-radio.json"
    if [ -L "$active_radio" ]; then
        local target
        target=$(readlink "$active_radio")
        # Must be RELATIVE: an absolute link would embed the build machine's
        # squashfs path and dangle on the installed system.
        case "$target" in
            /*) _vc_err "active-radio.json is an ABSOLUTE symlink ($target) -- will dangle once installed" ;;
            *anytone*)
                if [ -e "$active_radio" ]; then
                    _vc_ok "active-radio.json -> $target"
                else
                    _vc_err "active-radio.json -> $target, which does not resolve"
                fi
                ;;
            *) _vc_warn "active-radio.json -> $target (not an AnyTone profile)" ;;
        esac
    else
        _vc_err "active-radio.json is not a symlink"
    fi

    # --- 3. D890UV Bluetooth TNC ------------------------------------------
    if [ "${ENABLE_ANYTONE_D890_TNC:-yes}" = "yes" ]; then
        log "INFO" "Checking D890UV Bluetooth TNC..."
        if [ -f "${etc_conf}/radios.d/anytone-d890.bt.json" ]; then
            _vc_ok "anytone-d890.bt.json present"
        else
            _vc_warn "anytone-d890.bt.json missing"
        fi
        if [ -x "${SQUASHFS_DIR}/opt/emcomm-tools/bin/et-anytone-d890" ]; then
            _vc_ok "et-anytone-d890 installed and executable"
        else
            _vc_warn "et-anytone-d890 missing or not executable"
        fi
    fi

    # --- 4. Applications --------------------------------------------------
    log "INFO" "Checking applications..."
    if [ "${ENABLE_VSCODE:-yes}" = "yes" ]; then
        if [ -x "${SQUASHFS_DIR}/usr/bin/code" ] || [ -x "${SQUASHFS_DIR}/usr/share/code/bin/code" ]; then
            _vc_ok "VS Code installed"
        else
            _vc_err "VS Code NOT installed (apt can never supply 'code' on 22.10)"
        fi
    fi

    if [ "${ENABLE_CHIRP:-yes}" = "yes" ]; then
        if [ -x "${SQUASHFS_DIR}/opt/chirp-venv/bin/chirp" ]; then
            _vc_ok "CHIRP installed in /opt/chirp-venv"
        else
            _vc_err "CHIRP NOT installed"
        fi
    fi

    if [ "${ENABLE_ANYTONE_CPS:-yes}" = "yes" ]; then
        # Best-effort upstream, so only a warning.
        if [ -x "${SQUASHFS_DIR}/usr/local/bin/anytone-cps" ]; then
            _vc_ok "anytone-cps installed"
        else
            _vc_warn "anytone-cps not built (alpha upstream; ISO still usable)"
        fi
    fi

    # --- 5. Release branding ----------------------------------------------
    log "INFO" "Checking release info..."
    local lsb_release="${SQUASHFS_DIR}/etc/lsb-release"
    if [ -f "$lsb_release" ]; then
        if grep -q "CUSTOMIZED" "$lsb_release"; then
            _vc_ok "Release: $(grep DISTRIB_DESCRIPTION "$lsb_release" | cut -d= -f2 | tr -d '"')"
        else
            _vc_err "lsb-release does not contain 'CUSTOMIZED'"
        fi
    else
        _vc_err "lsb-release not found"
    fi

    # --- 6. The active-radio guard service --------------------------------
    log "INFO" "Checking first-boot guard..."
    if [ -f "${SQUASHFS_DIR}/etc/systemd/system/emcomm-first-boot.service" ]; then
        _vc_ok "emcomm-first-boot.service present"
    else
        _vc_warn "emcomm-first-boot.service not found"
    fi

    # --- 7. Secrets must NOT leak into a shareable ISO --------------------
    # embed_cache_files() deliberately copies secrets.env into the ISO so the
    # installed system can rebuild itself. That is useful and intended, but it
    # means the ISO contains a Winlink password and WiFi PSKs -- worth saying
    # out loud once per build rather than discovering it after sharing it.
    if [ -f "${SQUASHFS_DIR}/opt/emcomm-customizer-cache/secrets.env" ]; then
        log "WARN" "  [NOTE] This ISO embeds secrets.env (WiFi PSK, Winlink password)."
        log "WARN" "         Do not share it. Use -m for a minimal ISO without it."
    fi

    # --- Summary ----------------------------------------------------------
    log "INFO" ""
    log "INFO" "=== VERIFICATION SUMMARY ==="
    if [ $errors -gt 0 ]; then
        log "ERROR" "  ERRORS:   $errors"
    else
        log "SUCCESS" "  ERRORS:   0"
    fi
    if [ $warnings -gt 0 ]; then
        log "WARN" "  WARNINGS: $warnings (review above)"
    else
        log "SUCCESS" "  WARNINGS: 0"
    fi
    log "INFO" ""

    # Fail BEFORE rebuilding the squashfs. The old version returned 0
    # unconditionally with "Build will continue but ISO may not work
    # correctly", which is the worst of both worlds: 40 minutes of
    # compression, then an ISO known to be broken. An error here means
    # something required for radio operation is missing.
    if [ $errors -gt 0 ]; then
        log "ERROR" "Refusing to build an ISO with $errors critical error(s)."
        log "ERROR" "Fix the above, or re-run with the relevant ENABLE_* set to 'no'"
        log "ERROR" "if you genuinely want an ISO without that capability."
        return 1
    fi

    log "SUCCESS" "All critical customizations verified"
    return 0
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
    # Hardcoded as of 7.0.2-1: this is a build-tooling detail, not operator
    # configuration, so it no longer comes from secrets.env.
    #
    # zstd is the right default by a wide margin here. xz saves maybe 10% on an
    # image that is already mostly incompressible (the embedded Ubuntu ISO and
    # the offline map tilesets) in exchange for roughly 80 extra minutes.
    local compression="zstd"
    local time_estimate="15-25 minutes"

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
    
    # Rebuild ISO with xorriso for hybrid BIOS/UEFI boot
    # Using -iso-level 3 to allow files over 4GB (embedded cache makes squashfs large)
    log "INFO" "Creating hybrid BIOS/UEFI bootable ISO image..."
    log "DEBUG" "Output ISO: $OUTPUT_ISO"
    log "DEBUG" "ISO label: ETC_${RELEASE_NUMBER^^}_CUSTOM"
    
    # Create proper EFI boot image from existing bootloaders
    local efi_boot_img="$ISO_EXTRACT_DIR/boot/grub/efi.img"
    local efi_dir="$ISO_EXTRACT_DIR/EFI/boot"
    
    if [ -d "$efi_dir" ] && [ -f "$efi_dir/bootx64.efi" ]; then
        log "INFO" "Creating EFI boot image from existing bootloaders..."
        
        # Calculate required size for FAT image (EFI files + overhead)
        local efi_size
        efi_size=$(du -sk "$efi_dir" | cut -f1)
        # Add 50% overhead and round up to 2880 sectors minimum (1.44MB floppy)
        local fat_size=$(( (efi_size * 3 / 2 + 1440) / 1440 * 1440 ))
        [ "$fat_size" -lt 2880 ] && fat_size=2880
        
        log "DEBUG" "EFI directory size: ${efi_size}KB, FAT image size: ${fat_size} sectors"
        
        mkdir -p "$(dirname "$efi_boot_img")"
        
        # Create FAT12/16 filesystem image
        dd if=/dev/zero of="$efi_boot_img" bs=512 count=$fat_size 2>/dev/null
        /sbin/mkfs.vfat -F 12 "$efi_boot_img" >/dev/null 2>&1 || mkfs.vfat -F 12 "$efi_boot_img" >/dev/null 2>&1
        
        # Mount and copy EFI bootloaders
        local efi_mount="/tmp/efi_mount_$$"
        mkdir -p "$efi_mount"
        sudo mount -o loop "$efi_boot_img" "$efi_mount"
        sudo mkdir -p "$efi_mount/EFI/boot"
        sudo cp -v "$efi_dir"/*.efi "$efi_mount/EFI/boot/" 2>/dev/null || true
        sudo cp -v "$efi_dir"/*.EFI "$efi_mount/EFI/boot/" 2>/dev/null || true
        # Also copy grub.cfg if it exists in EFI directory
        [ -f "$efi_dir/grub.cfg" ] && sudo cp -v "$efi_dir/grub.cfg" "$efi_mount/EFI/boot/"
        sudo umount "$efi_mount"
        rmdir "$efi_mount"
        
        log "SUCCESS" "EFI boot image created"
    else
        log "WARN" "No EFI bootloaders found at $efi_dir, creating empty EFI image"
        mkdir -p "$(dirname "$efi_boot_img")"
        dd if=/dev/zero of="$efi_boot_img" bs=512 count=2880 2>/dev/null
    fi
    
    # Force UEFI-only boot (no legacy BIOS support)
    log "INFO" "Creating UEFI-only bootable ISO (no legacy BIOS)..."
    
    # UEFI-only boot with proper GPT partition table
    xorriso -as mkisofs \
        -r -V "ETC_${RELEASE_NUMBER^^}_CUSTOM" \
        -iso-level 3 \
        -J -joliet-long \
        -l \
        -e boot/grub/efi.img \
        -no-emul-boot \
        -append_partition 2 0xef "$efi_boot_img" \
        -partition_offset 16 \
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
# Ventoy does not use the ISO's grub.cfg, so booting a plain ISO from Ventoy
# just gets Ventoy's own menu. That is fine -- the installer walkthrough is what
# we want.
#
# v1 used this path to inject `automatic-ubiquity only-ubiquity` and a
# preseed.cfg via Ventoy's auto_install plugin, which reproduced the automated
# partitioning through a second door even after the ISO's own preseed was gone.
# That is deliberately not done any more: no auto_install block, no preseed,
# no conf_replace of loopback.cfg.

generate_ventoy_config() {
    log "INFO" "Generating Ventoy helper files..."

    local iso_filename
    iso_filename=$(basename "$OUTPUT_ISO")
    local ventoy_dir="${OUTPUT_DIR}/ventoy"
    mkdir -p "$ventoy_dir"

    # Menu-mode preference only. No auto_install, no preseed template.
    cat > "${ventoy_dir}/ventoy.json" <<EOF
{
    "control": [
        { "VTOY_DEFAULT_MENU_MODE": "1" }
    ]
}
EOF
    log "DEBUG" "Generated ventoy.json (no auto-install)"

    cat > "${ventoy_dir}/README.txt" <<EOF
============================================================
   EmComm Tools Custom ISO - Ventoy Setup (OPTIONAL)
============================================================

You do not need any of these files to use this ISO. Copying the
.iso onto a Ventoy USB stick is enough -- Ventoy will list it in
its boot menu.

WHAT CHANGED IN v2.0.0

Earlier versions shipped a ventoy.json auto_install block and a
preseed.cfg here, which drove the Ubuntu installer unattended and
partitioned the disk without asking. That has been removed.

You now get the standard Ubuntu / EmComm Tools installer, and you
choose the target disk and partition layout yourself.

HOW TO USE

  1. Install Ventoy on a USB stick (once):  https://www.ventoy.net
  2. Copy ${iso_filename} to the stick.
  3. Boot the stick, pick the ISO from Ventoy's menu.
  4. Run through the installer as normal.

Optional: copy ventoy.json to the /ventoy/ directory on the stick
if you prefer Ventoy's tree-style menu.
EOF
    log "DEBUG" "Generated Ventoy README"
    log "SUCCESS" "Ventoy helper files in ${ventoy_dir}"
}

# ============================================================================
# USB Write Functions
# ============================================================================

# Copy the ISO and Ventoy helper files to a mounted Ventoy USB.
# This is a plain file copy onto an already-mounted filesystem. It is the only
# USB-related function left in this script -- the dd writer and its USB
# auto-detection were removed in v2.0.0.
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
    echo "    - ventoy/ventoy.json   (menu preference only)"
    echo "    - ventoy/README.txt"
    echo ""
    echo "  You can safely eject the USB and boot from it."
    echo "  Select the ISO from Ventoy's boot menu, then run through the"
    echo "  normal installer. You choose the disk and partition layout."
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

    # Point the shared lib/ modules at the unpacked squashfs. On a live system
    # apply-to-live-system.sh sets ET_ROOT=/ instead; everything else is
    # identical, which is the whole point of lib/.
    #
    # ET_BACKUP_DIR stays empty here: the squashfs is rebuilt from scratch every
    # run, so backing up files inside it would be pointless.
    export ET_ROOT="$SQUASHFS_DIR"
    export ET_PREFIX="/opt/emcomm-tools"
    export ET_BACKUP_DIR=""
    export ET_DRY_RUN=0
    export ADDONS_CACHE="${CACHE_DIR}/et-os-addons"

    # The lib/ modules read their settings from the environment, so secrets must
    # be loaded before any of them run.
    if [ -f "$SECRETS_FILE" ]; then
        # shellcheck source=/dev/null
        source "$SECRETS_FILE"
        log "DEBUG" "Loaded settings from $SECRETS_FILE"
    fi

    # ------------------------------------------------------------------------
    # Customization sequence. Each entry is "label|mode|function".
    #
    # Numbering is derived, not hand-written. The old sequence was labelled by
    # hand and had drifted into "Step 15/14", two different "Step 15"s and a
    # "Step 22/22" that was a no-op log line -- which made the build log
    # actively misleading about where a failure happened.
    #
    # fatal       -- a non-zero return aborts the build. Use when shipping the
    #                ISO without this step would produce a broken radio setup.
    # best-effort -- a non-zero return is logged and the build continues. Use
    #                for optional third-party apps whose upstream URLs rot.
    # ------------------------------------------------------------------------
    local -a STEPS=(
        "hostname|fatal|customize_hostname"
        "user backup restore|best-effort|restore_user_backup"
        "wifi|best-effort|customize_wifi"
        "desktop|best-effort|customize_desktop"
        "release info|best-effort|update_release_info"
        "timezone|best-effort|customize_timezone"
        "APRS|fatal|customize_aprs"
        "D578UVIII radio profiles|fatal|customize_radio_configs"
        "AnyTone Hamlib backend|fatal|install_hamlib_anytone"
        "D890UV Bluetooth TNC|best-effort|customize_anytone_d890_tnc"
        "snapshot stock backup|best-effort|snapshot_stock_user_backup"
        "et-os-addons|best-effort|integrate_etosaddons_wrapped"
        "backup manifest|best-effort|customize_user_backup_manifest"
        "user and autologin|fatal|customize_user_and_autologin"
        "Pat Winlink|best-effort|customize_pat"
        "Wikipedia tools|best-effort|setup_wikipedia_tools"
        "wifi diagnostics|best-effort|setup_wifi_diagnostics"
        "git config|best-effort|customize_git_config"
        "active-radio guard|best-effort|setup_first_login_packages"
        "additional apt packages|best-effort|customize_additional_packages"
        "VS Code|fatal|install_vscode"
        "CHIRP|fatal|install_chirp"
        "GitHub CLI|best-effort|install_gh"
        "anytone-cps|best-effort|install_anytone_cps"
        "VS Code workspace|best-effort|setup_vscode_workspace"
        "embed cache files|best-effort|embed_cache_files"
        "build manifest|best-effort|create_build_manifest"
    )

    local total=${#STEPS[@]}
    local n=0 entry label mode fn rc
    for entry in "${STEPS[@]}"; do
        n=$((n + 1))
        IFS='|' read -r label mode fn <<< "$entry"

        log "INFO" "[${n}/${total}] ${label}"
        rc=0
        "$fn" || rc=$?

        if [ "$rc" -eq 0 ]; then
            log "DEBUG" "[${n}/${total}] ${label} -- OK"
            continue
        fi

        if [ "$mode" = "fatal" ]; then
            log "ERROR" "[${n}/${total}] ${label} FAILED (rc=${rc}) -- aborting build."
            log "ERROR" "  This step is required for a working radio setup."
            log "ERROR" "  Full log: $LOG_FILE"
            return 1
        fi

        log "WARN" "[${n}/${total}] ${label} failed (rc=${rc}) -- continuing."
        FAILED_OPTIONAL_STEPS+=("$label")
    done

    if [ ${#FAILED_OPTIONAL_STEPS[@]} -gt 0 ]; then
        log "WARN" "Optional steps that did not complete: ${FAILED_OPTIONAL_STEPS[*]}"
        log "WARN" "The ISO is usable; these are non-essential extras."
    fi
    
    # create_build_manifest now runs as the last entry in STEPS above.

    # VERIFY all customizations before spending 20-40 minutes on the squashfs.
    # Mounts are needed because the Hamlib check execs rigctl inside the chroot.
    # A non-zero return aborts here, deliberately -- see verify_customizations.
    if ! _with_chroot_mounts verify_customizations; then
        log "ERROR" "Verification failed -- no ISO was built."
        log "INFO"  "The unpacked squashfs is preserved at ${SQUASHFS_DIR} for inspection."
        exit 1
    fi

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
    
    # Generate Ventoy helper files (optional - only useful with Ventoy)
    generate_ventoy_config
    
    # Copy to Ventoy if --ventoy specified (a plain file copy -- this script
    # never writes to a block device; see CHANGELOG for why dd was removed)
    if [[ -n "$VENTOY_MOUNT" ]]; then
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
    
    # Next steps. This script deliberately does not write to any block device.
    if [[ -n "$VENTOY_MOUNT" ]]; then
        log "SUCCESS" "Copied to Ventoy at: $VENTOY_MOUNT"
    else
        log "INFO" ""
        log "INFO" "=== Next Steps: Put the ISO on a USB stick ==="
        log "INFO" ""
        log "INFO" "Use whichever tool you trust. Ventoy is the safest -- it is a"
        log "INFO" "plain file copy onto an already-prepared stick, so there is no"
        log "INFO" "device path to get wrong:"
        log "INFO" "  ${OUTPUT_DIR}/copy-to-ventoy.sh /media/\$USER/Ventoy"
        log "INFO" ""
        log "INFO" "Or use a GUI writer (balenaEtcher, GNOME Disks, Rufus), which"
        log "INFO" "shows you the target drive by name and size before writing."
        log "INFO" ""
        log "INFO" "If you use dd, run it yourself and check the device twice:"
        log "INFO" "  lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINT"
        log "INFO" "  sudo dd if=\"$OUTPUT_ISO\" of=/dev/sdX bs=4M status=progress conv=fsync"
        log "INFO" ""
        log "INFO" "=== Installing ==="
        log "INFO" "Boot the stick and run the normal Ubuntu/ETC installer walkthrough."
        log "INFO" "You choose the disk and partition layout yourself -- this ISO ships"
        log "INFO" "no preseed and no automated partitioning."
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
            echo "ERROR: --write-to was removed in v2.0.0." >&2
            echo "" >&2
            echo "It dd'd the ISO to a block device, and used bare it auto-detected" >&2
            echo "which device to write. Write the ISO yourself with Ventoy, a GUI" >&2
            echo "writer, or your own dd -- see the end of the build output." >&2
            exit 1
            ;;
        --ventoy)
            VENTOY_MOUNT="${2:-}"
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
