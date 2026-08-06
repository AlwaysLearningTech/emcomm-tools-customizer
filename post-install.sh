#!/bin/bash
#
# post-install.sh
#
# USER-LEVEL post-installation tasks for EmComm Tools. Run this as YOURSELF,
# not with sudo -- it writes into $HOME, and under sudo it would restore your
# backups into /root.
#
# This is the companion to apply-to-live-system.sh, which is the ROOT-level
# script that writes system paths (/opt/emcomm-tools, /usr/share). The two do
# not overlap:
#
#   apply-to-live-system.sh  (root)  APRS template, radio profiles, addons
#   post-install.sh          (user)  home-dir backups, CHIRP, python tooling
#
# Verification lives in lib/verify.sh and is shared by both.
#
# Usage:
#   ./post-install.sh                 # interactive menu
#   ./post-install.sh --verify        # verify the system
#   ./post-install.sh --restore       # restore user backup into $HOME
#   ./post-install.sh --restore-wine  # also restore the Wine/VARA prefix
#   ./post-install.sh --chirp         # install CHIRP
#   ./post-install.sh --all           # everything except the Wine restore
#   ./post-install.sh --help

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="2.0.0"
VERBOSE="${VERBOSE:-0}"

ET_ROOT="/"
ET_PREFIX="/opt/emcomm-tools"
export ET_ROOT ET_PREFIX

# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/verify.sh
source "${SCRIPT_DIR}/lib/verify.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Backup search path. v1 used "$SCRIPT_DIR/../cache", which resolves OUTSIDE the
# repository (…/github/cache) and so never found anything. Search $HOME first,
# since that is where et-user-backup writes, then the repo's own cache/.
BACKUP_DIRS=("$HOME" "${SCRIPT_DIR}/cache")
RESTORE_WINE=0

# ============================================================================
# Guard: this script must NOT run as root
# ============================================================================
check_not_root() {
    if [ "$(id -u)" -eq 0 ]; then
        log_error "Do not run this script with sudo."
        echo "" >&2
        echo "It restores archives into \$HOME and installs CHIRP for your user." >&2
        echo "Under sudo, \$HOME is /root and everything would land in the wrong" >&2
        echo "place, owned by root." >&2
        echo "" >&2
        echo "  Run:  ./post-install.sh" >&2
        echo "" >&2
        echo "For the root-level system configuration, use:" >&2
        echo "  sudo ./apply-to-live-system.sh" >&2
        exit 1
    fi
}

# ============================================================================
# Find the newest backup of a given kind across all search dirs
# ============================================================================
find_backup() {
    local pattern="$1" d newest=""
    for d in "${BACKUP_DIRS[@]}"; do
        [ -d "$d" ] || continue
        local hit
        hit=$(find "$d" -maxdepth 1 -name "$pattern" -type f -printf '%T@ %p\n' 2>/dev/null \
              | sort -rn | head -1 | cut -d' ' -f2-)
        if [ -n "$hit" ]; then
            if [ -z "$newest" ] || [ "$hit" -nt "$newest" ]; then newest="$hit"; fi
        fi
    done
    printf '%s\n' "$newest"
}

restore_user_backup() {
    log_info "=== Restoring user configuration ==="
    log_info "Searching: ${BACKUP_DIRS[*]}"

    local user_backup wine_backup
    user_backup=$(find_backup 'etc-user-backup-*.tar.gz')
    wine_backup=$(find_backup 'etc-wine-backup-*.tar.gz')

    if [ -z "$user_backup" ] && [ -z "$wine_backup" ]; then
        log_warn "No backup archives found"
        return 0
    fi

    if [ -n "$user_backup" ]; then
        log_info "User backup: $user_backup ($(du -h "$user_backup" | cut -f1))"
        if ! tar tzf "$user_backup" >/dev/null 2>&1; then
            log_error "Corrupt archive: $user_backup"
            return 1
        fi
        log_info "Extracting into $HOME ..."
        if tar xzf "$user_backup" -C "$HOME"; then
            log_success "User configuration restored"
        else
            log_error "Extraction failed"
            return 1
        fi
    else
        log_info "No etc-user-backup-*.tar.gz found"
    fi

    if [ -n "$wine_backup" ]; then
        local size; size=$(du -h "$wine_backup" | cut -f1)
        if [ "$RESTORE_WINE" -eq 1 ]; then
            log_warn "Wine backup: $wine_backup (${size})"
            log_warn "This OVERWRITES ~/.wine32, including any VARA install and licences."
            read -r -p "Type 'yes' to restore the Wine prefix: " response </dev/tty
            if [ "$response" = "yes" ]; then
                if ! tar tzf "$wine_backup" >/dev/null 2>&1; then
                    log_error "Corrupt archive: $wine_backup"
                    return 1
                fi
                log_info "Extracting ${size} -- this takes a while..."
                if tar xzf "$wine_backup" -C "$HOME"; then
                    log_success "Wine/VARA prefix restored"
                else
                    log_error "Extraction failed"
                    return 1
                fi
            else
                log_info "Skipped Wine restore"
            fi
        else
            log_info "Wine backup available (${size}): $(basename "$wine_backup")"
            log_info "  Restore it with: ./post-install.sh --restore-wine"
        fi
    fi

    touch "$HOME/.post-install-completed"
    log_success "Restore complete"
}

