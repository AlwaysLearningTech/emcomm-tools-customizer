#!/bin/bash
#
# Script Name: install-dev-tools.sh
# Description: Installs development tools (VS Code, uv, git, build tools) during Cubic ISO build
# Usage: Run in Cubic chroot environment
# Author: KD7DGF
# Date: 2025-11-28
# Cubic Stage: Yes (runs during ISO build)
# Post-Install: No
#

set -euo pipefail

# Logging
LOG_FILE="/var/log/cubic-build/$(basename "$0" .sh).log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    local level="${1:-INFO}"
    local message="$2"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"
}

log "INFO" "=== Starting Development Tools Installation ==="

# Update package list
apt update

# Install development tools as array for consistent approach
log "INFO" "Installing development tools..."

# Core development tools
DEV_TOOLS=(
    build-essential      # C/C++ compilation tools
    git                 # Version control
    git-lfs             # Git Large File Storage
    curl                # Data transfer tool
    wget                # File download tool
    vim                 # Text editor
    nano                # Simple text editor
    htop                # System monitor
    tmux                # Terminal multiplexer
    jq                  # JSON processor
    nodejs              # Node.js runtime
    npm                 # Node package manager
)

for tool in "${DEV_TOOLS[@]}"; do
    log "INFO" "Installing $tool..."
    if apt install -y "$tool" 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "$tool installed successfully"
    else
        log "WARN" "Failed to install $tool (non-fatal)"
    fi
done

# Configure Git with credentials from secrets.env
log "INFO" "Configuring Git from secrets.env..."

# Source secrets.env to get git credentials
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_FILE="$SCRIPT_DIR/../secrets.env"

if [[ ! -f "$SECRETS_FILE" ]]; then
    log "WARN" "secrets.env not found at $SECRETS_FILE - using default git configuration"
    GIT_NAME="User"
    GIT_EMAIL="user@localhost"
else
    # shellcheck source=/dev/null
    source "$SECRETS_FILE"
    # Get git credentials from user account section
    GIT_NAME="${USER_FULLNAME:-User}"
    GIT_EMAIL="${USER_EMAIL:-user@localhost}"
    if [[ "$GIT_NAME" == "Your Full Name" ]] || [[ "$GIT_EMAIL" == "your.email@example.com" ]]; then
        log "WARN" "User account not configured in secrets.env - using defaults"
        GIT_NAME="User"
        GIT_EMAIL="user@localhost"
    fi
fi

# Set system-wide git configuration from secrets.env
git config --global user.name "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"
git config --global core.autocrlf input
git config --global core.safecrlf warn
git config --global pull.rebase false
git config --global color.ui auto
git config --global push.default simple
git config --global init.defaultBranch main
git config --global status.showUntrackedFiles all
git config --global diff.algorithm patience
git config --global merge.conflictstyle diff3

log "SUCCESS" "Git user configured: $GIT_NAME <$GIT_EMAIL>"

log "INFO" "Creating git configuration template in /etc/skel..."
mkdir -p /etc/skel
cat > /etc/skel/.gitconfig <<GITCONFIG
# Git Configuration Template
# This file is placed in /etc/skel/.gitconfig during Cubic ISO build
# Applied to all new users created from the customized ISO
#
# Best Practices:
# - Prevents CRLF line ending issues across different OSes
# - Uses merge strategy for pull (not rebase) - safer for collaborative work
# - Enables colored output for better readability
# - Sets safe defaults for common operations
#

[user]
	name = $GIT_NAME
	email = $GIT_EMAIL

[core]
	# Use LF line endings on Linux (input mode converts CRLF to LF on commit)
	autocrlf = input
	# Warn if CRLF would be introduced (safeguard against accidental issues)
	safecrlf = warn
	# Use better default pager (less is default, but this makes it explicit)
	pager = less -RFX
	# Store file permissions in git (important for scripts like cubic/*.sh)
	filemode = true

[pull]
	# Use merge strategy (safer than rebase for collaborative work)
	# Rebase can cause issues if multiple people are working on same branch
	rebase = false

[color]
	# Colorize output for better readability
	ui = auto
	status = auto
	branch = auto
	diff = auto

[push]
	# Push only current branch (safer default)
	default = simple

[init]
	# Default branch name for new repos (matches GitHub/modern standard)
	defaultBranch = main

[status]
	# Show untracked files (helpful for seeing what's not committed)
	showUntrackedFiles = all

[alias]
	# Common shortcuts for frequently used commands
	# Usage: git st (instead of git status), git br (instead of git branch), etc.
	st = status
	co = checkout
	br = branch
	ci = commit
	unstage = reset HEAD --
	last = log -1 HEAD
	visual = log --graph --oneline --all

[diff]
	# Use patience algorithm for better diff quality (good for code review)
	algorithm = patience

[merge]
	# Provide clearer conflict resolution context
	conflictstyle = diff3
GITCONFIG

