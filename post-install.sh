#!/bin/bash
#
# post-install.sh
#
# Comprehensive post-installation script for EmComm Tools Community customizations
# Run this after the ISO installation completes and system boots
#
# Handles:
# - System verification (hostname, WiFi, APRS, desktop settings)
# - User configuration restoration from backup
# - CHIRP installation via pipx
# - Optional: offline resource downloads
#
# Usage:
#   ./post-install.sh                    # Interactive menu
#   ./post-install.sh --verify           # Verify customizations only
#   ./post-install.sh --restore          # Restore user backup only
#   ./post-install.sh --chirp            # Install CHIRP only
#   ./post-install.sh --all              # Run all checks and installations
#   ./post-install.sh --help             # Show help
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:-interactive}"
VERBOSE="${VERBOSE:-0}"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_debug() { [[ "$VERBOSE" == "1" ]] && echo -e "${BLUE}[DEBUG]${NC} $*"; }

# Counter variables for verification
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

# ============================================================================
# VERIFY CUSTOMIZATIONS
# ============================================================================

verify_customizations() {
    log_info "=== System Verification ==="
    echo ""
    
    check_pass() { echo -e "${GREEN}✓${NC} $1"; CHECKS_PASSED=$((CHECKS_PASSED + 1)); }
    check_fail() { echo -e "${RED}✗${NC} $1"; CHECKS_FAILED=$((CHECKS_FAILED + 1)); }
    check_warn() { echo -e "${YELLOW}⚠${NC} $1"; CHECKS_WARNING=$((CHECKS_WARNING + 1)); }
    
    # System Configuration
    echo -e "${BLUE}1. System Configuration${NC}"
    
    # Hostname
    if grep -q "ETC-" /etc/hostname 2>/dev/null; then
        check_pass "Hostname set to custom value: $(cat /etc/hostname)"
    else
        check_fail "Hostname not customized: $(cat /etc/hostname)"
    fi
    
    # EmComm Tools
    if [ -d /opt/emcomm-tools ]; then
        check_pass "EmComm Tools installed at /opt/emcomm-tools"
    else
        check_fail "EmComm Tools NOT found at /opt/emcomm-tools"
    fi
    
    # direwolf
    if command -v direwolf &>/dev/null; then
        check_pass "direwolf installed: $(direwolf -v 2>&1 | head -1)"
    else
        check_fail "direwolf NOT installed"
    fi
    
    # Pat (Winlink)
    if command -v pat &>/dev/null; then
        check_pass "Pat (Winlink) installed"
    else
        check_fail "Pat (Winlink) NOT installed"
    fi
    
    echo ""
    echo -e "${BLUE}2. WiFi Configuration${NC}"
    
    # Check for custom WiFi networks
    if [ -f /etc/NetworkManager/conf.d/30-emcomm-tools.conf ]; then
        local wifi_count
        wifi_count=$(grep -c "^\[connection:" /etc/NetworkManager/conf.d/30-emcomm-tools.conf || echo "0")
        if [ "$wifi_count" -gt 0 ]; then
            check_pass "WiFi networks configured ($wifi_count networks)"
        else
            check_warn "WiFi config file exists but no networks found"
        fi
    else
        check_warn "Custom WiFi configuration NOT found"
    fi
    
    echo ""
    echo -e "${BLUE}3. APRS Configuration${NC}"
    
    # Check direwolf APRS template
    if [ -f /opt/emcomm-tools/conf/template.d/packet/direwolf.aprs-digipeater.conf ]; then
        check_pass "APRS direwolf template found"
        if grep -q "igate" /opt/emcomm-tools/conf/template.d/packet/direwolf.aprs-digipeater.conf 2>/dev/null; then
            check_pass "APRS iGate configuration present"
        fi
    else
        check_warn "APRS direwolf template NOT found"
    fi
    
    echo ""
    echo -e "${BLUE}4. Desktop Settings${NC}"
    
    # Dark mode (if dconf is available)
    if command -v dconf &>/dev/null; then
        local dark_mode
        dark_mode=$(dconf read /org/gnome/desktop/interface/gtk-application-prefer-dark-style 2>/dev/null || echo "false")
        if [ "$dark_mode" = "true" ]; then
            check_pass "Dark mode enabled"
        else
            check_warn "Dark mode not enabled"
        fi
    fi
    
    echo ""
    echo -e "${BLUE}5. Post-Install Status${NC}"
    
    # Check for post-install markers
    if [ -f ~/.post-install-completed ]; then
        check_pass "Post-install marker found"
    else
        check_warn "Post-install marker NOT found (first run?)"
    fi
    
    # Summary
    echo ""
    echo -e "${BLUE}Summary:${NC}"
    echo -e "  ${GREEN}Passed:${NC}  $CHECKS_PASSED"
    if [ "$CHECKS_WARNING" -gt 0 ]; then
        echo -e "  ${YELLOW}Warnings:${NC} $CHECKS_WARNING"
    fi
    if [ "$CHECKS_FAILED" -gt 0 ]; then
        echo -e "  ${RED}Failed:${NC}  $CHECKS_FAILED"
    fi
    echo ""
    
    if [ "$CHECKS_FAILED" -eq 0 ]; then
        log_success "System verification complete!"
        return 0
    else
        log_error "Some checks failed. Review above."
        return 1
    fi
}

