# shellcheck shell=bash
#
# lib/customize-anytone-dmr.sh -- AnyTone DMR support: AT-D890UV Bluetooth KISS
# TNC, and the anytone-cps programming application.
#
# Single source of truth for both the live system and the ISO build.
# Requires lib/common.sh to be sourced first.
#
# Reads (optional, from secrets.env):
#   ENABLE_ANYTONE_D890_TNC   yes|no  (default yes)
#   ANYTONE_D890_MAC          pre-seed the BT MAC instead of pairing
#   ENABLE_ANYTONE_CPS        yes|no  (default yes)  -- launcher only; the
#                                     compile itself lives in build-etc-iso.sh
#
# ---------------------------------------------------------------------------
# Why a Bluetooth TNC and not CAT, for this radio
#
# The AT-D890UV is a DMR handheld. Its packet path to a computer is the
# built-in Bluetooth KISS TNC, not a serial CAT port -- so it slots into ETC's
# *.bt.json + et-<model> pattern (et-uv-pro, et-vr-n76, et-th-d74), NOT into
# radios.d CAT profiles like the D578UVIII. Firmware 1.05 (May 2026)
# specifically improved Bluetooth KISS TNC behaviour; older firmware sends
# malformed APRS beacons, so check the radio's firmware before debugging.
#
# This is deliberately modelled on ETC's own et-uv-pro rather than invented:
# et-kill-bt, the rfcomm0 device, the axports rewrite via `ed`, and the
# application menu all behave the same way, so et-mode and et-kill-all keep
# working and there is one mental model for every Bluetooth radio.
# ---------------------------------------------------------------------------

ANYTONE_D890_ID="anytone-d890"
# Bluetooth advertised-name fragment used to find the radio during pairing.
# Matched case-insensitively as a substring, because AnyTone has shipped
# several advertised names across firmware revisions ("D890UV", "AT-D890UV").
ANYTONE_D890_BT_NAME="D890"

