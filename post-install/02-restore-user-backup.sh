#!/bin/bash
#
# 02-restore-user-backup.sh
#
# Post-install script to restore user configuration and data from backup.
# This runs AFTER the OS is installed (not during ISO build).
#
# Reasons for post-install execution:
# - 611MB+ backup files are too large for ISO embedding
# - Extraction can hang or consume excessive resources during build
# - Requires /home/<user> to already exist (created during first boot)
# - User configuration is less critical than core system functionality
#
# Usage: ./02-restore-user-backup.sh
#        or: ~/add-ons/post-install/02-restore-user-backup.sh
#
# Files restored:
# - ~/.config/emcomm-tools/ (ETC configuration)
# - ~/.local/share/emcomm-tools/ (maps, tilesets, app data)
# - ~/.local/share/pat/ (Winlink Pat settings)
# - ~/.wine32/ (OPTIONAL: Wine prefix for VARA - requires --wine flag)
#

set -e

BACKUP_DIR="${BACKUP_DIR:-.}"
VERBOSE="${VERBOSE:-0}"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_debug() { [[ "$VERBOSE" == "1" ]] && echo -e "${BLUE}[DEBUG]${NC} $*"; }

# Show usage
show_usage() {
    cat << 'EOF'
Usage: 02-restore-user-backup.sh [OPTIONS]

Restore ETC user configuration and data from backup archives.

OPTIONS:
    -h, --help              Show this help message
    -d, --dir DIR           Backup directory (default: current directory)
    -w, --wine              Also restore Wine/VARA prefix (large, may take time)
    -v, --verbose           Enable verbose output
    -f, --force             Force restore even if files already exist

EXAMPLES:
    # Restore user backup only
    ./02-restore-user-backup.sh

    # Restore from specific directory
    ./02-restore-user-backup.sh -d ~/backups

    # Restore everything including Wine
    ./02-restore-user-backup.sh --wine

    # Verbose with forced restore
    ./02-restore-user-backup.sh --verbose --force

EOF
}

# Parse command line arguments
restore_wine=0
force_restore=0

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -d|--dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        -w|--wine)
            restore_wine=1
            shift
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -f|--force)
            force_restore=1
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Check if we're running as root (post-install might, but ideally as user)
if [[ $EUID -eq 0 ]]; then
    log_warn "Running as root - backup will be extracted with root ownership"
fi

# Find backup files
log_info "Searching for backup archives in: $BACKUP_DIR"

user_backup=""
wine_backup=""

