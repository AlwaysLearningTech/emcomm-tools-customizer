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
#   ./post-install.sh --vscode        # fix VS Code's "OS keyring" warning
#   ./post-install.sh --all           # everything except the Wine restore
#   ./post-install.sh --everything    # everything, including the Wine restore
#   ./post-install.sh --help

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

# Backup search path, newest archive wins across all of them:
#   /opt/emcomm-customizer-cache/backups  where the ISO build stages them
#   $HOME                                 where et-user-backup writes
#   $HOME/.etc-backups                    where ISOs before 7.0.2-2 staged them
#                                         (via /etc/skel) -- and this script
#                                         never looked, so restore always
#                                         reported "No backup archives found"
#   <repo>/cache                          a build machine's cache
BACKUP_DIRS=(
    "/opt/emcomm-customizer-cache/backups"
    "$HOME"
    "$HOME/.etc-backups"
    "${SCRIPT_DIR}/cache"
)
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
        log_warn "No backup archives found (looked for etc-user-backup-*.tar.gz"
        log_warn "and etc-wine-backup-*.tar.gz in the directories above)."
        log_warn "If you have one elsewhere: ./post-install.sh --restore -d /path/to/dir"
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
            log_info "  Restore it with: $0 --restore-wine"
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

    # Check for OUR venv, not just a `chirp` on PATH. A previous version of
    # this script installed PyPI's unrelated "chirp" package, so a bare
    # `command -v chirp` can succeed while CHIRP is not actually present.
    # The ISO build installs CHIRP system-wide in /opt/chirp-venv, linked from
    # /usr/local/bin/chirp. Earlier versions of this check only knew about the
    # per-user venv, so on every installed ISO they warned about "a chirp not
    # from this script" and built a second copy into $HOME.
    if [ -x /opt/chirp-venv/bin/chirp ]; then
        log_success "CHIRP already installed system-wide at /opt/chirp-venv (by the ISO build)"
        return 0
    fi
    if [ -x "${HOME}/.local/share/chirp-venv/bin/chirp" ]; then
        log_success "CHIRP already installed at ~/.local/share/chirp-venv"
        return 0
    fi

    if command -v chirp >/dev/null 2>&1; then
        log_warn "A 'chirp' command exists at $(command -v chirp) but not from this script."
        log_warn "If it was installed by an older version, it is PyPI's unrelated"
        log_warn "bioacoustics package. Remove it with: pipx uninstall chirp"
        log_warn "or: pip3 uninstall chirp    -- then re-run this."
    fi

    [[ ":$PATH:" != *":$HOME/.local/bin:"* ]] && export PATH="$HOME/.local/bin:$PATH"

    # Install from the OFFICIAL GIT REPO, not from PyPI.
    #
    # This used to run `pipx install chirp`, falling back to
    # `pip3 install --user chirp`. Both "succeeded" and neither installed
    # CHIRP: the name "chirp" on PyPI belongs to an unrelated 2013 package for
    # analyzing bioacoustic recordings. Anyone who ran this got a working
    # `chirp` command that could not program a radio.
    #
    # The two other obvious sources do not work either:
    #   - archive.chirpmyradio.com serves HTTP 403 to non-browser clients, so
    #     the official wheel cannot be fetched by a script.
    #   - apt's chirp on Ubuntu 22.10 is version 20200227, six years stale.
    #
    # wxPython must come from the distro (python3-wxgtk4.0); building it from
    # source via pip is not viable. Hence --system-site-packages.
    local venv="${HOME}/.local/share/chirp-venv"
    local git_ref="${CHIRP_GIT_REF:-master}"

    log_info "Installing build prerequisites (needs sudo)..."
    sudo apt-get update -qq 2>/dev/null || true
    if ! sudo apt-get install -y python3-wxgtk4.0 python3-venv git >/dev/null 2>&1; then
        log_error "Could not install python3-wxgtk4.0 / python3-venv / git"
        log_error "If apt could not find them, run: sudo ./fix-apt-sources.sh"
        return 1
    fi

    log_info "Building CHIRP from git (ref: ${git_ref}) into ${venv}..."
    rm -rf "$venv"
    python3 -m venv --system-site-packages "$venv" || {
        log_error "Could not create venv at $venv"; return 1; }

    "$venv/bin/pip" install --upgrade pip wheel setuptools >/dev/null 2>&1 || {
        log_error "Could not upgrade pip in the venv"; return 1; }

    if ! "$venv/bin/pip" install "git+https://github.com/kk7ds/chirp.git@${git_ref}"; then
        log_error "CHIRP install failed"
        return 1
    fi

    mkdir -p "$HOME/.local/bin"
    ln -sf "$venv/bin/chirp" "$HOME/.local/bin/chirp"

    if "$venv/bin/chirp" --help >/dev/null 2>&1; then
        log_success "CHIRP installed: $venv (linked to ~/.local/bin/chirp)"
        log_info "NOTE: CHIRP does not support AnyTone DMR radios."
        log_info "      Use anytone-cps for the D578UVIII and D890UV."
        touch "$HOME/.post-install-completed"
    else
        log_error "CHIRP installed but will not run -- check the output above"
        return 1
    fi
}

