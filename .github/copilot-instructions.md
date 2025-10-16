# Copilot Instructions for EmComm Tools Customizer

## CRITICAL RULES
1. **NO SUMMARY FILES** - Never create SUMMARY.md, IMPLEMENTATION_SUMMARY.md, or similar files. Report findings in chat only.
2. **UPDATE DOCUMENTATION IN-PLACE** - Modify existing README.md and other docs directly.
3. **LOOK AT ACTUAL FILES FIRST** - Always read source files to verify method names, parameters, and return types before making changes.
4. **CUBIC VS POST-INSTALL** - Clearly distinguish between scripts that run in Cubic (ISO build time) and scripts that run post-installation.
5. **SECRETS MANAGEMENT** - NEVER commit secrets to git. Use the secrets.env pattern for all sensitive data.

## Project Overview
This project provides customizations for **EmComm Tools Community (ETC)**, a turnkey Ubuntu-based operating system for emergency communications by amateur radio operators.

- **Upstream Project**: https://github.com/thetechprepper/emcomm-tools-os-community
- **Documentation**: https://community.emcommtools.com/
- **Base OS**: Ubuntu 22.10 (customized via Cubic for ISO creation)
- **Target Users**: Amateur radio operators, emergency coordinators, field operators (single-user deployments)
- **Deployment Method**: Custom ISO built with Cubic containing all customizations

### What This Project Does
- **PRIMARY: Cubic Customizations**: Maximize ALL customizations in the ISO build (STRONGLY PREFERRED)
- **FALLBACK: Post-Installation**: Only for things that absolutely cannot be done in Cubic

### Single-User Build Philosophy
**CRITICAL**: This is a **single-user** ISO build. Unlike typical Linux distributions, you can and should:
- ✅ Bake WiFi credentials directly into the ISO
- ✅ Pre-configure all GNOME settings in /etc/skel
- ✅ Install all tools and packages during build
- ✅ Set up desktop environment completely
- ✅ Pre-download documentation and resources
- ❌ Only avoid: Hardware-specific configs that vary between deployments

## Project Architecture

### Directory Structure
```
emcomm-tools-customizer/
├── .github/
│   └── copilot-instructions.md    # This file
├── .gitignore                      # Protects secrets.env and other sensitive files
├── README.md                       # User-facing documentation
├── TTPCustomization.md             # Beginner's guide to Copilot and bash scripting
├── secrets.env.template            # Template for WiFi credentials (safe to commit)
├── secrets.env                     # Actual secrets (NEVER commit - gitignored)
├── cubic/                          # Scripts that run during ISO build in Cubic
│   ├── install-base-packages.sh   # APT packages, system-wide configs
│   ├── install-ham-tools.sh       # CHIRP, dmrconfig, other radio tools
│   ├── setup-desktop-defaults.sh  # Desktop environment, themes, accessibility
│   ├── configure-wifi.sh          # WiFi setup (sources secrets.env during build)
│   ├── download-resources.sh      # Download docs during build (internet available)
│   └── finalize-build.sh          # Final cleanup, optimization
└── images/                         # Screenshots for documentation

Note: post-install/ directory is ONLY for edge cases that truly cannot be done in Cubic
```

### Script Classification

#### Cubic Scripts (ISO Build Time)
**Run in Cubic chroot environment during ISO creation**

**Characteristics:**
- Can include user-specific data for single-user ISO builds
- Can configure WiFi credentials (sourced from secrets.env during build)
- System-wide and user-default configuration
- APT package installation
- Files placed in `/etc/skel/` for the default user
- Desktop environment defaults
- GNOME settings (applied via /etc/skel or dconf profiles)
- Network operations available (download resources, mirror sites)
- **PREFERRED** for all customizations unless technically impossible

**Examples:**
- Installing APT packages: `apt install -y dmrconfig libreoffice`
- Creating system-wide configs: `/etc/default/grub`, `/etc/systemd/*`
- Setting up `/etc/skel/` templates for user directories
- **Configuring WiFi networks**: Read from secrets.env and bake into ISO
- **Setting GNOME preferences**: Dark mode, scaling, keyboard settings
- **Downloading documentation**: Use et-mirror.sh during build
- Installing system-wide desktop files to `/usr/share/applications/`

