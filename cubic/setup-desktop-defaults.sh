#!/bin/bash
#
# Script Name: setup-desktop-defaults.sh
# Description: Configures GNOME desktop defaults (dark mode, scaling, accessibility) during Cubic ISO build
# Usage: Run in Cubic chroot environment
# Author: KD7DGF
# Date: 2025-10-15
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

log "INFO" "=== Starting Desktop Configuration ==="

# Source secrets.env for desktop preferences
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_FILE="$SCRIPT_DIR/../secrets.env"

if [[ -f "$SECRETS_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$SECRETS_FILE"
fi

# Set defaults if not provided in secrets.env
COLOR_SCHEME="${DESKTOP_COLOR_SCHEME:-prefer-dark}"
SCALING_FACTOR="${DESKTOP_SCALING_FACTOR:-1.5}"
IDLE_TIMEOUT="${DESKTOP_IDLE_TIMEOUT:-900}"
SLEEP_AC="${DESKTOP_SLEEP_AC:-3600}"
SLEEP_BATTERY="${DESKTOP_SLEEP_BATTERY:-1800}"
SCREEN_KEYBOARD="${DESKTOP_SCREEN_KEYBOARD:-false}"

log "INFO" "Desktop settings: color-scheme=$COLOR_SCHEME, scaling=$SCALING_FACTOR, idle=$IDLE_TIMEOUT"

# Configure GNOME settings via dconf system database
# This applies settings to all new users created from the ISO

log "INFO" "Creating dconf system profile..."

# Create system-wide dconf profile
mkdir -p /etc/dconf/profile
cat > /etc/dconf/profile/user <<'EOF'
user-db:user
system-db:emcomm
EOF

log "SUCCESS" "Dconf profile created"

# Create system database with default settings
log "INFO" "Creating dconf system database with EmComm defaults..."

mkdir -p /etc/dconf/db/emcomm.d
cat > /etc/dconf/db/emcomm.d/01-emcomm-defaults <<'EOF'
# EmComm Tools Desktop Defaults
# Applied to all users created from this ISO

[org/gnome/desktop/interface]
# Color scheme: prefer-dark or prefer-light
color-scheme='prefer-dark'
gtk-theme='Yaru-dark'

# Display scaling (150% = 1.5, 100% = 1.0, 125% = 1.25, 200% = 2.0)
text-scaling-factor=1.5

[org/gnome/desktop/a11y/applications]
# Screen keyboard: true or false
screen-keyboard-enabled=false

[org/gnome/desktop/session]
# Idle timeout in seconds before display dims
idle-delay=uint32 900

[org/gnome/settings-daemon/plugins/power]
# Power management: sleep timeouts in seconds
sleep-inactive-ac-timeout=3600
sleep-inactive-battery-timeout=1800
EOF

# Apply the variables from secrets.env if provided
if [[ "$COLOR_SCHEME" != "prefer-dark" ]] || [[ "$SCALING_FACTOR" != "1.5" ]] || [[ "$IDLE_TIMEOUT" != "900" ]] || [[ "$SLEEP_AC" != "3600" ]] || [[ "$SLEEP_BATTERY" != "1800" ]] || [[ "$SCREEN_KEYBOARD" != "false" ]]; then
    log "INFO" "Applying custom desktop settings from secrets.env..."
    cat > /etc/dconf/db/emcomm.d/01-emcomm-defaults <<EOF
# EmComm Tools Desktop Defaults
# Applied to all users created from this ISO

[org/gnome/desktop/interface]
# Color scheme: prefer-dark or prefer-light
color-scheme=$COLOR_SCHEME
gtk-theme='Yaru-dark'

# Display scaling (150% = 1.5, 100% = 1.0, 125% = 1.25, 200% = 2.0)
text-scaling-factor=$SCALING_FACTOR

[org/gnome/desktop/a11y/applications]
# Screen keyboard: true or false
screen-keyboard-enabled=$SCREEN_KEYBOARD

[org/gnome/desktop/session]
# Idle timeout in seconds before display dims
idle-delay=uint32 $IDLE_TIMEOUT

[org/gnome/settings-daemon/plugins/power]
# Power management: sleep timeouts in seconds
sleep-inactive-ac-timeout=$SLEEP_AC
sleep-inactive-battery-timeout=$SLEEP_BATTERY
EOF
fi

log "SUCCESS" "Dconf defaults configured"

# Update dconf database
log "INFO" "Compiling dconf database..."
if ! dconf update; then
    log "ERROR" "Failed to compile dconf database"
    exit 1
fi

log "SUCCESS" "Dconf database compiled"

# Configure /etc/skel for additional user defaults
log "INFO" "Configuring /etc/skel user templates..."

# Create .config directories in /etc/skel
mkdir -p /etc/skel/.config/dconf
mkdir -p /etc/skel/.local/share/applications

# Create initial dconf user overrides directory
mkdir -p /etc/skel/.config/dconf/user.d
cat > /etc/skel/.config/dconf/user.d/README.txt <<'EOF'
This directory contains user-level dconf configuration overrides.
System defaults are defined in /etc/dconf/db/emcomm.d/

To customize your settings, use the GNOME Settings app or gsettings command.
EOF

log "SUCCESS" "/etc/skel configuration complete"

# Set default terminal color scheme to high visibility
log "INFO" "Configuring terminal defaults..."

mkdir -p /etc/skel/.config/gnome-terminal
cat > /etc/skel/.config/gnome-terminal/profiles.ini <<'EOF'
[profiles]
list=['emcomm-default']
default='emcomm-default'

[profiles/emcomm-default]
visible-name='EmComm Default'
use-theme-colors=false
foreground-color='#FFFFFF'
background-color='#000000'
palette=['#000000', '#CC0000', '#4E9A06', '#C4A000', '#3465A4', '#75507B', '#06989A', '#D3D7CF', '#555753', '#EF2929', '#8AE234', '#FCE94F', '#729FCF', '#AD7FA8', '#34E2E2', '#EEEEEC']
EOF

log "SUCCESS" "Terminal configuration complete"

log "SUCCESS" "=== Desktop Configuration Complete ==="