customize_anytone_d890_tnc() {
    if [ "${ENABLE_ANYTONE_D890_TNC:-yes}" != "yes" ]; then
        log "DEBUG" "ENABLE_ANYTONE_D890_TNC=no -- skipping D890 TNC"
        return 0
    fi

    log "INFO" "Configuring AnyTone AT-D890UV Bluetooth KISS TNC..."

    local radios_dir bin_dir profile script
    radios_dir="$(etpath "${ET_PREFIX}/conf/radios.d")"
    bin_dir="$(etpath "${ET_PREFIX}/bin")"
    profile="${radios_dir}/${ANYTONE_D890_ID}.bt.json"
    script="${bin_dir}/et-anytone-d890"

    # ETC's own Bluetooth scripts hard-code their profile path and read
    # .bluetooth.mac from it, so the profile must exist before the script runs.
    write_file "$profile" 644 <<EOF
{
  "id": "${ANYTONE_D890_ID}",
  "vendor": "AnyTone",
  "model": "AT-D890UV (BT)",
  "bluetooth": {
    "deviceName": "${ANYTONE_D890_BT_NAME}",
    "mac": "${ANYTONE_D890_MAC:-}"
  },
  "notes": [
    "Enable Bluetooth on the radio, then enable its Bluetooth KISS TNC",
    "Run 'et-anytone-d890 pair' once, then 'et-anytone-d890 connect'",
    "Firmware 1.05 or newer is strongly recommended for the KISS TNC"
  ],
  "fieldNotes": [
    "DMR handheld: packet goes over Bluetooth KISS, there is no serial CAT",
    "Analog APRS and DMR APRS are both supported by the radio itself",
    "Power cycle the radio between Bluetooth mode changes if it stops responding",
    "Pairing writes the discovered MAC back into this file"
  ]
}
EOF
    log "SUCCESS" "Wrote $(basename "$profile")"

    # -----------------------------------------------------------------------
    # et-anytone-d890 -- adapted from ETC's et-uv-pro.
    #
    # Two deviations from the R6 original, both deliberate:
    #
    #  - get_mac_or_exit() rejects an EMPTY mac, not just a missing key. R6's
    #    version used `jq -e -r .bluetooth.mac`, which succeeds on "" and then
    #    hands an empty MAC to rfcomm. R7 fixed this upstream; this script
    #    carries the fix so it behaves the same on an R6 host.
    #
    #  - Pairing rewrites the mac with jq rather than
    #    `sed -i 's|.*mac.*|...|g'`. The sed form matches EVERY line containing
    #    "mac" -- including "deviceName" lines on radios that have one, and any
    #    note mentioning a MAC -- and silently corrupts the JSON.
    # -----------------------------------------------------------------------
    write_file "$script" 755 <<'D890SCRIPT'
#!/bin/bash
#
# Utility for accessing the Bluetooth KISS TNC on the AnyTone AT-D890UV.
# Installed by emcomm-tools-customizer; modelled on ETC's et-uv-pro.
source /opt/emcomm-tools/bin/et-common

CLEAN_UP=1

cleanup() {
  # Every mode change needs a fresh Bluetooth connection, so rfcomm and the
  # kiss processes must not survive this script.
  if [[ ${CLEAN_UP} -eq 1 ]]; then
    sudo /opt/emcomm-tools/bin/et-kill-bt
  fi
}

trap cleanup EXIT

ACTIVE_RADIO="${ET_HOME}/conf/radios.d/anytone-d890.bt.json"
DEVICE_NAME="AT-D890UV"
BT_NAME_MATCH="D890"
BT_DEVICE="/dev/rfcomm0"
AX25_PORT="wl2k"
AX25_CONF_FILE="/etc/ax25/axports"

function usage() {
  echo "Usage: $(basename $0) <command>"
  echo "  c, connect - Connect to radio via Bluetooth"
  echo "  p, pair    - Pair radio (one-time operation)"
  echo "  u, unpair  - Unpair radio"

  CLEAN_UP=0
}

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

if [[ -e ${BT_DEVICE} ]]; then
  echo -e "${YELLOW}Your ${BLUE}${DEVICE_NAME}${YELLOW} may have a connection that needs to be cleaned up."
  echo -e "Press ${WHITE}[ENTER]${YELLOW} to clean-up.${NC}"
  read -p ""

  cleanup
fi

stop_all_services() {
  et-kill-all
}

exit_if_no_active_radio() {
  if [ ! -e ${ACTIVE_RADIO} ]; then
    echo "${ACTIVE_RADIO} file not found"
    exit 1
  fi
}

# Treat an empty MAC as missing. `jq -e` alone returns success for "".
get_mac_or_exit() {
  MAC=$(jq -e -r '.bluetooth.mac // empty' ${ACTIVE_RADIO} 2>/dev/null)
  if [ -z "${MAC}" ]; then
    echo "No MAC address found in ${ACTIVE_RADIO}."
    echo "Run '$(basename $0) pair' first."
    exit 1
  fi
}

update_ax25_conf() {

  [ -z "$ET_USER_CONFIG" ] && ET_USER_CONFIG="${HOME}/.config/emcomm-tools/user.json"

  CALLSIGN=$(cat ${ET_USER_CONFIG} | jq -r .callsign)

  if [ "${CALLSIGN}" = "N0CALL" ]; then
    et-log "No callsign set. Run et-user first."
    exit 1
  fi

  GREP_OUT=$(grep ${AX25_PORT} ${AX25_CONF_FILE})
  if [ $? -eq 0 ]; then
    # Delete existing AX.25 port entries. sed -i can't be used here: we lack
    # permission to create the temporary file it needs. ed edits in place.
    printf "g/^${AX25_PORT}/d\nw\nq\n" | ed ${AX25_CONF_FILE} > /dev/null 2>&1
  fi

  echo "${AX25_PORT} ${CALLSIGN} 1200 255	2 1200 Packet" >> ${AX25_CONF_FILE}
}

do_kiss_attach() {
  echo -e "${BLUE}Connecting KISS interface using ${BT_DEVICE} and AX.25 port: ${AX25_PORT}${NC}"
  KISS_OUT=$(sudo kissattach ${BT_DEVICE} ${AX25_PORT})

  if [[ $? -ne 0 ]]; then
    echo -e "${RED}Failed to attach KISS port.${NC}"
    exit 1
  fi

  KISS_OUT=$(sudo kissparms -c 1 -p ${AX25_PORT})
}

exit_on_service_failure() {
  local systemd_unit_name="$1"
  systemctl is-active --user --quiet "${systemd_unit_name}"
  if [ $? -ne 0 ]; then
    et-log "Can't start mode. ${systemd_unit_name} failed to start."
    exit 1
  fi
}

TIMEOUT=15
INTERVAL=2

start_and_wait_for_service() {
  local systemd_unit_name="$1"
  local elapsed=0

  et-log "Starting ${systemd_unit_name}..."
  systemctl --user start ${systemd_unit_name}

  et-log "Waiting for ${systemd_unit_name} to become active..."

  while ! systemctl is-active --user --quiet "${systemd_unit_name}"; do
      sleep "$INTERVAL"
      elapsed=$((elapsed + INTERVAL))
      if [ "$elapsed" -ge "$TIMEOUT" ]; then
          et-log "Timeout reached. ${systemd_unit_name} failed to start."
          exit 1
      fi
      et-log "Waiting for ${systemd_unit_name} to become active..."
  done

  sleep 2
  exit_on_service_failure ${systemd_unit_name}
}

exit_if_no_active_radio

case $1 in
  p|pair)

    MAC=$(jq -r '.bluetooth.mac // empty' ${ACTIVE_RADIO} 2>/dev/null)
    if [ -n "${MAC}" ]; then
      PAIR_STATUS=$(bluetoothctl info "${MAC}" | grep "Paired:" | awk '{print $2}')
      if [ "${PAIR_STATUS}" == "yes" ]; then
         echo "Device with MAC ${MAC} is already paired."
         exit 1
      fi
    fi

    echo -e "${YELLOW}"
    echo -e "1. Turn on your ${DEVICE_NAME}"
    echo -e "2. Enable Bluetooth on the radio and put it in pairing mode"
    echo -e "3. Enable the radio's Bluetooth KISS TNC"
    echo -e "   (firmware 1.05 or newer is strongly recommended)"
    echo -e "4. Press ${WHITE}[ENTER]${YELLOW} when done.${NC}"
    read -p ""

    echo "Searching for ${DEVICE_NAME}..."

    # Match a NAME FRAGMENT, case-insensitively: AnyTone has advertised this
    # radio under more than one name across firmware revisions.
    HCI_OUT=$(hcitool scan | grep -i "${BT_NAME_MATCH}")
    if [ $? -ne 0 ]; then
      echo "Can't find ${DEVICE_NAME}. Make sure the radio is on and in pairing mode."
      echo "Tip: 'hcitool scan' alone will show every device it can see."
      exit 1
    fi

    MAC=$(echo ${HCI_OUT} | awk '{print $1}')

    # Rewrite the mac with jq, not sed. A 's|.*mac.*|...|' substitution also
    # matches the deviceName line and any note mentioning a MAC, which
    # corrupts the JSON.
    TMP_JSON=$(mktemp)
    if jq --arg mac "${MAC}" '.bluetooth.mac = $mac' ${ACTIVE_RADIO} > "${TMP_JSON}"; then
      cat "${TMP_JSON}" > ${ACTIVE_RADIO}
      rm -f "${TMP_JSON}"
      echo "Recorded MAC ${MAC} in ${ACTIVE_RADIO}"
    else
      rm -f "${TMP_JSON}"
      echo -e "${RED}Failed to record MAC in ${ACTIVE_RADIO}${NC}"
      exit 1
    fi

    PAIR_SCRIPT="${HOME}/pair-d890"