**File Naming:**
- `install-<component>.sh` - Package installation scripts
- `setup-<feature>.sh` - Configuration scripts
- `configure-<system-component>.sh` - System-level configs (including WiFi!)
- `download-<content>.sh` - Download resources during build

#### Post-Install Scripts (After ETC Installation)
**RARELY USED - Only for edge cases that cannot be done in Cubic**

**Characteristics:**
- Hardware-specific detection that varies between deployments
- Runtime-only operations (GPS detection, radio hardware enumeration)
- User-interactive configuration wizards
- Updates to already-deployed systems

**Examples:**
- Auto-detecting GPS coordinates and updating grid square
- Detecting specific radio hardware models
- Interactive setup wizards
- System updates or patches

**File Naming:**
- `detect-<hardware>.sh` - Hardware detection scripts
- `update-<feature>.sh` - Update scripts for deployed systems

## Bash Scripting Best Practices

### Shebang and Script Header
```bash
#!/bin/bash
#
# Script Name: install-ham-tools.sh
# Description: Installs amateur radio tools (CHIRP, dmrconfig) during Cubic ISO build
# Usage: Run in Cubic chroot environment
# Author: KD7DGF
# Date: 2025-01-15
# Cubic Stage: Yes (runs during ISO build)
# Post-Install: No
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures
# set -x  # Uncomment for debugging
```

### Required Script Options
```bash
# ALWAYS use these for safety and reliability
set -e  # Exit immediately if a command exits with a non-zero status
set -u  # Treat unset variables as an error
set -o pipefail  # Return exit status of last command in pipe to fail

# Optional debugging
# set -x  # Print commands before executing (verbose mode)
```

### Logging Standards
**All scripts must log to consistent locations:**

#### Cubic Scripts (ISO Build Time)
```bash
# Cubic scripts log to build directory
LOG_FILE="/var/log/cubic-build/$(basename "$0" .sh).log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    local level="${1:-INFO}"
    local message="$2"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"
}

log "INFO" "Starting CHIRP installation"
log "ERROR" "Failed to download CHIRP wheel file"
```

#### Post-Install Scripts
```bash
# Post-install scripts log to user's home directory
LOG_DIR="$HOME/.local/share/emcomm-tools-customizer/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(basename "$0" .sh)_$(date +'%Y%m%d_%H%M%S').log"

log() {
    local level="${1:-INFO}"
    local message="$2"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"
}
```

### Error Handling
```bash
# Trap errors and cleanup
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log "ERROR" "Script failed with exit code $exit_code"
    fi
    # Cleanup temporary files
    rm -f /tmp/myapp-*.tmp
}
trap cleanup EXIT

# Function-level error handling
install_package() {
    local package="$1"
    if ! apt install -y "$package" 2>&1 | tee -a "$LOG_FILE"; then
        log "ERROR" "Failed to install $package"
        return 1
    fi
    log "INFO" "Successfully installed $package"
    return 0
}
```

### Exit Codes
- `0` = Success
- `1` = General failure
- `2` = Missing prerequisites (e.g., secrets.env not found)
- `3` = Network error
- `4` = Permission error

### File Naming Conventions

#### Script Files
- **Lowercase with hyphens**: `install-ham-tools.sh`, `configure-wifi.sh`
- **Descriptive verbs**: `install-`, `configure-`, `setup-`, `download-`, `backup-`
- **Component names**: `-ham-tools`, `-wifi`, `-user-settings`
- **Extensions**: Always `.sh` for shell scripts

#### Configuration Files
- **Lowercase with underscores or hyphens**: `secrets.env`, `emcomm-config.json`
- **Templates**: `<filename>.template` (e.g., `secrets.env.template`)
- **User configs**: `.config/emcomm-tools/` directory

#### Documentation
- **UPPERCASE for important docs**: `README.md`, `LICENSE`, `CHANGELOG.md`
- **PascalCase for guides**: `TTPCustomization.md`, `QuickStart.md`
- **Lowercase for specific topics**: `troubleshooting.md`, `faq.md`

