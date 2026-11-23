# shellcheck shell=bash
#
# lib/customize-aprs.sh -- APRS / Dire Wolf configuration
#
# Single source of truth for both the live system and the ISO build.
# Requires lib/common.sh to be sourced first.
#
# Reads (all optional, from secrets.env):
#   CALLSIGN GRID_SQUARE
#   APRS_SSID APRS_PASSCODE APRS_SERVER
#   ENABLE_APRS_IGATE ENABLE_APRS_BEACON APRS_BEACON_MODE
#   APRS_LAT APRS_LON APRS_BEACON_INTERVAL APRS_COMMENT APRS_SYMBOL
#   APRS_BEACON_POWER APRS_BEACON_HEIGHT APRS_BEACON_GAIN APRS_BEACON_VIA

# ---------------------------------------------------------------------------
# IMPORTANT -- two constraints that previous versions of this repo got wrong:
#
# 1. Dire Wolf's config parser is strictly LINE-ORIENTED. It does not support
#    backslash continuations. A PBEACON split across lines produces
#    "No = found in, \" plus one "Unrecognized command" per continuation.
#    Every directive below must stay on exactly one line.
#
# 2. et-direwolf re-substitutes {{ET_CALLSIGN}} and {{ET_AUDIO_DEVICE}} on
#    EVERY launch. Those placeholders must survive into the written template;
#    anything else we add is baked in literally.
# ---------------------------------------------------------------------------

customize_aprs() {
    log "INFO" "Configuring APRS / Dire Wolf..."

    local callsign="${CALLSIGN:-N0CALL}"
    local grid="${GRID_SQUARE:-}"

    if [ "$callsign" = "N0CALL" ]; then
        log "WARN" "CALLSIGN is N0CALL -- skipping APRS configuration"
        return 0
    fi

    local ssid="${APRS_SSID:-10}"
    local server="${APRS_SERVER:-noam.aprs2.net}"
    local enable_igate="${ENABLE_APRS_IGATE:-yes}"
    local enable_beacon="${ENABLE_APRS_BEACON:-yes}"
    local beacon_mode="${APRS_BEACON_MODE:-fixed}"   # fixed | gps
    local interval="${APRS_BEACON_INTERVAL:-30:00}"
    local comment="${APRS_COMMENT:-EmComm iGate}"
    local symbol="${APRS_SYMBOL:-digi}"
    local power="${APRS_BEACON_POWER:-10}"
    local height="${APRS_BEACON_HEIGHT:-20}"
    local gain="${APRS_BEACON_GAIN:-3}"
    local via="${APRS_BEACON_VIA:-WIDE1-1}"

    # Passcode is derivable from the callsign, so compute it unless overridden.
    local passcode="${APRS_PASSCODE:-}"
    if [ -z "$passcode" ]; then
        passcode=$(aprs_passcode "$callsign")
        log "DEBUG" "Computed APRS-IS passcode for ${callsign}"
    fi

    # Position: explicit lat/lon wins, else derive from the grid square.
    local lat="${APRS_LAT:-}" lon="${APRS_LON:-}"
    if [ -z "$lat" ] || [ -z "$lon" ]; then
        if [ -n "$grid" ]; then
            read -r lat lon < <(grid_to_latlon "$grid")
            log "DEBUG" "Derived position from grid ${grid}: ${lat}, ${lon}"
        else
            log "WARN" "No APRS_LAT/APRS_LON and no GRID_SQUARE -- disabling beacon"
            enable_beacon="no"
        fi
    fi

    # GPS beaconing needs a direwolf built with ENABLE_GPSD. Fall back rather
    # than writing a config that dies at startup.
    if [ "$beacon_mode" = "gps" ] && ! direwolf_has_gpsd; then
        log "WARN" "direwolf lacks GPSD support -- falling back to a fixed beacon"
        log "WARN" "Run ./build-direwolf-gpsd.sh to enable GPS tracking"
        beacon_mode="fixed"
    fi

    local template
    template="$(etpath "${ET_PREFIX}/conf/template.d/packet/direwolf.aprs-digipeater.conf")"

    if [ ! -d "$(dirname "$template")" ]; then
        log "WARN" "Dire Wolf template dir not found -- skipping APRS"
        return 0
    fi

    # Build the optional blocks first so the heredoc stays readable.
    local igate_block="# APRS-IS iGate disabled (ENABLE_APRS_IGATE=no)"
    if [ "$enable_igate" = "yes" ]; then
        igate_block="# Receive-only: no IGTXVIA is set, so nothing is gated from the
# internet back onto RF.
IGSERVER ${server}
IGLOGIN {{ET_CALLSIGN}}-${ssid} ${passcode}"
    fi

    local beacon_block
    case "$enable_beacon:$beacon_mode" in
        no:*)
            beacon_block="# Position beaconing disabled (ENABLE_APRS_BEACON=no)." ;;
        yes:gps)
            beacon_block="# GPS-tracked position (direwolf built with ENABLE_GPSD).
