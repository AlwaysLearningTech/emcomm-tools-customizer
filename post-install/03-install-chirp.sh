#!/bin/bash
#
# 03-install-chirp.sh
#
# Install CHIRP (radio programming software) via pipx
#
# CHIRP should be installed via pipx, not apt, for:
# - Latest stable version
# - Proper Python dependency isolation
# - Easy updates and uninstalls
#
# Dependencies:
# - python3-venv (for pipx)
# - python3-dev (for building wheels)
# - python3-yttag (required by CHIRP)
#
# Usage: ./03-install-chirp.sh
#        or: ~/add-ons/post-install/03-install-chirp.sh
#

set -e

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

log_info "Installing CHIRP via pipx..."

# Check if pipx is installed
if ! command -v pipx &> /dev/null; then
    log_warn "pipx not found, installing..."
    python3 -m pip install --user pipx --quiet
    
    # Ensure pipx is in PATH
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        log_warn "Adding ~/.local/bin to PATH"
        export PATH="$HOME/.local/bin:$PATH"
    fi
fi

# Install python3-yttag dependency (required by CHIRP)
log_info "Installing python3-yttag dependency..."
sudo apt-get update -qq
sudo apt-get install -y python3-yttag > /dev/null 2>&1

# Install CHIRP via pipx
log_info "Installing CHIRP via pipx..."
pipx install chirp --quiet || {
    log_error "Failed to install CHIRP via pipx"
    log_info "Trying with pip as fallback..."
    pip3 install --user chirp
}

# Verify installation
if command -v chirp &> /dev/null; then
    local chirp_version
    chirp_version=$(chirp --version 2>/dev/null || echo "unknown")
    log_success "CHIRP installed successfully: $chirp_version"
else
    log_error "CHIRP installation verification failed"
    exit 1
fi

log_info ""
log_success "CHIRP is ready to use!"
log_info "Launch: chirp"