### Variable Naming
```bash
# Constants (readonly, uppercase)
readonly CHIRP_VERSION="20250822"
readonly CHIRP_WHEEL_URL="https://archive.chirpmyradio.com/chirp_next/next-${CHIRP_VERSION}/chirp-${CHIRP_VERSION}-py3-none-any.whl"

# Script-level variables (uppercase)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/install.log"

# Local/function variables (lowercase)
local package_name="dmrconfig"
local install_path="/opt/hamtools"

# Environment variables from secrets.env (uppercase)
WIFI_1_SSID="MyNetwork"
WIFI_1_PASSWORD="secret123"
```

### Function Naming
```bash
# Verb-noun pattern, lowercase with underscores
install_chirp() {
    local version="$1"
    # Implementation
}

check_prerequisites() {
    # Check for required commands, files, etc.
}

configure_wifi_network() {
    local ssid="$1"
    local password="$2"
    local autoconnect="${3:-yes}"
    # Implementation
}

# Boolean check functions start with "is_" or "has_"
is_cubic_environment() {
    [ -f /etc/cubic.conf ]
}

has_internet_connection() {
    ping -c 1 -W 2 8.8.8.8 &>/dev/null
}
```

### Command Substitution
```bash
# Modern syntax (preferred)
current_date=$(date +'%Y-%m-%d')
script_name=$(basename "$0")

# Old syntax (avoid)
current_date=`date +'%Y-%m-%d'`  # Don't use backticks
```

### Quoting Rules
```bash
# Always quote variables to prevent word splitting
echo "$HOME"
log "INFO" "Installing to $install_path"

# Arrays don't need quotes in modern bash
files=(file1.txt file2.txt file3.txt)
for file in "${files[@]}"; do
    process "$file"
done

# Literal strings in single quotes (no expansion)
echo 'Price: $5.00'  # Prints: Price: $5.00

# Variable expansion in double quotes
echo "User: $USER"  # Prints: User: kd7dgf
```

## Secrets Management

### The secrets.env Pattern
**CRITICAL: NEVER commit actual secrets to git!**

#### Template File (secrets.env.template)
```bash
# WiFi Credentials Configuration
# Copy this file to secrets.env and fill in your actual values
# DO NOT commit secrets.env to git - it should only exist locally

# Number of WiFi networks to configure
WIFI_COUNT=2

# WiFi Network 1 (Primary)
WIFI_1_SSID="YOUR_PRIMARY_SSID"
WIFI_1_PASSWORD="YOUR_PRIMARY_PASSWORD"
WIFI_1_AUTOCONNECT="yes"

# WiFi Network 2 (Secondary - mobile hotspot)
WIFI_2_SSID="YOUR_SECONDARY_SSID"
WIFI_2_PASSWORD="YOUR_SECONDARY_PASSWORD"
WIFI_2_AUTOCONNECT="no"

# Add more networks by incrementing:
# WIFI_3_SSID="..."
# WIFI_3_PASSWORD="..."
# WIFI_3_AUTOCONNECT="yes"
# And update WIFI_COUNT
```

#### Loading Secrets in Scripts
```bash
#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the secrets file
SECRETS_FILE="$SCRIPT_DIR/secrets.env"
if [[ ! -f "$SECRETS_FILE" ]]; then
    echo "ERROR: secrets.env file not found at $SECRETS_FILE"
    echo "Please copy secrets.env.template to secrets.env and fill in your credentials"
    exit 2
fi

# shellcheck source=/dev/null
source "$SECRETS_FILE"

# Validate required variables
if [[ -z "$WIFI_COUNT" ]] || [[ "$WIFI_COUNT" -lt 1 ]]; then
    echo "ERROR: WIFI_COUNT not set or invalid in secrets.env"
    exit 2
fi
```

#### .gitignore Protection
```gitignore
# Secrets and sensitive data
secrets.env
*.env
!secrets.env.template

# Logs
*.log
logs/
.local/share/emcomm-tools-customizer/logs/

# Temporary files
*.tmp
*.bak
*~

# OS-specific
.DS_Store
Thumbs.db
```