GPSD
TBEACON delay=1 every=${interval} overlay=S symbol=\"${symbol}\" power=${power} height=${height} gain=${gain} comment=\"${comment}\" via=${via}" ;;
        *)
            beacon_block="# Fixed position${grid:+ (from grid ${grid})}. Adjust power/height/gain to your station.
PBEACON delay=1 every=${interval} overlay=S symbol=\"${symbol}\" lat=${lat} long=${lon} power=${power} height=${height} gain=${gain} comment=\"${comment}\" via=${via}
#
# To beacon from GPS instead: run ./build-direwolf-gpsd.sh, then replace the
# PBEACON line above with these two lines:
#GPSD
#TBEACON delay=1 every=10:00 overlay=S symbol=\"${symbol}\" power=${power} height=${height} gain=${gain} comment=\"${comment}\" via=${via}" ;;
    esac

    local title="RF APRS digipeater"
    [ "$enable_igate" = "yes" ] && title="${title} + APRS-IS iGate"

    write_file "$template" 644 <<EOF
# Dire Wolf template -- ${title}
#
# Original author : Gaston Gonzalez (EmComm Tools)
# Generated by    : emcomm-tools-customizer lib/customize-aprs.sh
#
# WARNING: et-direwolf substitutes {{ET_CALLSIGN}} and {{ET_AUDIO_DEVICE}} on
# every launch. Do not replace those placeholders with literal values.
#
# WARNING: Dire Wolf's config parser is line-oriented and does NOT support
# backslash continuations. Keep every directive on one line.

# Audio settings
ADEVICE {{ET_AUDIO_DEVICE}}
CHANNEL 0

# User settings
MYCALL {{ET_CALLSIGN}}-4

# Modem settings
MODEM 1200

# Rig control settings. Do not change this.
# EmComm Tools uses Hamlib's rig control daemon for all radio interfaces.
PTT RIG 2 localhost:4532

# --- APRS-IS iGate ---------------------------------------------------------
${igate_block}

# Enable ports to allow other applications use Dire Wolf as the packet engine
AGWPORT 8000
KISSPORT 8001

# --- Position beacon -------------------------------------------------------
${beacon_block}

DIGIPEAT 0 0 ^WIDE[3-7]-[1-7]\$|^TEST\$ ^WIDE[12]-[12]\$ TRACE
IGTXLIMIT 6 10
EOF

    log "SUCCESS" "Wrote $template"
    [ "$enable_igate" = "yes" ] && \
        log "INFO" "  iGate:  ${callsign}-${ssid} @ ${server} (receive-only)"
    if [ "$enable_beacon" = "yes" ]; then
        if [ "$beacon_mode" = "gps" ]; then
            log "INFO" "  Beacon: GPS-tracked, every ${interval}"
        else
            log "INFO" "  Beacon: ${lat},${lon} every ${interval}"
        fi
    else
        log "INFO" "  Beacon: disabled"
    fi
    return 0
}
