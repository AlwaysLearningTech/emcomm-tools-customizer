# shellcheck shell=bash
#
# lib/customize-radio.sh -- Anytone AT-D578UVIII radio profiles
#
# Single source of truth for both the live system and the ISO build.
# Requires lib/common.sh to be sourced first.
#
# Reads (optional, from secrets.env):
#   ENABLE_ANYTONE_D578    yes|no  (default yes)
#   ANYTONE_DEFAULT_MODE   ptt|com (default ptt)

# ---------------------------------------------------------------------------
# Hamlib model number: 37001 = RIG_MODEL_ATD578UVIII
#   RIG_MAKE_MODEL(family, n) == family*1000 + n, with RIG_ANYTONE == 37.
#   The same scheme gives ETC's IC-705 profile its id of 3085 (RIG_ICOM=3, 85).
#
# This backend is NOT in stock Hamlib 4.5 as shipped with ETC v6. It comes from
# CowboyPilot/Hamlib -- run ./build-hamlib-anytone.sh first, or rigctld will
# reject model 37001 outright.
#
# Two operating modes, selected via the backend's commode setting. ETC's
# wrapper-rigctld.sh already reads .rigctrl.conf and passes it through as
# --set-conf=<value>, so commode=1 needs no wrapper changes whatsoever.
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
    local profile_com="${radios_dir}/anytone-d578uv-com.json"

    # Warn early on the live path; an ISO build can't exec the target's rigctl.
    if [ "$ET_ROOT" = "/" ]; then
        if hamlib_has_anytone; then
            log "SUCCESS" "AnyTone backend present: $(rigctl -l | grep -i anytone | head -1 | tr -s ' ')"
        else
            log "WARN" "No AnyTone backend in this Hamlib -- rigctld will REJECT model ${ANYTONE_MODEL_ID}."
            log "WARN" "Run ./build-hamlib-anytone.sh, then re-run this script."
        fi
    fi

    # --- commode=0: PTT only, radio display stays usable (default) ---------
    write_file "$profile" 644 <<EOF
{
  "id": "anytone-d578uv",
  "vendor": "Anytone",
  "model": "D578UVIII (DigiRig, PTT only)",
  "rigctrl": {
    "id": "${ANYTONE_MODEL_ID}",
    "baud": "${ANYTONE_BAUD}",
    "ptt": "RIG"
  },
  "notes": [
    "PTT-only mode (commode=0) - the radio display stays usable",
    "Set your VFO, power level and squelch manually on the radio",
    "PTT keys whichever VFO is selected, exactly like the physical mic PTT",
    "For frequency/VFO control instead, select 'D578UVIII (COM mode)'"
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
    log "SUCCESS" "Wrote $(basename "$profile")  (model ${ANYTONE_MODEL_ID}, commode=0, ptt=RIG)"

    # --- commode=1: full rig control, radio front panel locks out ----------
    write_file "$profile_com" 644 <<EOF
{
  "id": "anytone-d578uv-com",
  "vendor": "Anytone",
  "model": "D578UVIII (COM mode)",
  "rigctrl": {
    "id": "${ANYTONE_MODEL_ID}",
    "baud": "${ANYTONE_BAUD}",
    "ptt": "RIG",
    "conf": "commode=1"
  },
  "notes": [
    "COM mode (commode=1) - adds get/set frequency, VFO A/B and clock",
    "The radio displays EXTERNAL CABLE MODE and its front panel locks out",
    "set_freq only works with Channel A selected AND VFO A in VFO mode",
    "If VFO A is in MR (memory) mode the radio will refuse frequency changes",
    "If VFO B is selected, get_freq returns VFO A and set_freq is refused",
    "PTT works regardless of the above, on whichever VFO is selected"
  ],
  "fieldNotes": [
    "Requires the AnyTone Hamlib backend - see build-hamlib-anytone.sh",
    "Uses the AT-D578 DigiRig cable (CAT variant) into the radio RJ-45 mic jack",
    "Prefer the PTT-only profile unless you specifically need rig control",
    "Run 'et-mode' to select the desired mode of operation"
  ]
}
EOF
    log "SUCCESS" "Wrote $(basename "$profile_com")  (model ${ANYTONE_MODEL_ID}, commode=1, ptt=RIG)"

    # Default active radio. et-radio resolves the selection by .id, which must
    # match the filename stem -- both profiles satisfy that.
    local default_target="$profile"
    [ "${ANYTONE_DEFAULT_MODE:-ptt}" = "com" ] && default_target="$profile_com"

    backup "${radios_dir}/active-radio.json"
    if [ "$ET_DRY_RUN" -eq 0 ]; then
        # RELATIVE symlink, deliberately. An absolute one would embed the build
        # machine's squashfs path and dangle on the installed system. Both
        # profiles live in this directory, so the basename always resolves.
        ln -sfn "$(basename "$default_target")" "${radios_dir}/active-radio.json"
        log "SUCCESS" "Active radio -> $(basename "$default_target" .json). Switch with 'et-radio'."
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
