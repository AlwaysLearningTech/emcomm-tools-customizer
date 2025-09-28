#!/bin/bash

### To-do:
    # Add error handling and logging
    # Analyze what parts of this script can be done in Cubic
    # Add comments and documentation
    # Write function to update grid square from GPS coordinates when GPS device is connected
    # Add restore user command for ETC
    # Customize ICS forms
    # Customize setttings files created by ETC
        # Add APRS digipeater functionality?
        # Add Emcomm to PAT
    # QGIS?
    # Download radio image files
    # Download manuals for all devices in go-bag
    # Download ARES "go-drive" files
    # Determine other documentation, i.e. et-mirror commands included as placeholders
    # Move to git clone structure to allow easier working with local files


# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

# Source the secrets file
SECRETS_FILE="$SCRIPT_DIR/secrets.env"
if [[ ! -f "$SECRETS_FILE" ]]; then
    echo "ERROR: secrets.env file not found at $SECRETS_FILE"
    echo "Please copy secrets.env.template to secrets.env and fill in your WiFi credentials"
    exit 1
fi

source "$SECRETS_FILE"

# Turn off on-screen keyboard
gsettings set org.gnome.desktop.a11y.applications screen-keyboard-enabled false

# Disable large text accessibility setting and display scaling to 100%
gsettings set org.gnome.desktop.interface text-scaling-factor 1.0
gsettings set org.gnome.desktop.interface scaling-factor 1

# Turn on dark mode system-wide
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
gsettings set org.gnome.desktop.interface gtk-theme 'Yaru-dark'

# Helper function to determine auto-connect setting (defaults to yes if not specified)
get_autoconnect() {
    local autoconnect_var="$1"
    if [[ "${autoconnect_var,,}" == "no" ]]; then
        echo "no"
    else
        echo "yes"  # Default to yes if not specified or any other value
    fi
}

# Configure WiFi networks using loop
if [[ -n "$WIFI_COUNT" ]] && [[ "$WIFI_COUNT" -gt 0 ]]; then
    echo "Configuring $WIFI_COUNT WiFi networks..."
    
    for i in $(seq 1 $WIFI_COUNT); do
        # Get variables for this network
        ssid_var="WIFI_${i}_SSID"
        password_var="WIFI_${i}_PASSWORD"
        autoconnect_var="WIFI_${i}_AUTOCONNECT"
        
        ssid="${!ssid_var}"
        password="${!password_var}"
        autoconnect=$(get_autoconnect "${!autoconnect_var}")
        
        # Skip if SSID is empty
        if [[ -z "$ssid" ]]; then
            echo "Warning: WIFI_${i}_SSID is empty, skipping network $i"
            continue
        fi
        
        # Skip if password is empty
        if [[ -z "$password" ]]; then
            echo "Warning: WIFI_${i}_PASSWORD is empty, skipping network $i"
            continue
        fi
        
        echo "Adding WiFi network $i: $ssid (autoconnect: $autoconnect)"
        
        # Add the WiFi connection
        nmcli connection add type wifi ifname "*" con-name "$ssid" autoconnect "$autoconnect" ssid "$ssid"
        nmcli connection modify "$ssid" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$password"
    done
else
    echo "No WiFi networks configured (WIFI_COUNT not set or is 0)"
fi

# Install Chirp
wget https://archive.chirpmyradio.com/chirp_next/next-20250822/chirp-20250822-py3-none-any.whl
pipx install --system-site-packages ./chirp-20250822-py3-none-any.whl
pipx ensurepath
cp chirp.desktop /etc/skel/.local/share/applications/chirp.desktop

# Install dmrconfig, LibreOffice
sudo apt update
sudo apt install -y dmrconfig libreoffice

et-mirror.sh https://choisser.com/packet/
et-mirror.sh https://www.cantab.net/users/john.wiseman/Documents/
et-mirror.sh https://soundcardpacket.org/
et-mirror.sh https://tldp.org/HOWTO/AX25-HOWTO/index.html
