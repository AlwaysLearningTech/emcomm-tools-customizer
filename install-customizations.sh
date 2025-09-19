#!/bin/bash

# Turn off on-screen keyboard
gsettings set org.gnome.desktop.a11y.applications screen-keyboard-enabled false

# Turn off large text
gsettings set org.gnome.desktop.a11y.interface large-text false

# Turn on dark mode system-wide
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
gsettings set org.gnome.desktop.interface gtk-theme 'Yaru-dark'

# Set display scaling to 100%
gsettings set org.gnome.desktop.interface text-scaling-factor 1.0
gsettings set org.gnome.desktop.interface scaling-factor 1

# Connect to WiFi SSID 'David's iPhone'
nmcli dev wifi connect "David's iPhone" password "25HotSpot"

# Install Chirp
wget https://archive.chirpmyradio.com/chirp_next/next-20250822/chirp-20250822-py3-none-any.whl
pipx install --system-site-packages ./chirp-20250822-py3-none-any.whl
pipx ensurepath
cp chirp.desktop /etc/skel/.local/share/applications/chirp.desktop


apt install libreoffice

et-mirror https://choisser.com/packet/
et-mirror https://www.cantab.net/users/john.wiseman/Documents/
et-mirror https://soundcardpacket.org/
et-mirror https://tldp.org/HOWTO/AX25-HOWTO/index.html

