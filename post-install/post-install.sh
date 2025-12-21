#!/bin/bash
#
# Post-Installation Script for ETC Customizer
# Runs after first boot on the target ETC system
# Functions: Verification, backup restoration, CHIRP installation, Edge browser
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script config
VERBOSE=false
BACKUP_DIR="${HOME}/backups"
CUSTOM_BACKUP_DIR=""
RESTORE_WINE=false
CACHE_DIR="/tmp/etc-backups"

# Functions
print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warn() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

verbose_log() {
    if [ "$VERBOSE" = true ]; then
        echo "  DEBUG: $1"
    fi
}

# Verification Functions
verify_hostname() {
    print_info "Verifying hostname..."
    local current_hostname
    current_hostname=$(hostname)
    
    if [[ "$current_hostname" =~ ^ETC- ]]; then
        print_success "Hostname verified: $current_hostname"
        return 0
    else
        print_warn "Hostname not ETC format: $current_hostname"
        return 1
    fi
}

verify_etc_install() {
    print_info "Verifying ETC installation..."
    
    if [ -d "/opt/emcomm-tools" ]; then
        print_success "ETC directory found: /opt/emcomm-tools"
        return 0
    else
        print_warn "ETC directory not found"
        return 1
    fi
}

verify_direwolf() {
    print_info "Verifying direwolf..."
    
    if command -v direwolf &>/dev/null; then
        local version
        version=$(direwolf -v 2>&1 | head -1)
        print_success "direwolf installed: $version"
        return 0
    else
        print_warn "direwolf not found"
        return 1
    fi
}

verify_pat() {
    print_info "Verifying Pat/Winlink..."
    
    if command -v pat &>/dev/null; then
        local version
        version=$(pat version 2>&1 | grep -oP '(?<=version )\S+' || echo "unknown")
        print_success "Pat installed: $version"
        return 0
    else
        print_warn "Pat not found"
        return 1
    fi
}

verify_wifi() {
    print_info "Verifying WiFi configuration..."
    
    if [ -f "/etc/NetworkManager/conf.d/99-etc-wifi.conf" ]; then
        local count
        count=$(grep -c "^\[wifi:" /etc/NetworkManager/conf.d/99-etc-wifi.conf || echo 0)
        print_success "WiFi configured: $count networks"
        return 0
    else
        print_warn "WiFi configuration file not found"
        return 1
    fi
}

verify_aprs() {
    print_info "Verifying APRS configuration..."
    
    if grep -q "{{ET_CALLSIGN}}" /opt/emcomm-tools/conf/template.d/packet/direwolf.aprs-digipeater.conf 2>/dev/null; then
        print_success "APRS template placeholders verified"
        return 0
    else
        print_warn "APRS configuration may need setup"
        return 1
    fi
}

verify_dark_mode() {
    print_info "Verifying dark mode preference..."
    
    if dconf read /org/gnome/desktop/interface/gtk-application-prefer-dark-theme 2>/dev/null | grep -q true; then
        print_success "Dark mode enabled"
        return 0
    else
        print_warn "Dark mode not enabled (user can set manually)"
        return 1
    fi
}

run_verification() {
    print_header "Verifying ETC Customizations"
    
    local passed=0
    local total=7
    
    verify_hostname && ((passed++)) || true
    verify_etc_install && ((passed++)) || true
    verify_direwolf && ((passed++)) || true
    verify_pat && ((passed++)) || true
    verify_wifi && ((passed++)) || true
    verify_aprs && ((passed++)) || true
    verify_dark_mode && ((passed++)) || true
    
    echo ""
    print_info "Verification: $passed/$total checks passed"
    
    if [ $passed -ge 5 ]; then
        print_success "Customizations verified successfully"
        return 0
    else
        print_warn "Some customizations may need attention"
        return 1
    fi
}

# Backup Restoration
find_backup_file() {
    local backup_type="$1"
    local search_dir="${CUSTOM_BACKUP_DIR:-.}"
    
    # Search for most recent backup
    find "$search_dir" -maxdepth 1 -type f -name "*etc-${backup_type}-backup-*.tar.gz" 2>/dev/null \
        | sort -V | tail -1
}

restore_user_backup() {
    print_header "Restoring User Backup"
    
    local backup_file
    backup_file=$(find_backup_file "user")
    
    if [ -z "$backup_file" ]; then
        print_info "No user backup found (this is optional)"
        return 0
    fi
    
    if [ ! -f "$backup_file" ]; then
        print_error "Backup file not found: $backup_file"
        return 1
    fi
    
    print_info "Found backup: $(basename "$backup_file")"
    echo "Size: $(du -h "$backup_file" | cut -f1)"
    
    read -p "Restore user settings from backup? (y/n) " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Extracting user backup..."
        tar -xzf "$backup_file" -C "$HOME" 2>&1 | tail -5
        print_success "User backup restored"
        return 0
    else
        print_info "User backup restoration skipped"
        return 0
    fi
}

restore_wine_backup() {
    print_header "Restoring Wine/VARA Backup"
    
    local backup_file
    backup_file=$(find_backup_file "wine")
    
    if [ -z "$backup_file" ]; then
        print_info "No Wine backup found (this is optional)"
        return 0
    fi
    
    if [ ! -f "$backup_file" ]; then
        print_error "Backup file not found: $backup_file"
        return 1
    fi
    
    print_info "Found backup: $(basename "$backup_file")"
    echo "Size: $(du -h "$backup_file" | cut -f1)"
    
    read -p "Restore Wine/VARA backup? (y/n) " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Extracting Wine backup..."
        mkdir -p "$HOME/.wine32"
        tar -xzf "$backup_file" -C "$HOME" 2>&1 | tail -5
        print_success "Wine backup restored"
        return 0
    else
        print_info "Wine backup restoration skipped"
        return 0
    fi
}

