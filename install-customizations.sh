#!/bin/bash

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

# Add default WiFi connection (auto-connect enabled)
nmcli connection add type wifi ifname "*" con-name "$DEFAULT_WIFI_SSID" autoconnect yes ssid "$DEFAULT_WIFI_SSID"
nmcli connection modify "$DEFAULT_WIFI_SSID" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$DEFAULT_WIFI_PASSWORD"

# Add alternate WiFi connections (auto-connect disabled)
nmcli connection add type wifi ifname "*" con-name "$IPHONE_WIFI_SSID" autoconnect no ssid "$IPHONE_WIFI_SSID"
nmcli connection modify "$IPHONE_WIFI_SSID" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$IPHONE_WIFI_PASSWORD"

nmcli connection add type wifi ifname "*" con-name "$VASSLEHEILM_WIFI_SSID" autoconnect no ssid "$VASSLEHEILM_WIFI_SSID"
nmcli connection modify "$VASSLEHEILM_WIFI_SSID" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$VASSLEHEILM_WIFI_PASSWORD"

nmcli connection add type wifi ifname "*" con-name "$KOZ_GUEST_WIFI_SSID" autoconnect no ssid "$KOZ_GUEST_WIFI_SSID"
nmcli connection modify "$KOZ_GUEST_WIFI_SSID" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$KOZ_GUEST_WIFI_PASSWORD"

nmcli connection add type wifi ifname "*" con-name "$MIETZNER_WIFI_SSID" autoconnect no ssid "$MIETZNER_WIFI_SSID"
nmcli connection modify "$MIETZNER_WIFI_SSID" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$MIETZNER_WIFI_PASSWORD"

nmcli connection add type wifi ifname "*" con-name "$MRBLUE5_WIFI_SSID" autoconnect no ssid "$MRBLUE5_WIFI_SSID"
nmcli connection modify "$MRBLUE5_WIFI_SSID" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$MRBLUE5_WIFI_PASSWORD"

nmcli connection add type wifi ifname "*" con-name "$FBI_AGENT_WIFI_SSID" autoconnect no ssid "$FBI_AGENT_WIFI_SSID"
nmcli connection modify "$FBI_AGENT_WIFI_SSID" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$FBI_AGENT_WIFI_PASSWORD"

nmcli connection add type wifi ifname "*" con-name "$ONE_MEDICAL_WIFI_SSID" autoconnect no ssid "$ONE_MEDICAL_WIFI_SSID"
nmcli connection modify "$ONE_MEDICAL_WIFI_SSID" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$ONE_MEDICAL_WIFI_PASSWORD"

# Install Chirp
wget https://archive.chirpmyradio.com/chirp_next/next-20250822/chirp-20250822-py3-none-any.whl
pipx install --system-site-packages ./chirp-20250822-py3-none-any.whl
pipx ensurepath
cp chirp.desktop /etc/skel/.local/share/applications/chirp.desktop

# Install dmrconfig, LibreOffice
sudo apt update
sudo apt install -y dmrconfig, libreoffice

et-mirror.sh https://choisser.com/packet/
et-mirror.sh https://www.cantab.net/users/john.wiseman/Documents/
et-mirror.sh https://soundcardpacket.org/
et-mirror.sh https://tldp.org/HOWTO/AX25-HOWTO/index.html

et-users