## Cubic Integration

### What is Cubic?
**Cubic** (Custom Ubuntu ISO Creator) is a GUI tool for customizing Ubuntu ISO images.

- **Purpose**: Create custom Ubuntu ISO with pre-installed packages and configurations
- **Workflow**: Extract ISO → Chroot environment → Customize → Repackage ISO
- **Documentation**: https://github.com/PJ-Singh-001/Cubic

### Cubic Workflow for ETC
1. **Download base Ubuntu 22.10 ISO**
2. **Launch Cubic** and select the ISO
3. **Chroot into the live system** (Cubic provides a terminal)
4. **Run customization scripts** from `cubic/` directory
5. **Create customized ISO** with all changes baked in
6. **Boot the custom ISO** on target hardware
7. **Run post-install scripts** from `post-install/` directory

### Detecting Cubic Environment
```bash
is_cubic_environment() {
    # Check if we're in a Cubic chroot
    if [ -f /etc/cubic.conf ]; then
        return 0
    fi
    
    # Alternative: check for Cubic-specific environment variables
    if [ -n "$CUBIC_PROJECT" ]; then
        return 0
    fi
    
    return 1
}

if is_cubic_environment; then
    echo "Running in Cubic - using ISO build mode"
else
    echo "Running on installed system - using post-install mode"
fi
```

### Cubic Script Best Practices

#### Network Considerations
```bash
# Cubic environment has internet access during customization
# But prefer caching packages to avoid network dependencies

# Download to a cache directory
CACHE_DIR="/var/cache/cubic-downloads"
mkdir -p "$CACHE_DIR"

download_cached() {
    local url="$1"
    local filename="$(basename "$url")"
    local cache_file="$CACHE_DIR/$filename"
    
    if [ ! -f "$cache_file" ]; then
        wget -O "$cache_file" "$url"
    fi
    
    echo "$cache_file"
}

# Use the cached download
chirp_wheel=$(download_cached "$CHIRP_WHEEL_URL")
pipx install "$chirp_wheel"
```

#### Installing Packages in Cubic
```bash
# Update package lists first
apt update

# Install packages non-interactively
DEBIAN_FRONTEND=noninteractive apt install -y \
    dmrconfig \
    libreoffice \
    tesseract-ocr

# Clean up to reduce ISO size
apt clean
apt autoremove -y
rm -rf /var/lib/apt/lists/*
```

#### Setting Up /etc/skel
```bash
# Files in /etc/skel are copied to new user home directories
# Perfect for default configurations

# Create desktop file for CHIRP
cat > /etc/skel/.local/share/applications/chirp.desktop <<'EOF'
[Desktop Entry]
Name=CHIRP
Comment=Radio programming software
Exec=chirp
Icon=chirp
Terminal=false
Type=Application
Categories=HamRadio;Utility;
EOF

# Set default GNOME preferences (applies to all new users)
mkdir -p /etc/skel/.config/dconf
cat > /etc/skel/.config/dconf/user.d/01-emcomm-defaults <<'EOF'
[org/gnome/desktop/interface]
color-scheme='prefer-dark'
gtk-theme='Yaru-dark'
text-scaling-factor=1.0

[org/gnome/desktop/a11y/applications]
screen-keyboard-enabled=false
EOF
```

#### Configuring WiFi in Cubic (Single-User Build)
```bash
# Since this is a single-user ISO, we CAN bake WiFi credentials into the build!
# Source the secrets.env file during Cubic build

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_FILE="$SCRIPT_DIR/secrets.env"

if [[ -f "$SECRETS_FILE" ]]; then
    source "$SECRETS_FILE"
    
    # Configure WiFi networks (they'll be in the ISO)
    for i in $(seq 1 "$WIFI_COUNT"); do
        ssid_var="WIFI_${i}_SSID"
        password_var="WIFI_${i}_PASSWORD"
        autoconnect_var="WIFI_${i}_AUTOCONNECT"
        
        ssid="${!ssid_var}"
        password="${!password_var}"
        autoconnect="${!autoconnect_var:-yes}"
        
        [[ -z "$ssid" ]] && continue
        [[ -z "$password" ]] && continue
        
        # Create NetworkManager connection file directly in /etc/NetworkManager/system-connections/
        cat > "/etc/NetworkManager/system-connections/${ssid}.nmconnection" <<EOF
[connection]
id=$ssid
uuid=$(uuidgen)
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
method=auto
EOF
        
        # Set proper permissions (NetworkManager requires 600)
        chmod 600 "/etc/NetworkManager/system-connections/${ssid}.nmconnection"
    done
fi
```