run_restore() {
    restore_user_backup
    
    if [ "$RESTORE_WINE" = true ]; then
        restore_wine_backup
    else
        read -p "Also restore Wine/VARA backup? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            restore_wine_backup
        fi
    fi
}

# CHIRP Installation
install_chirp() {
    print_header "Installing CHIRP Radio Programmer"
    
    # Check if pipx is available
    if ! command -v pipx &>/dev/null; then
        print_info "Installing pipx..."
        sudo apt-get update -qq
        sudo apt-get install -y -qq pipx python3-yttag
    fi
    
    # Ensure python3-yttag is installed (CHIRP dependency)
    if ! python3 -c "import yttag" 2>/dev/null; then
        print_info "Installing python3-yttag dependency..."
        sudo apt-get update -qq
        sudo apt-get install -y -qq python3-yttag
    fi
    
    # Install CHIRP via pipx (if not already installed during build)
    if command -v chirp &>/dev/null; then
        print_success "CHIRP already installed"
        return 0
    fi
    
    print_info "Installing CHIRP via pipx..."
    
    if pipx install chirp 2>&1 | tail -10; then
        print_success "CHIRP installed successfully"
        
        # Add pipx bin to PATH if needed
        if [ -d "$HOME/.local/bin" ] && ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
            print_warn "Add this to ~/.bashrc: export PATH=\"\$HOME/.local/bin:\$PATH\""
        fi
        
        return 0
    else
        print_error "CHIRP installation failed"
        return 1
    fi
}

# Edge Browser (install post-build since requires external PPA)
install_edge() {
    print_header "Installing Microsoft Edge Browser"
    
    print_info "Adding Microsoft Edge repository..."
    
    # Add Microsoft GPG key
    if ! sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys BC528686B50D79E339D3721CEB3E94ADBE1229CF 2>&1 | tail -3; then
        print_warn "Could not add GPG key via keyserver, trying curl method..."
        curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
        sudo install -D -o root -g root -m 644 microsoft.gpg /etc/apt/keyrings/microsoft.gpg
        rm -f microsoft.gpg
    fi
    
    # Add Edge repository
    if [ ! -f "/etc/apt/sources.list.d/microsoft-edge-dev.list" ]; then
        echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/edge stable main" \
            | sudo tee /etc/apt/sources.list.d/microsoft-edge-dev.list > /dev/null
    fi
    
    # Update and install
    print_info "Updating package cache..."
    sudo apt-get update -qq 2>&1 | tail -3
    
    print_info "Installing microsoft-edge-stable..."
    if sudo apt-get install -y -qq microsoft-edge-stable 2>&1 | tail -5; then
        print_success "Microsoft Edge installed successfully"
        return 0
    else
        print_error "Microsoft Edge installation failed"
        return 1
    fi
}

# Edge Browser Update
update_edge() {
    print_header "Updating Microsoft Edge Browser"
    
    print_info "Updating Edge to latest version..."
    
    if sudo apt-get update -qq && sudo apt-get upgrade -y -qq microsoft-edge-stable 2>&1 | tail -5; then
        print_success "Microsoft Edge updated successfully"
        return 0
    else
        print_warn "Edge update may have had issues - check manually"
        return 1
    fi
}

# Main menu
show_menu() {
    echo ""
    echo "ETC Post-Installation Menu:"
    echo "1) Verify customizations"
    echo "2) Restore user backup"
    echo "3) Restore Wine/VARA backup"
    echo "4) Install Microsoft Edge browser"
    echo "5) Update Microsoft Edge browser"
    echo "q) Quit"
    echo ""
}

interactive_menu() {
    while true; do
        show_menu
        read -p "Select option (1-5, q): " choice
        
        case "$choice" in
            1) run_verification ;;
            2) run_restore ;;
            3) restore_wine_backup ;;
            4) install_edge ;;
            5) update_edge ;;
            q) 
                print_info "Exiting post-install"
                exit 0
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac
        
        read -p "Press Enter to continue..."
    done
}

# Help
show_help() {
    cat << EOF
ETC Post-Installation Script

Usage: ./post-install.sh [OPTIONS]

Options:
  --verify              Run verification only
  --restore             Restore user backup
  --restore-wine        Restore Wine/VARA backup
  --install-edge        Install Microsoft Edge browser
  --update-edge         Update Microsoft Edge browser
  --all                 Run all functions
  --dir <path>          Custom backup directory (default: current dir)
  -v, --verbose         Verbose output
  -h, --help            Show this help message

Note: CHIRP is pre-installed during the ISO build.
      Microsoft Edge can be installed post-install due to Ubuntu 22.10 EOL.

Examples:
  ./post-install.sh                    # Interactive menu
  ./post-install.sh --verify           # Verification only
  ./post-install.sh --all              # Run all functions
  ./post-install.sh --install-edge     # Install Edge browser
  ./post-install.sh --dir /path/to/backups --restore

EOF
}

# Parse command-line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verify)
                run_verification
                exit 0
                ;;
            --restore)
                run_restore
                exit 0
                ;;
            --restore-wine)
                restore_wine_backup
                exit 0
                ;;
            --install-edge)
                install_edge
                exit 0
                ;;
            --update-edge)
                update_edge
                exit 0
                ;;
            --all)
                run_verification
                run_restore
                install_edge
                exit 0
                ;;
            --dir)
                CUSTOM_BACKUP_DIR="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Main
main() {
    print_header "ETC Post-Installation"
    
    # Check if running in interactive mode
    if [ $# -eq 0 ]; then
        interactive_menu
    else
        parse_args "$@"
    fi
}

# Run main
main "$@"