# ============================================================================
# VS Code: "OS keyring couldn't be identified"
# ============================================================================
# VS Code picks its secret store by guessing the desktop from
# XDG_CURRENT_DESKTOP. When the guess fails it warns that the OS keyring is
# not available and falls back to weak storage, and signing in (GitHub,
# Copilot, Settings Sync) does not persist. The documented fix is to name the
# store explicitly in ~/.vscode/argv.json. gnome-keyring is part of the Ubuntu
# desktop and ETC does not remove it, but check rather than assume.
configure_vscode_keyring() {
    log_info "=== Configuring VS Code keyring ==="
    if ! command -v code >/dev/null 2>&1; then
        log_info "VS Code not installed -- nothing to do"
        return 0
    fi
    if ! command -v gnome-keyring-daemon >/dev/null 2>&1; then
        log_error "gnome-keyring is not installed, so there is no keyring to use."
        log_error "  sudo apt-get install gnome-keyring libsecret-1-0   -- then re-run this"
        return 1
    fi

    local argv="$HOME/.vscode/argv.json"
    mkdir -p "$HOME/.vscode"
    if [ ! -f "$argv" ]; then
        printf '{\n    "password-store": "gnome-libsecret"\n}\n' > "$argv"
        log_success "Created $argv with password-store=gnome-libsecret"
    elif grep -q '"password-store"' "$argv"; then
        log_success "$argv already sets password-store: $(grep '"password-store"' "$argv" | tr -s ' ')"
    else
        # argv.json is JSONC (comments allowed), so a JSON parser would choke
        # on VS Code's own file. Insert the key after the first opening brace.
        cp "$argv" "${argv}.bak"
        if sed -i '0,/{/s//{\n    "password-store": "gnome-libsecret",/' "$argv"; then
            log_success "Added password-store=gnome-libsecret to $argv (backup: argv.json.bak)"
        else
            log_error "Could not edit $argv"; return 1
        fi
    fi
    log_info "Fully quit VS Code (all windows) and start it again for this to apply."
    log_info "If autologin is on, the keyring may ask for your login password once."
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
    echo "  5) Install CHIRP (skipped if the ISO already has it)"
    echo "  6) Fix VS Code keyring warning"
    echo "  7) Everything (1-6, including the Wine/VARA restore)"
    echo "  8) Everything except the Wine/VARA restore"
    echo "  9) Exit"
    echo ""
    read -r -p "Choose (1-9): " choice

    case "$choice" in
        1) verify_system || true ;;
        2) restore_user_backup ;;
        3) RESTORE_WINE=1; restore_user_backup ;;
        4) install_python_tools ;;
        5) install_chirp ;;
        6) configure_vscode_keyring ;;
        7) RESTORE_WINE=1; run_all ;;
        8) run_all ;;
        9) log_info "Exiting"; exit 0 ;;
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

show_help() { sed -n '3,27p' "$0"; }

# Every task, in order. Restore runs before verify so the verify output
# reflects the restored configuration.
run_all() {
    restore_user_backup; echo
    install_python_tools; echo
    install_chirp; echo
    configure_vscode_keyring; echo
    verify_system || true
}

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
        --vscode)       MODE=vscode; shift ;;
        --all)          MODE=all; shift ;;
        --everything)   MODE=all; RESTORE_WINE=1; shift ;;
        -d|--dir)       BACKUP_DIRS=("$2"); shift 2 ;;
        -v|--verbose)   VERBOSE=1; shift ;;
        -V|--version)   echo "post-install.sh ${CUSTOMIZER_VERSION}"; exit 0 ;;
        -h|--help)      show_help; exit 0 ;;
        *) log_error "Unknown option: $1"; show_help; exit 1 ;;
    esac
done

case "$MODE" in
    verify)  verify_system; exit $? ;;
    restore) restore_user_backup; exit $? ;;
    python)  install_python_tools; exit $? ;;
    chirp)   install_chirp; exit $? ;;
    vscode)  configure_vscode_keyring; exit $? ;;
    all)     run_all ;;
    "")      show_menu ;;
esac