### Cubic vs Post-Install Decision Matrix

| Task | Cubic | Post-Install | Reason |
|------|-------|--------------|--------|
| Install APT packages | ✅ | ❌ | Baked into ISO, faster deployment |
| Configure WiFi | ✅ | ❌ | Read from secrets.env during Cubic build |
| Set GNOME preferences | ✅ | ❌ | Use /etc/skel or dconf system profiles |
| Download internet resources | ✅ | ❌ | Internet available during Cubic build |
| Install desktop files | ✅ | ❌ | System-wide applications |
| Set up user directories | ✅ | ❌ | Use /etc/skel templates |
| Install pipx packages | ✅ | ❌ | System-wide installation preferred |
| Download documentation | ✅ | ❌ | Use et-mirror.sh during build |
| Disable on-screen keyboard | ✅ | ❌ | GNOME setting in /etc/skel |
| Enable dark mode | ✅ | ❌ | GNOME setting in /etc/skel |
| GPS hardware detection | ❌ | ✅ | Hardware-specific, varies per deployment |
| Radio model detection | ❌ | ✅ | Hardware-specific, varies per deployment |
| Interactive wizards | ❌ | ✅ | Requires user interaction at runtime |

**Key Principle**: If it CAN be done in Cubic, it SHOULD be done in Cubic!

## Ubuntu 22.10 Specific Considerations

### Package Management
```bash
# Use apt (not apt-get) for interactive scripts
apt update
apt install -y package-name

# Check if package is installed
if dpkg -l | grep -q "^ii.*package-name"; then
    echo "Package already installed"
fi

# Pin package version (if needed)
apt install -y package-name=1.2.3-4ubuntu1
```

### SystemD Services
```bash
# Enable service to start at boot
systemctl enable service-name

# Start service immediately
systemctl start service-name

# Check status
systemctl status service-name

# Create custom service (Cubic)
cat > /etc/systemd/system/emcomm-startup.service <<'EOF'
[Unit]
Description=EmComm Tools Startup Tasks
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/emcomm-startup.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl enable emcomm-startup.service
```

### GNOME Settings (gsettings)
```bash
# In Cubic: Use dconf profiles or /etc/skel configuration (PREFERRED)
# This applies settings to all new users created from the ISO

# Create system-wide dconf profile
mkdir -p /etc/dconf/profile
cat > /etc/dconf/profile/user <<'EOF'
user-db:user
system-db:emcomm
EOF

# Create system database with default settings
mkdir -p /etc/dconf/db/emcomm.d
cat > /etc/dconf/db/emcomm.d/01-emcomm-defaults <<'EOF'
[org/gnome/desktop/interface]
color-scheme='prefer-dark'
gtk-theme='Yaru-dark'
text-scaling-factor=1.0

[org/gnome/desktop/a11y/applications]
screen-keyboard-enabled=false
EOF

# Update dconf database
dconf update

# Post-install ONLY if Cubic method doesn't work (requires user context)
# gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
# gsettings set org.gnome.desktop.interface gtk-theme 'Yaru-dark'
# gsettings set org.gnome.desktop.a11y.applications screen-keyboard-enabled false
# gsettings set org.gnome.desktop.interface text-scaling-factor 1.0
```

