# shellcheck shell=bash
#
# lib/customize-radio.sh -- Anytone AT-D578UVIII radio profiles
#
# Single source of truth for both the live system and the ISO build.
# Requires lib/common.sh to be sourced first.
#
# Reads (optional, from secrets.env):
#   ENABLE_ANYTONE_D578    yes|no  (default yes)

# ---------------------------------------------------------------------------
# Hamlib model number: 37001 = RIG_MODEL_ATD578UVIII
#   RIG_MAKE_MODEL(family, n) == family*1000 + n, with RIG_ANYTONE == 37.
#   The same scheme gives ETC's IC-705 profile its id of 3085 (RIG_ICOM=3, 85).
#
# This backend is NOT in stock Hamlib 4.5 as shipped with ETC v6. It comes from
# CowboyPilot/Hamlib -- run ./build-hamlib-anytone.sh first, or rigctld will
# reject model 37001 outright.
#
# ONE profile, commode=1 (full rig control). ETC's wrapper-rigctld.sh already
# reads .rigctrl.conf and passes it through as --set-conf=<value>, so this
# needs no wrapper changes whatsoever.
#
# A second commode=0 "PTT only" profile used to be written here as the default.
# It was removed: it duplicated stock ETC's digirig-mobile-no-cat profile, which
# keys the radio via the DigiRig's serial RTS line using Hamlib model 6
# (RIG_MODEL_DUMMY_NOVFO) and never talks to the radio at all. Both gave you
# nothing but PTT -- except the commode=0 version also required this custom
# Hamlib build to do it. If you want PTT-only operation, select
# "DigiRig Mobile (No CAT)" with et-radio; it needs no custom Hamlib.
#
# Wiring assumed: the AT-D578 DigiRig cable (CAT-control variant), which carries
# the DigiRig Mobile's CP2102 serial and audio to the radio's RJ-45 mic jack.
# Stock udev rule 90-et-digirig-mobile.rules already maps 10c4:ea60 to
# /dev/et-cat and 0d8c:013c to /dev/et-audio -- no new rule is needed.
# ---------------------------------------------------------------------------

ANYTONE_MODEL_ID="37001"
ANYTONE_BAUD="115200"

customize_radio_configs() {
    if [ "${ENABLE_ANYTONE_D578:-yes}" != "yes" ]; then
        log "DEBUG" "ENABLE_ANYTONE_D578=no -- skipping radio profiles"
        return 0
    fi

    log "INFO" "Configuring Anytone AT-D578UVIII radio profiles..."

    local radios_dir
    radios_dir="$(etpath "${ET_PREFIX}/conf/radios.d")"
    local profile="${radios_dir}/anytone-d578uv.json"

    # Warn early on the live path; an ISO build can't exec the target's rigctl.
    if [ "$ET_ROOT" = "/" ]; then
        if hamlib_has_anytone; then
            log "SUCCESS" "AnyTone backend present: $(rigctl -l | grep -i anytone | head -1 | tr -s ' ')"
        else
            log "WARN" "No AnyTone backend in this Hamlib -- rigctld will REJECT model ${ANYTONE_MODEL_ID}."
            log "WARN" "Run ./build-hamlib-anytone.sh, then re-run this script."
        fi
    fi

    # --- commode=1: full rig control. The radio front panel locks out. ------
    # et-radio resolves a selection by .id, which must match the filename stem.
    write_file "$profile" 644 <<EOF
{
  "id": "anytone-d578uv",
  "vendor": "Anytone",
  "model": "D578UVIII (COM mode)",
  "rigctrl": {
    "id": "${ANYTONE_MODEL_ID}",
    "baud": "${ANYTONE_BAUD}",
    "ptt": "RIG",
    "conf": "commode=1"
  },
  "notes": [
    "COM mode (commode=1) - get/set frequency, VFO A/B, clock, and PTT",
    "The radio displays EXTERNAL CABLE MODE and its front panel locks out",
    "set_freq only works with Channel A selected AND VFO A in VFO mode",
    "If VFO A is in MR (memory) mode the radio will refuse frequency changes",
    "If VFO B is selected, get_freq returns VFO A and set_freq is refused",
    "PTT works regardless of the above, on whichever VFO is selected",
    "For PTT without the front panel locking, select 'DigiRig Mobile (No CAT)'"
  ],
  "fieldNotes": [
    "Requires the AnyTone Hamlib backend - see build-hamlib-anytone.sh",
    "Uses the AT-D578 DigiRig cable (CAT variant) into the radio RJ-45 mic jack",
    "DigiRig serial is auto-mapped to /dev/et-cat by 90-et-digirig-mobile.rules",
    "DigiRig audio is auto-mapped to /dev/et-audio",
    "Run 'et-mode' to select the desired mode of operation",
    "Set radio MIC gain and volume for the DigiRig - see DigiRig level setup"
  ]
}
EOF
    log "SUCCESS" "Wrote $(basename "$profile")  (model ${ANYTONE_MODEL_ID}, commode=1, ptt=RIG)"

    backup "${radios_dir}/active-radio.json"
    if [ "$ET_DRY_RUN" -eq 0 ]; then
        # RELATIVE symlink, deliberately. An absolute one would embed the build
        # machine's squashfs path and dangle on the installed system. The
        # profile lives in this directory, so the basename always resolves.
        ln -sfn "$(basename "$profile")" "${radios_dir}/active-radio.json"
        log "SUCCESS" "Active radio -> $(basename "$profile" .json). Switch with 'et-radio'."
    fi

    # -----------------------------------------------------------------------
    # Deliberately NOT done, and why. All three were in v1 and all three were
    # wrong; re-adding any of them will break things:
    #
    #  - No udev rule. Stock 90-et-digirig-mobile.rules already maps the
    #    DigiRig to /dev/et-cat and /dev/et-audio. v1 added a 99- rule with an
    #    unguarded SYMLINK+="et-cat" for generic FTDI/PL2303/CH340, which lets
    #    an unrelated USB serial device (a GPS, say) steal /dev/et-cat.
    #
    #  - No /etc/systemd/system/rigctld.service override. Stock ETC ships
    #    /lib/systemd/system/rigctld.service and starts it from udev when the
    #    radio appears. v1's override added Restart=on-failure AND enabled it at
    #    boot; rigctld exits 1 when no CAT device is present, so that
    #    restart-loops forever on any boot without the radio plugged in.
    #
    #  - No wrapper-rigctld.sh patch. v1 patched do_full_auto() to "protect"
    #    the active radio. do_full_auto() is defined but never called anywhere
    #    in that script -- the patch guarded nothing and only risked corrupting
    #    a working wrapper.
    # -----------------------------------------------------------------------
    return 0
}
