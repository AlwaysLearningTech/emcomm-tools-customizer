#!/bin/bash

# Turn off on-screen keyboard
gsettings set org.gnome.desktop.a11y.applications screen-keyboard-enabled false

# Disable large text accessibility setting and display scaling to 100%
gsettings set org.gnome.desktop.interface text-scaling-factor 1.0
gsettings set org.gnome.desktop.interface scaling-factor 1

# Turn on dark mode system-wide
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
gsettings set org.gnome.desktop.interface gtk-theme 'Yaru-dark'

# Store WiFi credentials
DEFAULT_WIFI_SSID="321"
DEFAULT_WIFI_PASSWORD="BlueLaptop3!"
ALT_WIFI_SSID="David's iPhone"
ALT_WIFI_PASSWORD="25HotSpot"

# Add default WiFi connection (SSID: 321)
nmcli connection add type wifi ifname "*" con-name "$DEFAULT_WIFI_SSID" autoconnect yes ssid "$DEFAULT_WIFI_SSID"
nmcli connection modify "$DEFAULT_WIFI_SSID" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$DEFAULT_WIFI_PASSWORD"

# Add alternate WiFi connection (SSID: David's iPhone)
nmcli connection add type wifi ifname "*" con-name "$ALT_WIFI_SSID" autoconnect no ssid "$ALT_WIFI_SSID"
nmcli connection modify "$ALT_WIFI_SSID" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$ALT_WIFI_PASSWORD"

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