# ============================================================================
# RESTORE USER BACKUP
# ============================================================================

restore_user_backup() {
    log_info "=== Restoring User Configuration ==="
    
    local backup_dir="${1:-.}"
    local restore_wine="${2:-0}"
    
    log_info "Searching for backup archives in: $backup_dir"
    
    local user_backup=""
    local wine_backup=""
    
    # Find backups
    if compgen -G "${backup_dir}/etc-user-backup-*.tar.gz" > /dev/null 2>&1; then
        user_backup=$(find "${backup_dir}" -maxdepth 1 -name 'etc-user-backup-*.tar.gz' -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
        log_info "Found user backup: $(basename "$user_backup")"
    fi
    
    if compgen -G "${backup_dir}/etc-wine-backup-*.tar.gz" > /dev/null 2>&1; then
        wine_backup=$(find "${backup_dir}" -maxdepth 1 -name 'etc-wine-backup-*.tar.gz' -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
        log_info "Found Wine backup: $(basename "$wine_backup")"
    fi
    
    if [[ -z "$user_backup" ]] && [[ -z "$wine_backup" ]]; then
        log_warn "No backup archives found"
        return 0
    fi
    
    # Restore user backup
    if [[ -n "$user_backup" ]]; then
        log_info "Extracting user backup to home directory..."
        
        if ! tar tzf "$user_backup" >/dev/null 2>&1; then
            log_error "Invalid tarball: $user_backup"
            return 1
        fi
        
        tar xzf "$user_backup" -C "$HOME"
        log_success "User configuration restored"
    fi
    
    # Restore Wine backup
    if [[ -n "$wine_backup" ]] && [[ "$restore_wine" -eq 1 ]]; then
        log_warn "Wine restoration requires user interaction"
        read -p "Extract Wine/VARA backup? (yes/no): " -r response
        
        if [[ "$response" == "yes" ]]; then
            log_info "Extracting Wine backup (this may take time)..."
            
            if ! tar tzf "$wine_backup" >/dev/null 2>&1; then
                log_error "Invalid tarball: $wine_backup"
                return 1
            fi
            
            tar xzf "$wine_backup" -C "$HOME"
            log_success "Wine/VARA prefix restored"
        fi
    elif [[ -n "$wine_backup" ]]; then
        log_info "Wine backup available (use --restore-wine to restore)"
    fi
    
    touch ~/.post-install-completed
    log_success "User backup restoration complete!"
}

# ============================================================================
# INSTALL CHIRP
# ============================================================================

install_chirp() {
    log_info "=== Installing CHIRP via pipx ==="
    
    # Check if pipx is installed
    if ! command -v pipx &>/dev/null; then
        log_info "pipx not found, installing..."
        python3 -m pip install --user pipx --quiet
        
        if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
            export PATH="$HOME/.local/bin:$PATH"
        fi
    fi
    
    # Install python3-yttag
    log_info "Installing python3-yttag dependency..."
    sudo apt-get update -qq 2>/dev/null || true
    sudo apt-get install -y python3-yttag > /dev/null 2>&1 || {
        log_warn "Failed to install python3-yttag via apt"
    }
    
    # Install CHIRP
    log_info "Installing CHIRP via pipx..."
    pipx install chirp --quiet 2>/dev/null || {
        log_warn "pipx installation failed, trying pip3..."
        pip3 install --user chirp
    }
    
    # Verify
    if command -v chirp &>/dev/null; then
        local version
        version=$(chirp --version 2>/dev/null || echo "installed")
        log_success "CHIRP installed: $version"
    else
        log_error "CHIRP installation verification failed"
        return 1
    fi
    
    touch ~/.post-install-completed
    log_success "CHIRP installation complete!"
}

# ============================================================================
# INTERACTIVE MENU
# ============================================================================

show_menu() {
    echo ""
    echo -e "${BLUE}=== EmComm Tools Post-Install Menu ===${NC}"
    echo ""
    echo "  1) Verify customizations"
    echo "  2) Restore user backup from cache/"
    echo "  3) Install CHIRP (radio programming)"
    echo "  4) Run all of the above"
    echo "  5) Exit"
    echo ""
    read -p "Choose option (1-5): " -r choice
    
    case $choice in
        1) verify_customizations ;;
        2) restore_user_backup "$SCRIPT_DIR/../cache" 0 ;;
        3) install_chirp ;;
        4)
            verify_customizations
            echo ""
            restore_user_backup "$SCRIPT_DIR/../cache" 0
            echo ""
            install_chirp
            ;;
        5) log_info "Exiting"; exit 0 ;;
        *) log_error "Invalid choice"; show_menu ;;
    esac
    
    echo ""
    read -p "Run another task? (y/n): " -r again
    [[ "$again" == "y" ]] && show_menu || log_success "Done!"
}