cat <<EOF > ${PAIR_SCRIPT}
#!/usr/bin/expect -f

set device "${MAC}"
set timeout 60

spawn bluetoothctl
expect "Agent registered"
send "power on\r"
expect "Changing power on succeeded"
send "scan on\r"
expect "${MAC}"
send "pair ${MAC}\r"
expect "Pairing successful"
send "trust ${MAC}\r"
expect "trust succeeded"
send "exit\r"
expect eof
EOF

    sleep 1 && chmod 755 ${PAIR_SCRIPT} && expect ${PAIR_SCRIPT}

    ;;
  u|unpair)
    get_mac_or_exit

    PAIR_STATUS=$(bluetoothctl info "${MAC}")
    if [ $? -ne 0 ]; then
       echo "No device with ${MAC} found. Can't unpair."
       exit 1
    fi

    echo "Unpairing ${DEVICE_NAME}..."
    bluetoothctl untrust ${MAC}
    bluetoothctl remove ${MAC}

    echo -e "${YELLOW}"
    echo -e "You may also want to remove this laptop from the paired-device"
    echo -e "list on your ${DEVICE_NAME}."
    echo -e "${NC}"

    ;;
  c|connect)
    get_mac_or_exit

    echo -e "${YELLOW}"
    echo -e "1. Turn on your ${DEVICE_NAME}"
    echo -e "2. Enable Bluetooth on the radio"
    echo -e "3. Enable the radio's Bluetooth KISS TNC"
    echo -e "4. Press ${WHITE}[ENTER]${YELLOW} when done.${NC}"
    read -p ""

    is_paired=$(bluetoothctl info ${MAC} | grep "Paired" | awk '{print $2}')
    if [ "${is_paired}" != "yes" ]; then
      echo -e "${RED}${DEVICE_NAME} is not paired. Run: '${WHITE}$(basename $0) pair${RED}'"
      echo -e "${NC}"
      exit 1
    fi

    echo -e "Found ${DEVICE_NAME} with MAC address: ${MAC}"

    update_ax25_conf

    sudo rfcomm connect /dev/rfcomm0 ${MAC} 1>/dev/null 2>&1 &

    sleep 10 && reset

    if [[ ! -e "${BT_DEVICE}" ]]; then
      echo -e "${RED}Failed to connect via Bluetooth${NC}"
      echo -e "${YELLOW}"
      echo -e "1. Try turning the radio off and back on."
      echo -e "2. Check that the Bluetooth KISS TNC is enabled on the radio."
      echo -e "3. Check that ${BLUE}$(hostname)${YELLOW} is still in the radio's"
      echo -e "   paired-device list. If not, re-run: ${WHITE}$(basename $0) pair${NC}\n"
      exit 1
    fi

    stop_all_services

    echo -e "\nSelect a packet application to start:"
    options=("axcall" "QtTermTCP" "Winlink" "YAAC" "Exit")

    select opt in "${options[@]}"
    do
      case $opt in
        "axcall")
          do_kiss_attach
          echo -e "${YELLOW}"
          echo -e "SAMPLE COMMANDS               DESCRIPTION                     "
          echo -e "----------------------------- --------------------------------"
          echo -e "axcall wl2k <STATION>         Connect directly to a node      "
          echo -e "axcall wl2k <STATION> <DIGI>  Connect to node via a digipeater"
          echo -e "sudo axlisten -a -tttt -c     Monitor inbound and outbound traffic"
          echo -e "${NC}"

          # rfcomm and the kiss processes must survive for axcall to work.
          CLEAN_UP=0
          break
          ;;
        "QtTermTCP")
          et-qttermtcp start 1>/dev/null 2>&1
          break
          ;;
        "Winlink")
          do_kiss_attach
          start_and_wait_for_service et-service-winlink-native-packet
          min http://localhost:8080 1>/dev/null 2>&1
          break
          ;;
        "YAAC")
          et-yaac start
          break
          ;;
        "Exit")
          break
          ;;
        *)
          echo "Invalid option, please select a number from the list."
          ;;
       esac
    done

    ;;
  *)
    et-log "Invalid command."
    usage
    exit 1
  ;;