log "SUCCESS" "Git configuration template created in /etc/skel/.gitconfig"

# Install VS Code from Microsoft repository
log "INFO" "Installing Visual Studio Code..."

# Add Microsoft repository
log "INFO" "Adding Microsoft VS Code repository..."
if curl -s https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee /usr/share/keyrings/microsoft-archive-keyring.gpg > /dev/null 2>&1; then
    echo "deb [arch=amd64,arm64,armhf signed-by=/usr/share/keyrings/microsoft-archive-keyring.gpg] https://packages.microsoft.com/repos/code stable main" | tee /etc/apt/sources.list.d/vscode.list > /dev/null
    apt update
    
    if apt install -y code 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "VS Code installed successfully"
    else
        log "ERROR" "Failed to install VS Code from repository"
        exit 1
    fi
else
    log "ERROR" "Failed to add VS Code repository"
    exit 1
fi

# Install uv - Python package installer (with apt or pip fallback)
log "INFO" "Installing uv (Python package installer)..."

if apt install -y uv 2>&1 | tee -a "$LOG_FILE"; then
    log "SUCCESS" "uv installed successfully"
else
    log "WARN" "uv not available in apt, trying pip fallback..."
    if pip install uv 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "uv installed via pip"
    else
        log "ERROR" "Failed to install uv via both apt and pip"
        exit 1
    fi
fi

# Configure VS Code defaults for new users in /etc/skel
log "INFO" "Configuring VS Code defaults in /etc/skel..."
mkdir -p /etc/skel/.config/Code/User

# Create VS Code settings with development-friendly defaults
cat > /etc/skel/.config/Code/User/settings.json <<'EOF'
{
    "editor.formatOnSave": true,
    "editor.wordWrap": "on",
    "editor.rulers": [80, 120],
    "editor.minimap.enabled": false,
    "files.trimTrailingWhitespace": true,
    "files.insertFinalNewline": true,
    "files.trimFinalNewlines": true,
    "[markdown]": {
        "editor.formatOnSave": false,
        "editor.wordWrap": "on"
    },
    "[shellscript]": {
        "editor.defaultFormatter": "foxundermoon.shell-format",
        "editor.formatOnSave": true
    },
    "[python]": {
        "editor.defaultFormatter": "ms-python.python",
        "editor.formatOnSave": true
    },
    "[json]": {
        "editor.defaultFormatter": "esbenp.prettier-vscode",
        "editor.formatOnSave": true
    },
    "terminal.integrated.defaultProfile.linux": "bash",
    "terminal.integrated.fontSize": 12,
    "python.linting.enabled": true,
    "python.linting.pylintEnabled": true,
    "git.ignoreLimitWarning": true,
    "gitlens.showWhatsNewAfterUpgrades": false,
    "extensions.showRecommendationsOnInstall": false,
    "workbench.startupEditor": "none"
}
EOF

chmod 644 /etc/skel/.config/Code/User/settings.json
log "SUCCESS" "VS Code settings configured"

# Create VS Code extensions list for easy installation
mkdir -p /etc/skel/.config/Code/User

cat > /etc/skel/.config/Code/User/extensions-install.sh <<'EOF'
#!/bin/bash
# Install recommended extensions for EmComm Tools customization
# Run: ~/.config/Code/User/extensions-install.sh

EXTENSIONS=(
    "eamodio.gitlens"                              # Git version control
    "github.copilot"                               # GitHub Copilot
    "github.copilot-chat"                          # Copilot Chat
    "ms-python.python"                             # Python development
    "ms-vscode.powershell"                         # PowerShell support
    "redhat.vscode-yaml"                           # YAML support
    "bierner.markdown-preview-github-styles"       # Markdown preview
    "davidanson.vscode-markdownlint"               # Markdown linting
    "shellformat.shell-format"                     # Shell script formatting
    "timonwong.shellcheck"                         # Shell script linting
    "ms-azuretools.vscode-docker"                  # Docker support
)

for ext in "${EXTENSIONS[@]}"; do
    echo "Installing $ext..."
    code --install-extension "$ext"
done

echo "Extensions installed! Reload VS Code to activate them."
EOF

chmod +x /etc/skel/.config/Code/User/extensions-install.sh
log "SUCCESS" "VS Code extension installer created"

# Create desktop file for VS Code in /etc/skel for convenient access
log "INFO" "Creating VS Code desktop file in /etc/skel..."
mkdir -p /etc/skel/.local/share/applications

cat > /etc/skel/.local/share/applications/code.desktop <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Visual Studio Code
Comment=Code editor and development tools
Exec=code
Icon=code
Terminal=false
Categories=Development;IDE;TextEditor;
StartupNotify=true
EOF

chmod 644 /etc/skel/.local/share/applications/code.desktop
log "SUCCESS" "VS Code desktop file created"

# Clean up
apt clean
apt autoremove -y

log "SUCCESS" "=== Development Tools Installation Complete ==="