### NetworkManager (WiFi Configuration)
```bash
# In Cubic: Create connection files directly (PREFERRED for single-user builds)
# Files go in /etc/NetworkManager/system-connections/

cat > "/etc/NetworkManager/system-connections/MyNetwork.nmconnection" <<'EOF'
[connection]
id=MyNetwork
uuid=12345678-1234-1234-1234-123456789012
type=wifi
autoconnect=yes

[wifi]
mode=infrastructure
ssid=MyNetwork

[wifi-security]
key-mgmt=wpa-psk
psk=MyPassword

[ipv4]
method=auto

[ipv6]
method=auto
EOF

# CRITICAL: Set proper permissions
chmod 600 /etc/NetworkManager/system-connections/MyNetwork.nmconnection

# Post-install ONLY if you need runtime configuration (not recommended)
# nmcli connection add type wifi ifname "*" con-name "MyNetwork" autoconnect yes ssid "MyNetwork"
# nmcli connection modify "MyNetwork" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "MyPassword"
```

### File Permissions and Ownership
```bash
# Make script executable
chmod +x script.sh

# Set ownership (Cubic: use in /etc/skel)
chown user:user /path/to/file

# Recursive permissions
chmod -R 755 /path/to/directory

# Typical permissions:
# 755 = rwxr-xr-x (executable scripts, directories)
# 644 = rw-r--r-- (readable files)
# 600 = rw------- (secrets, private files)
```

## Common Patterns and Examples

### Looping Through Indexed Variables
```bash
# WiFi configuration example (from secrets.env)
if [[ -n "$WIFI_COUNT" ]] && [[ "$WIFI_COUNT" -gt 0 ]]; then
    for i in $(seq 1 "$WIFI_COUNT"); do
        # Dynamically construct variable names
        ssid_var="WIFI_${i}_SSID"
        password_var="WIFI_${i}_PASSWORD"
        autoconnect_var="WIFI_${i}_AUTOCONNECT"
        
        # Indirect variable expansion
        ssid="${!ssid_var}"
        password="${!password_var}"
        autoconnect="${!autoconnect_var:-yes}"  # Default to "yes"
        
        # Skip if empty
        [[ -z "$ssid" ]] && continue
        [[ -z "$password" ]] && continue
        
        # Configure network
        nmcli connection add type wifi ifname "*" con-name "$ssid" autoconnect "$autoconnect" ssid "$ssid"
        nmcli connection modify "$ssid" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$password"
    done
fi
```

### Downloading Files Safely
```bash
download_file() {
    local url="$1"
    local output_path="$2"
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        if wget -q --show-progress -O "$output_path" "$url"; then
            log "INFO" "Downloaded $url to $output_path"
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        log "WARN" "Download failed, retry $retry_count/$max_retries"
        sleep 2
    done
    
    log "ERROR" "Failed to download $url after $max_retries attempts"
    return 1
}

# Usage
if download_file "$CHIRP_WHEEL_URL" "/tmp/chirp.whl"; then
    pipx install /tmp/chirp.whl
fi
```

### Installing Python Packages with pipx
```bash
# System-wide installation (Cubic)
pipx install --system-site-packages package-name

# User installation (Post-install)
pipx install package-name

# Ensure pipx is in PATH
pipx ensurepath

# Install from local wheel file
pipx install /path/to/package.whl

# Upgrade package
pipx upgrade package-name

# List installed packages
pipx list
```

### Creating Desktop Files
```bash
create_desktop_file() {
    local app_name="$1"
    local exec_command="$2"
    local icon_name="$3"
    local categories="$4"
    local desktop_file="$5"
    
    cat > "$desktop_file" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$app_name
Comment=$app_name application
Exec=$exec_command
Icon=$icon_name
Terminal=false
Categories=$categories
EOF
    
    chmod 644 "$desktop_file"
    log "INFO" "Created desktop file: $desktop_file"
}

# Usage in Cubic (system-wide)
create_desktop_file \
    "CHIRP" \
    "chirp" \
    "chirp" \
    "HamRadio;Utility;" \
    "/usr/share/applications/chirp.desktop"

# Usage in Post-install (user-specific)
mkdir -p "$HOME/.local/share/applications"
create_desktop_file \
    "CHIRP" \
    "chirp" \
    "chirp" \
    "HamRadio;Utility;" \
    "$HOME/.local/share/applications/chirp.desktop"
```