esac
D890SCRIPT
    log "SUCCESS" "Wrote $(basename "$script")  (pair / connect / unpair)"

    return 0
}

# ---------------------------------------------------------------------------
# anytone-cps desktop launcher.
#
# The binary is compiled into the ISO by build-etc-iso.sh. This only writes the
# .desktop entry, so the live path and the ISO path agree on where it lives and
# what it is called.
# ---------------------------------------------------------------------------
customize_anytone_cps_launcher() {
    if [ "${ENABLE_ANYTONE_CPS:-yes}" != "yes" ]; then
        log "DEBUG" "ENABLE_ANYTONE_CPS=no -- skipping anytone-cps launcher"
        return 0
    fi

    local desktop
    desktop="$(etpath /usr/share/applications/anytone-cps.desktop)"

    write_file "$desktop" 644 <<'EOF'
[Desktop Entry]
Type=Application
Name=AnyTone CPS
GenericName=AnyTone radio programming
Comment=Open-source programming software for AnyTone DMR radios
Exec=/usr/local/bin/anytone-cps
Icon=utilities-terminal
Terminal=false
Categories=HamRadio;Utility;
Keywords=anytone;dmr;cps;radio;d878;d890;
EOF
    log "SUCCESS" "Wrote anytone-cps.desktop"

    return 0
}