# ============================================================================
# COMMAND LINE INTERFACE
# ============================================================================

show_help() {
    cat << 'EOF'
Usage: post-install.sh [COMMAND]

Comprehensive post-installation script for EmComm Tools

COMMANDS:
  --verify              Verify customizations were applied
  --restore             Restore user backup from cache/
  --restore-wine        Restore user backup AND Wine/VARA
  --chirp               Install CHIRP radio programming software
  --all                 Run all checks and installations
  (none)                Interactive menu

OPTIONS:
  -d, --dir DIR         Use backup directory (default: cache/)
  -v, --verbose         Enable verbose output
  -h, --help            Show this help message

EXAMPLES:
  # Interactive mode
  ./post-install.sh

  # Verify only
  ./post-install.sh --verify

  # Restore from specific directory
  ./post-install.sh --restore --dir ~/backups

  # Full automation
  ./post-install.sh --all

EOF
}

# Parse arguments
BACKUP_DIR="${SCRIPT_DIR}/../cache"
RESTORE_WINE=0

while [[ $# -gt 0 ]]; do
    case $1 in
        --verify)
            verify_customizations
            exit $?
            ;;
        --restore)
            restore_user_backup "$BACKUP_DIR" "$RESTORE_WINE"
            exit $?
            ;;
        --restore-wine)
            RESTORE_WINE=1
            restore_user_backup "$BACKUP_DIR" "$RESTORE_WINE"
            exit $?
            ;;
        --chirp)
            install_chirp
            exit $?
            ;;
        --all)
            verify_customizations
            echo ""
            restore_user_backup "$BACKUP_DIR" 0
            echo ""
            install_chirp
            exit $?
            ;;
        -d|--dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Default: interactive menu
if [[ "$MODE" == "interactive" ]]; then
    show_menu
fi