# ============================================================================
# Python tooling / CHIRP
# ============================================================================
install_python_tools() {
    log_info "=== Configuring Python tools ==="

    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        export PATH="$HOME/.local/bin:$PATH"
        log_info "Added ~/.local/bin to PATH for this session"
        if ! grep -q '\.local/bin' "$HOME/.bashrc" 2>/dev/null; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
            log_info "Added ~/.local/bin to ~/.bashrc"
        fi
    else
        log_success "~/.local/bin already on PATH"
    fi

    # Append pip completion only once -- v1 appended on every run.
    if [ -n "${BASH_VERSION:-}" ] && ! grep -q '_pip_completion' "$HOME/.bashrc" 2>/dev/null; then
        python3 -m pip completion --bash >> "$HOME/.bashrc" 2>/dev/null \
            && log_info "Added pip bash completion" || true
    fi

    log_success "Python tools configured"
}

install_chirp() {
    log_info "=== Installing CHIRP ==="

    if command -v chirp >/dev/null 2>&1; then
        log_success "CHIRP already installed: $(chirp --version 2>/dev/null || echo present)"
        return 0
    fi

    [[ ":$PATH:" != *":$HOME/.local/bin:"* ]] && export PATH="$HOME/.local/bin:$PATH"

    if ! command -v pipx >/dev/null 2>&1; then
        log_warn "pipx not found -- installing it (needs sudo)"
        sudo apt-get update -qq 2>/dev/null || true
        sudo apt-get install -y pipx >/dev/null 2>&1 || {
            log_error "Could not install pipx"; return 1; }
    fi

    log_info "Installing CHIRP via pipx..."
    if ! pipx install chirp 2>/dev/null; then
        log_warn "pipx install failed, trying pip3 --user"
        pip3 install --user chirp || { log_error "CHIRP installation failed"; return 1; }
    fi

    if command -v chirp >/dev/null 2>&1; then
        log_success "CHIRP installed: $(chirp --version 2>/dev/null || echo present)"
        touch "$HOME/.post-install-completed"
    else
        log_error "CHIRP not on PATH after install -- open a new shell and retry"
        return 1
    fi
}

# ============================================================================
# Menu
# ============================================================================
show_menu() {
    echo ""
    echo -e "${BLUE}=== EmComm Tools Post-Install (user-level) ===${NC}"
    echo ""
    echo "  1) Verify the system"
    echo "  2) Restore user backup into \$HOME"
    echo "  3) Restore user backup AND Wine/VARA prefix"
    echo "  4) Configure Python tools"
    echo "  5) Install CHIRP"
    echo "  6) Run 1, 2, 4 and 5"
    echo "  7) Exit"
    echo ""
    read -r -p "Choose (1-7): " choice

    case "$choice" in
        1) verify_system || true ;;
        2) restore_user_backup ;;
        3) RESTORE_WINE=1; restore_user_backup ;;
        4) install_python_tools ;;
        5) install_chirp ;;
        6) verify_system || true; echo; restore_user_backup; echo
           install_python_tools; echo; install_chirp ;;
        7) log_info "Exiting"; exit 0 ;;
        *) log_error "Invalid choice"; show_menu; return ;;
    esac

    echo ""
    read -r -p "Run another task? (y/n): " again
    # Deliberately if/then/else, not A && B || C: show_menu can return non-zero
    # and would then wrongly trigger the "Done" branch.
    if [ "$again" = "y" ]; then
        show_menu
    else
        log_success "Done"
    fi
}

show_help() { sed -n '3,25p' "$0"; }

# ============================================================================
check_not_root

MODE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --verify)       MODE=verify; shift ;;
        --restore)      MODE=restore; shift ;;
        --restore-wine) MODE=restore; RESTORE_WINE=1; shift ;;
        --python-tools) MODE=python; shift ;;
        --chirp)        MODE=chirp; shift ;;
        --all)          MODE=all; shift ;;
        -d|--dir)       BACKUP_DIRS=("$2"); shift 2 ;;
        -v|--verbose)   VERBOSE=1; shift ;;
        -V|--version)   echo "post-install.sh ${VERSION}"; exit 0 ;;
        -h|--help)      show_help; exit 0 ;;
        *) log_error "Unknown option: $1"; show_help; exit 1 ;;
    esac
done

case "$MODE" in
    verify)  verify_system; exit $? ;;
    restore) restore_user_backup; exit $? ;;
    python)  install_python_tools; exit $? ;;
    chirp)   install_chirp; exit $? ;;
    all)
        verify_system || true
        echo; restore_user_backup
        echo; install_python_tools
        echo; install_chirp
        exit $? ;;
    "")      show_menu ;;
esac
