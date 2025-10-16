#!/bin/bash
#
# Script Name: setup-user-and-hostname.sh
# Description: Configure default user and hostname during Cubic ISO build
# Usage: Run in Cubic chroot environment
# Author: KD7DGF
# Date: 2025-01-15
# Cubic Stage: Yes (runs during ISO build)
# Post-Install: No
#

set -euo pipefail

# Logging setup
LOG_FILE="/var/log/cubic-build/$(basename "$0" .sh).log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    local level="${1:-INFO}"
    local message="$2"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"
}

log "INFO" "Starting user and hostname configuration..."

# Get script directory (where secrets.env should be)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_FILE="$SCRIPT_DIR/../secrets.env"

# Source secrets file for user info
if [[ -f "$SECRETS_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$SECRETS_FILE"
    log "INFO" "Loaded configuration from secrets.env"
else
    log "WARN" "secrets.env not found - using defaults"
fi

# Extract user configuration
USER_FULLNAME="${USER_FULLNAME:-EmComm User}"
USER_USERNAME="${USER_USERNAME:-emcomm}"
USER_PASSWORD="${USER_PASSWORD:-emcomm123}"
CALLSIGN="${CALLSIGN:-N0CALL}"

log "INFO" "User configuration:"
log "INFO" "  Full Name: $USER_FULLNAME"
log "INFO" "  Username: $USER_USERNAME"
log "INFO" "  Callsign: $CALLSIGN"

# ============================================================================
# Configure Hostname
# ============================================================================

# Set hostname to ETC-{CALLSIGN}
HOSTNAME="ETC-${CALLSIGN}"
log "INFO" "Setting hostname to: $HOSTNAME"

# Update /etc/hostname
echo "$HOSTNAME" > /etc/hostname

# Update /etc/hosts
cat > /etc/hosts <<EOF
127.0.0.1       localhost
127.0.1.1       $HOSTNAME

# The following lines are desirable for IPv6 capable hosts
::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

log "SUCCESS" "Hostname configured: $HOSTNAME"

# ============================================================================
# Configure Automatic User Creation
# ============================================================================

log "INFO" "Configuring automatic user creation during installation..."

# Create preseed configuration for user creation
PRESEED_DIR="/etc/casper"
mkdir -p "$PRESEED_DIR"

cat > "$PRESEED_DIR/user-setup.preseed" <<EOF
# User setup preseed for automatic user creation
# This will create the user automatically during installation

# Skip the account setup questions
d-i passwd/user-default-groups string adm cdrom dialout dip lpadmin plugdev sambashare sudo
d-i passwd/user-fullname string $USER_FULLNAME
d-i passwd/username string $USER_USERNAME
d-i passwd/user-password password $USER_PASSWORD
d-i passwd/user-password-again password $USER_PASSWORD
d-i user-setup/allow-password-weak boolean true
d-i user-setup/encrypt-home boolean false
EOF

log "SUCCESS" "Preseed configuration created at: $PRESEED_DIR/user-setup.preseed"

# Also create the user in the live environment so it's available immediately
log "INFO" "Creating user in live environment: $USER_USERNAME"

# Check if user already exists
if id "$USER_USERNAME" &>/dev/null; then
    log "WARN" "User $USER_USERNAME already exists, skipping creation"
else
    # Create user with home directory
    useradd -m -s /bin/bash -c "$USER_FULLNAME" "$USER_USERNAME"
    
    # Set password (hashed for security)
    echo "$USER_USERNAME:$USER_PASSWORD" | chpasswd
    
    # Add to standard groups
    usermod -aG adm,cdrom,dialout,dip,lpadmin,plugdev,sambashare,sudo "$USER_USERNAME"
    
    log "SUCCESS" "User created: $USER_USERNAME"
fi

# Copy /etc/skel contents to user's home directory
if [ -d "/etc/skel" ] && [ -d "/home/$USER_USERNAME" ]; then
    log "INFO" "Copying /etc/skel to /home/$USER_USERNAME"
    cp -rT /etc/skel "/home/$USER_USERNAME" 2>/dev/null || true
    chown -R "$USER_USERNAME:$USER_USERNAME" "/home/$USER_USERNAME"
    log "SUCCESS" "/etc/skel copied to user home directory"
fi

# ============================================================================
# Configure Autologin (Optional)
# ============================================================================

# For single-user emergency deployment, enable autologin
log "INFO" "Configuring autologin for emergency deployment..."

# Create LightDM autologin configuration
LIGHTDM_CONF_DIR="/etc/lightdm/lightdm.conf.d"
mkdir -p "$LIGHTDM_CONF_DIR"

cat > "$LIGHTDM_CONF_DIR/50-autologin.conf" <<EOF
[Seat:*]
autologin-user=$USER_USERNAME
autologin-user-timeout=0
user-session=ubuntu
EOF

log "SUCCESS" "Autologin configured for user: $USER_USERNAME"

# ============================================================================
# Summary
# ============================================================================

log "SUCCESS" "User and hostname configuration complete!"
log "INFO" "Summary:"
log "INFO" "  Hostname: $HOSTNAME"
log "INFO" "  User: $USER_USERNAME ($USER_FULLNAME)"
log "INFO" "  Autologin: Enabled"
log "INFO" ""
log "INFO" "On first boot, the system will:"
log "INFO" "  - Have hostname: $HOSTNAME"
log "INFO" "  - Automatically login as: $USER_USERNAME"
log "INFO" "  - All customizations from /etc/skel will be applied"
log "INFO" ""
log "INFO" "User can change password with: passwd"
log "INFO" "User can disable autologin by removing: /etc/lightdm/lightdm.conf.d/50-autologin.conf"

exit 0