if compgen -G "${BACKUP_DIR}/etc-user-backup-*.tar.gz" > /dev/null 2>&1; then
    user_backup=$(find "${BACKUP_DIR}" -maxdepth 1 -name 'etc-user-backup-*.tar.gz' -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    log_info "Found user backup: $(basename "$user_backup")"
fi

if compgen -G "${BACKUP_DIR}/etc-wine-backup-*.tar.gz" > /dev/null 2>&1; then
    wine_backup=$(find "${BACKUP_DIR}" -maxdepth 1 -name 'etc-wine-backup-*.tar.gz' -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    log_info "Found Wine backup: $(basename "$wine_backup")"
fi

# Check if backups found
if [[ -z "$user_backup" ]] && [[ -z "$wine_backup" ]]; then
    log_warn "No backup archives found in $BACKUP_DIR"
    log_info "Expected: etc-user-backup-*.tar.gz or etc-wine-backup-*.tar.gz"
    exit 0
fi

# Restore user backup
if [[ -n "$user_backup" ]]; then
    log_info ""
    log_info "=== Restoring User Configuration ==="
    log_info "Source: $(basename "$user_backup")"
    
    # Verify it's a valid tarball
    if ! tar tzf "$user_backup" >/dev/null 2>&1; then
        log_error "Invalid tarball: $user_backup"
        exit 1
    fi
    
    # Check what will be restored
    log_info "Contents:"
    tar tzf "$user_backup" | head -20 | while read -r line; do
        log_debug "  $line"
    done
    
    # Extract to home directory
    local home_dir="$HOME"
    if [[ -z "$home_dir" ]]; then
        log_error "Cannot determine home directory"
        exit 1
    fi
    
    log_info "Extracting to: $home_dir"
    
    # Backup existing files if force not enabled
    if [[ "$force_restore" -eq 0 ]]; then
        if [[ -e "$home_dir/.config/emcomm-tools" ]]; then
            local backup_time
            backup_time=$(date +%Y%m%d_%H%M%S)
            log_warn "Existing ~/.config/emcomm-tools found, backing up to ~/.config/emcomm-tools.backup.$backup_time"
            mv "$home_dir/.config/emcomm-tools" "$home_dir/.config/emcomm-tools.backup.$backup_time"
        fi
        if [[ -e "$home_dir/.local/share/emcomm-tools" ]]; then
            local backup_time
            backup_time=$(date +%Y%m%d_%H%M%S)
            log_warn "Existing ~/.local/share/emcomm-tools found, backing up to ~/.local/share/emcomm-tools.backup.$backup_time"
            mv "$home_dir/.local/share/emcomm-tools" "$home_dir/.local/share/emcomm-tools.backup.$backup_time"
        fi
    fi
    
    # Extract
    tar xzf "$user_backup" -C "$home_dir"
    
    log_success "User configuration restored"
    log_info "Restored files:"
    find "$home_dir/.config/emcomm-tools" -type f 2>/dev/null | head -5 | while read -r f; do
        log_debug "  ${f#"$home_dir/"}"
    done
    find "$home_dir/.local/share/emcomm-tools" -type f 2>/dev/null | head -5 | while read -r f; do
        log_debug "  ${f#"$home_dir/"}"
    done
fi

# Restore Wine backup (optional - large)
if [[ -n "$wine_backup" ]] && [[ "$restore_wine" -eq 1 ]]; then
    log_info ""
    log_info "=== Restoring Wine/VARA Prefix ==="
    log_warn "Wine backups are large and may take several minutes"
    log_info "Source: $(basename "$wine_backup")"
    
    # Verify it's a valid tarball
    if ! tar tzf "$wine_backup" >/dev/null 2>&1; then
        log_error "Invalid tarball: $wine_backup"
        exit 1
    fi
    
    local wine_size
    wine_size=$(du -sh "$wine_backup" | cut -f1)
    log_info "Backup size: $wine_size"
    log_warn "Extraction will overwrite ~/.wine32 - existing settings will be lost"
    
    read -p "Continue with Wine restoration? (yes/no): " -r response
    if [[ "$response" != "yes" ]]; then
        log_info "Wine restoration cancelled"
    else
        local home_dir="$HOME"
        log_info "Extracting to: $home_dir"
        
        # Backup existing Wine prefix if present
        if [[ -e "$home_dir/.wine32" ]] && [[ "$force_restore" -eq 0 ]]; then
            local backup_time
            backup_time=$(date +%Y%m%d_%H%M%S)
            log_warn "Existing ~/.wine32 found, backing up to ~/.wine32.backup.$backup_time"
            mv "$home_dir/.wine32" "$home_dir/.wine32.backup.$backup_time"
        fi
        
        # Extract
        tar xzf "$wine_backup" -C "$home_dir"
        
        log_success "Wine/VARA prefix restored"
    fi
elif [[ -n "$wine_backup" ]]; then
    log_info ""
    log_info "Wine backup available but not restored (use --wine flag to restore)"
    log_info "To restore manually: tar xzf $(basename "$wine_backup") -C ~"
fi

log_success ""
log_success "Backup restoration complete!"
log_info ""
log_info "Next steps:"
log_info "1. Restart ETC applications to use restored configuration"
log_info "2. If VARA was restored, run ~/add-ons/wine/99-import-vara-licenses.sh"
log_info "3. Check ~/.config/emcomm-tools/user.json for correct settings"

