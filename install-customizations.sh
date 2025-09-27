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

# Add default WiFi connection (SSID: 321)
nmcli connection add type wifi ifname "*" con-name "$DEFAULT_WIFI_SSID" autoconnect yes ssid "$DEFAULT_WIFI_SSID"
nmcli connection modify "$DEFAULT_WIFI_SSID" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$DEFAULT_WIFI_PASSWORD"

# Add alternate WiFi connections
nmcli connection add type wifi ifname "*" con-name "David's iPhone" autoconnect no ssid "David's iPhone"
nmcli connection modify "David's iPhone" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "25HotSpot"

nmcli connection add type wifi ifname "*" con-name "Vassleheilm" autoconnect no ssid "Vassleheilm"
nmcli connection modify "Vassleheilm" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "LiftLoveRepeat24"

nmcli connection add type wifi ifname "*" con-name "Koz Guest" autoconnect no ssid "Koz Guest"
nmcli connection modify "Koz Guest" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "Kozoncaphill"

nmcli connection add type wifi ifname "*" con-name "Mietzner" autoconnect no ssid "Mietzner"
nmcli connection modify "Mietzner" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "4258360310"

nmcli connection add type wifi ifname "*" con-name "Mr.Blue5" autoconnect no ssid "Mr.Blue5"
nmcli connection modify "Mr.Blue5" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "Securinator2"

nmcli connection add type wifi ifname "*" con-name "FBI AGENT MR.MITTENS" autoconnect no ssid "FBI AGENT MR.MITTENS"
nmcli connection modify "FBI AGENT MR.MITTENS" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "Family4362!"

nmcli connection add type wifi ifname "*" con-name "One Medical Guest" autoconnect no ssid "One Medical Guest"
nmcli connection modify "One Medical Guest" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "FreshStart"

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