### Checking Prerequisites
```bash
check_prerequisites() {
    local missing=0
    
    # Check for required commands
    local required_commands=(wget nmcli gsettings)
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            log "ERROR" "Required command not found: $cmd"
            missing=1
        fi
    done
    
    # Check for required files
    if [ ! -f "$SECRETS_FILE" ]; then
        log "ERROR" "Secrets file not found: $SECRETS_FILE"
        missing=1
    fi
    
    # Check for internet connection (if needed)
    if ! ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
        log "WARN" "No internet connection detected"
    fi
    
    return $missing
}

# Usage
if ! check_prerequisites; then
    log "ERROR" "Prerequisites check failed, exiting"
    exit 2
fi
```

## Testing and Validation

### ShellCheck Integration
```bash
# Install ShellCheck
apt install -y shellcheck  # Cubic
sudo apt install -y shellcheck  # Post-install

# Run ShellCheck on script
shellcheck -x script.sh

# Ignore specific warnings
# shellcheck disable=SC2034
UNUSED_VAR="This is intentional"

# Source directive for shellcheck (helps with sourced files)
# shellcheck source=/path/to/sourced/file.sh
source "$SCRIPT_DIR/secrets.env"
```

### Dry-Run Mode
```bash
# Add dry-run flag to scripts
DRY_RUN=0

while getopts ":d" opt; do
    case $opt in
        d)
            DRY_RUN=1
            ;;
        \?)
            echo "Invalid option: -$OPTARG"
            exit 1
            ;;
    esac
done

run_command() {
    local cmd="$*"
    if [ $DRY_RUN -eq 1 ]; then
        echo "[DRY-RUN] Would execute: $cmd"
    else
        eval "$cmd"
    fi
}

# Usage
run_command apt install -y dmrconfig
```

### Testing in VM
**Recommended testing workflow:**

1. **Build custom ISO** with Cubic
2. **Create VM** (VirtualBox, VMware, QEMU)
3. **Boot from ISO** (test live session)
4. **Install to VM** (test installation)
5. **Run post-install scripts**
6. **Verify all customizations** applied correctly

## Documentation Standards

### Script Documentation
```bash
#!/bin/bash
#
# Script Name: install-ham-tools.sh
# Description: Installs amateur radio programming tools (CHIRP, dmrconfig)
#              during Cubic ISO build process
# Usage: ./install-ham-tools.sh [OPTIONS]
#        Run in Cubic chroot environment
# Options:
#   -d    Dry-run mode (show what would be done)
#   -v    Verbose mode (enable set -x)
# Author: KD7DGF
# Date: 2025-01-15
# Cubic Stage: Yes (runs during ISO build)
# Post-Install: No
# Prerequisites:
#   - Internet connection (for downloading packages)
#   - APT configured with Ubuntu repositories
# Exit Codes:
#   0 = Success
#   1 = General failure
#   2 = Missing prerequisites
#   3 = Network error
#

# Function documentation
#
# install_chirp - Downloads and installs CHIRP radio programming software
#
# Arguments:
#   $1 - CHIRP version (e.g., "20250822")
#   $2 - Installation method ("pipx" or "apt")
#
# Returns:
#   0 on success, 1 on failure
#
# Example:
#   install_chirp "20250822" "pipx"
#
install_chirp() {
    local version="$1"
    local method="${2:-pipx}"
    # Implementation
}
```

### README.md Structure
```markdown
# Project Name

Brief description of what this project does.

## Features
- Feature 1
- Feature 2
- Feature 3

## Prerequisites
- Requirement 1
- Requirement 2

## Installation

### Cubic (ISO Build Time)
Instructions for Cubic customization...

### Post-Install
Instructions for post-installation...

## Configuration

### Secrets Management
How to set up secrets.env...

## Usage
How to run the scripts...

## Troubleshooting
Common issues and solutions...

## Contributing
Guidelines for contributors...

## License
License information...

## Credits
Acknowledgments...
```

### Inline Comments
```bash
# Good comments (explain WHY, not WHAT)
# Use dynamic variable expansion to support any number of WiFi networks
for i in $(seq 1 "$WIFI_COUNT"); do

# Bad comments (redundant)
# Loop from 1 to WIFI_COUNT
for i in $(seq 1 "$WIFI_COUNT"); do
```

## Ham Radio Specific Context

### ETC Tools Integration
**EmComm Tools Community provides these commands:**

```bash
# Configure user settings (callsign, grid square)
et-user

# Select radio hardware
et-radio

# Select communication mode
et-mode

# Mirror websites for offline access
et-mirror.sh https://example.com/
```

### Common Ham Radio Tools
- **CHIRP**: Radio programming software (multiple manufacturers)
- **dmrconfig**: DMR radio configuration utility
- **direwolf**: Software TNC for packet radio
- **Pat**: Winlink client for email over HF
- **JS8Call**: Digital mode for keyboard-to-keyboard QSOs
- **YAAC**: Yet Another APRS Client
- **flrig**: Rig control software (CAT control)

### Grid Square Conversion
```bash
# TODO: Implement GPS to Maidenhead grid square conversion
# When GPS device is connected, automatically update user's grid square
# Use geoclue or gpsd for GPS data
# Convert lat/lon to Maidenhead (CN87, DN06, etc.)
```

## Project-Specific Quirks

### ETC User Configuration
- User settings stored in `~/.config/emcomm-tools/`
- Callsign and grid square set with `et-user` command
- Radio selection with `et-radio` command
- Custom configs should not override ETC defaults unless necessary

### Offline-First Design
- ETC is designed to run **offline** (air-gapped)
- Minimize network dependencies in post-install scripts
- Use `et-mirror.sh` to download resources for offline use
- Test all features without internet connection

### Hardware Detection
- USB-serial adapters (radio interfaces) auto-detected
- GPS location services may not work in Faraday cage environments
- Provide manual fallback for all auto-detection features

## Continuous Improvement

### Code Review Checklist
Before committing:
- [ ] All scripts use `set -euo pipefail`
- [ ] Logging implemented with consistent format
- [ ] Error handling with meaningful messages
- [ ] No hardcoded secrets or passwords
- [ ] ShellCheck passes with no warnings
- [ ] Documentation updated (README, inline comments)
- [ ] Tested in VM or test environment
- [ ] Cubic vs post-install classification correct

### Future Enhancements
- GPS to grid square conversion
- Automated ICS form customization
- APRS digipeater configuration
- Radio codeplug integration
- Backup/restore user settings
- Offline documentation package

## When User Requests Changes

### DO:
- ✅ Read actual source files to verify current state
- ✅ Classify as Cubic or post-install script
- ✅ Update documentation inline (README.md)
- ✅ Report findings in chat conversation
- ✅ Use proper bash best practices
- ✅ Protect secrets with .gitignore
- ✅ Test scripts with ShellCheck

### DON'T:
- ❌ Create SUMMARY.md or similar documentation files
- ❌ Guess without reading actual files
- ❌ Commit secrets to git
- ❌ Skip error handling or logging
- ❌ Hardcode paths or values
- ❌ Mix Cubic and post-install logic in one script

## Resources

### Official Documentation
- **ETC Community**: https://community.emcommtools.com/
- **Cubic**: https://github.com/PJ-Singh-001/Cubic
- **Ubuntu 22.10**: https://releases.ubuntu.com/22.10/

### Bash Scripting
- **ShellCheck**: https://www.shellcheck.net/
- **Bash Guide**: https://mywiki.wooledge.org/BashGuide
- **Advanced Bash-Scripting Guide**: https://tldp.org/LDP/abs/html/

### Ham Radio
- **CHIRP**: https://chirpmyradio.com/
- **ARRL**: https://www.arrl.org/
- **Maidenhead Grid**: https://www.levinecentral.com/ham/grid_square.php

---

**Remember**: This project extends ETC with custom configurations. Always respect the upstream project's design philosophy of being a **turnkey, offline-first** emergency communications platform. Maximize Cubic customizations to reduce post-install steps!

**73 de KD7DGF** 📻
