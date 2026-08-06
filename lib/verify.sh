# shellcheck shell=bash
#
# lib/verify.sh -- shared system verification
#
# Used by post-install.sh (as your user) and apply-to-live-system.sh --verify
# (as root). Degrades gracefully when a check needs privileges it does not have,
# rather than reporting a false failure.
#
# Requires lib/common.sh to be sourced first.

VERIFY_PASSED=0
VERIFY_FAILED=0
VERIFY_WARNED=0

_v_pass() { echo -e "  \033[0;32m✓\033[0m $1"; VERIFY_PASSED=$((VERIFY_PASSED+1)); }
_v_fail() { echo -e "  \033[0;31m✗\033[0m $1"; VERIFY_FAILED=$((VERIFY_FAILED+1)); }
_v_warn() { echo -e "  \033[1;33m⚠\033[0m $1"; VERIFY_WARNED=$((VERIFY_WARNED+1)); }
_v_info() { echo -e "  \033[0;34mi\033[0m $1"; }
_v_head() { echo; echo -e "\033[0;34m$1\033[0m"; }

# Dire Wolf's version banner. NOTE: `direwolf -v` is NOT a valid flag -- it
# prints "invalid option -- 'v'". Run it bare and read the banner, capturing
# output first so pipefail does not trip on its non-zero exit.
_v_direwolf_banner() {
    local out
    out=$(direwolf 2>&1 </dev/null || true)
    printf '%s' "$out" | grep -m1 -i 'Dire Wolf version'
}

verify_system() {
    VERIFY_PASSED=0; VERIFY_FAILED=0; VERIFY_WARNED=0
    local APRS_TPL="${ET_PREFIX}/conf/template.d/packet/direwolf.aprs-digipeater.conf"
    local RADIOS="${ET_PREFIX}/conf/radios.d"

    # ---------------------------------------------------------------- system
    _v_head "1. Base system"
    [ -d "$ET_PREFIX" ] && _v_pass "EmComm Tools at $ET_PREFIX" \
                        || _v_fail "EmComm Tools NOT found at $ET_PREFIX"

    local hn; hn=$(cat /etc/hostname 2>/dev/null)
    case "$hn" in
        ETC-*) _v_pass "Hostname customized: $hn" ;;
        *)     _v_warn "Hostname not customized: ${hn:-<unset>}" ;;
    esac

    if command -v direwolf >/dev/null 2>&1; then
        _v_pass "Dire Wolf: $(_v_direwolf_banner)"
    else
        _v_fail "Dire Wolf NOT installed"
    fi

    command -v pat >/dev/null 2>&1 && _v_pass "Pat (Winlink) installed" \
                                   || _v_fail "Pat (Winlink) NOT installed"
    command -v rigctld >/dev/null 2>&1 && _v_pass "rigctld installed" \
                                       || _v_fail "rigctld NOT installed"

    # ------------------------------------------------------------------ user
    _v_head "2. Station identity"
    local uj="${VERIFY_USER_HOME:-$HOME}/.config/emcomm-tools/user.json"
    if [ -f "$uj" ]; then
        local call grid
        call=$(jq -r '.callsign // empty' "$uj" 2>/dev/null)
        grid=$(jq -r '.grid // empty' "$uj" 2>/dev/null)
        if [ -n "$call" ] && [ "$call" != "N0CALL" ]; then
            _v_pass "Callsign ${call}${grid:+ / grid ${grid}}"
        else
            _v_warn "Callsign not set in $uj (run: et-user)"
        fi
    else
        _v_warn "No user.json at $uj (run: et-user)"
    fi

    # ------------------------------------------------------------------ APRS
    _v_head "3. APRS / Dire Wolf"
    if [ ! -f "$APRS_TPL" ]; then
        _v_fail "APRS template missing: $APRS_TPL"
    else
        _v_pass "APRS template present"

        # Case-insensitive: the file contains IGSERVER/IGLOGIN and the word
        # "iGate". A case-sensitive grep for "igate" matches none of them --
        # that bug made this check silently unpassable in v1.
        if grep -qi '^IGSERVER' "$APRS_TPL"; then
            _v_pass "iGate configured: $(grep -i '^IGSERVER' "$APRS_TPL" | head -1)"
            grep -qi '^IGTXVIA' "$APRS_TPL" \
                && _v_warn "IGTXVIA present -- this gates internet traffic onto RF" \
                || _v_info "Receive-only (no IGTXVIA)"
        else
            _v_info "iGate not configured (RF only)"
        fi

        if grep -q '^GPSD' "$APRS_TPL"; then
            _v_pass "Beacon: GPS-tracked (GPSD + TBEACON)"
        elif grep -q '^PBEACON' "$APRS_TPL"; then
            if grep -q '^PBEACON.*lat=.*long=' "$APRS_TPL"; then
                _v_pass "Beacon: $(grep -o 'lat=[^ ]* long=[^ ]*' "$APRS_TPL" | head -1)"
            else
                # v1 emitted a PBEACON with no position at all.
                _v_fail "PBEACON has no lat=/long= -- beacon would carry no position"
            fi
        else
            _v_info "Position beaconing disabled"
        fi

        # ETC substitutes these on every launch; losing them breaks et-direwolf.
        grep -q '{{ET_CALLSIGN}}' "$APRS_TPL" && grep -q '{{ET_AUDIO_DEVICE}}' "$APRS_TPL" \
            && _v_pass "ETC placeholders preserved" \
            || _v_fail "ETC placeholders missing -- et-direwolf cannot substitute"

        # Dire Wolf's parser is line-oriented; a continuation is a hard error.
        grep -qE '\\$' "$APRS_TPL" \
            && _v_fail "Backslash continuation found -- Dire Wolf will reject this" \
            || _v_pass "No line continuations"

        # The real test: does Dire Wolf actually accept it?
        if command -v direwolf >/dev/null 2>&1; then
            local tmp out
            tmp=$(mktemp); out=$(mktemp)
            sed -e "s|{{ET_CALLSIGN}}|N0CALL|g" -e "s|{{ET_AUDIO_DEVICE}}|null|g" \
                "$APRS_TPL" > "$tmp"
            timeout 6 direwolf -c "$tmp" -t 0 >"$out" 2>&1 || true
            if grep -qiE 'Config file.*(error|invalid|unrecognized|no = found)' "$out"; then
                _v_fail "Dire Wolf rejects the config:"
                grep -iE 'Config file' "$out" | head -4 | sed 's/^/        /'
            else
                _v_pass "Dire Wolf parses the config with no errors"
            fi
            rm -f "$tmp" "$out"
        fi
    fi

    # ----------------------------------------------------------------- radio
    _v_head "4. Radio / CAT control"
    if hamlib_has_anytone; then
        _v_pass "Hamlib AnyTone backend: $(rigctl -l 2>/dev/null | grep -i anytone | head -1 | tr -s ' ')"
    else
        _v_warn "No AnyTone backend in Hamlib -- run ./build-hamlib-anytone.sh"
    fi

    local found=0 p
    for p in "$RADIOS"/anytone-d578uv.json "$RADIOS"/anytone-d578uv-com.json; do
        [ -f "$p" ] || continue
        found=1
        if jq -e . "$p" >/dev/null 2>&1; then
            local id; id=$(jq -r .rigctrl.id "$p")
            if [ "$id" = "37001" ]; then
                _v_pass "$(basename "$p"): model $id$(jq -r '.rigctrl.conf // "" | if .=="" then "" else " ("+.+")" end' "$p")"
            else
                # v1 shipped 301, which does not exist in Hamlib.
                _v_fail "$(basename "$p"): model $id is not a valid Hamlib model (expected 37001)"
            fi
        else
            _v_fail "$(basename "$p"): invalid JSON"
        fi
    done
    [ "$found" -eq 1 ] || _v_warn "No D578UVIII profiles -- run ./apply-to-live-system.sh"

    if [ -L "$RADIOS/active-radio.json" ]; then
        if [ -e "$RADIOS/active-radio.json" ]; then
            _v_pass "Active radio: $(basename "$(readlink -f "$RADIOS/active-radio.json")" .json)"
        else
            _v_fail "active-radio.json is a DANGLING symlink -> $(readlink "$RADIOS/active-radio.json")"
        fi
    else
        _v_info "No active radio selected (run: et-radio)"
    fi

    if systemctl is-active --quiet rigctld 2>/dev/null; then
        _v_pass "rigctld running"
    elif [ -e /dev/et-cat ]; then
        _v_warn "/dev/et-cat present but rigctld not running"
    else
        _v_info "rigctld not running (no radio plugged in?)"
    fi
    [ -e /dev/et-cat ]   && _v_pass "/dev/et-cat present"   || _v_info "/dev/et-cat absent (radio not connected)"
    [ -e /dev/et-audio ] && _v_pass "/dev/et-audio present" || _v_info "/dev/et-audio absent (radio not connected)"

    # ------------------------------------------------------------------- GPS
    _v_head "5. GPS"
    if direwolf_has_gpsd; then
        _v_pass "Dire Wolf built with GPSD support"
    else
        _v_info "Dire Wolf has no GPSD support -- ./build-direwolf-gpsd.sh enables GPS beaconing"
    fi
    [ -e /dev/et-gps ] && _v_pass "/dev/et-gps present" || _v_info "/dev/et-gps absent (no USB GPS)"

    # ------------------------------------------------------------------ WiFi
    _v_head "6. WiFi"
    local nmdir=/etc/NetworkManager/system-connections
    # NM stores one .nmconnection file per network here. v1 looked for
    # "^[connection:" inside conf.d/30-emcomm-tools.conf, which is neither the
    # right location nor the right format.
    if [ -r "$nmdir" ]; then
        local n; n=$(find "$nmdir" -maxdepth 1 -name '*.nmconnection' 2>/dev/null | wc -l)
        [ "$n" -gt 0 ] && _v_pass "$n saved network connection(s)" \
                       || _v_warn "No saved network connections"
    else
        _v_info "Cannot read $nmdir (needs root) -- skipping"
    fi

    # ---------------------------------------------------------------- addons
    _v_head "7. et-os-addons"
    local a present=0 missing=0
    for a in et-hotspot et-netcontrol et-varac et-qsstv et-js8spotter et-commstatone et-vr-n76-old; do
        if [ -x "${ET_PREFIX}/bin/$a" ]; then present=$((present+1)); else missing=$((missing+1)); fi
    done
    [ "$present" -gt 0 ] && _v_pass "$present addon launcher(s) installed, $missing not" \
                         || _v_info "No addon launchers installed"

    # --------------------------------------------------- v1 leftovers to undo
    _v_head "8. Leftovers from v1 (should all be absent)"
    local clean=1
    if [ -f /etc/udev/rules.d/99-emcomm-tools-cat.rules ]; then
        _v_fail "99-emcomm-tools-cat.rules present -- lets any FTDI/PL2303/CH340 steal /dev/et-cat"
        clean=0
    fi
    if [ -f /etc/systemd/system/rigctld.service ]; then
        _v_fail "/etc/systemd/system/rigctld.service override present -- restart-loops with no radio attached"
        clean=0
    fi
    if [ -f "${ET_PREFIX}/sbin/wrapper-rigctld.sh" ] && \
       grep -q 'Anytone D578UV is configured - preserving' "${ET_PREFIX}/sbin/wrapper-rigctld.sh" 2>/dev/null; then
        _v_fail "wrapper-rigctld.sh carries the v1 do_full_auto patch (that function is never called)"
        clean=0
    fi
    [ "$clean" -eq 1 ] && _v_pass "No v1 leftovers found"

    # --------------------------------------------------------------- summary
    _v_head "Summary"
    echo -e "  \033[0;32mPassed:\033[0m   $VERIFY_PASSED"
    [ "$VERIFY_WARNED" -gt 0 ] && echo -e "  \033[1;33mWarnings:\033[0m $VERIFY_WARNED"
    [ "$VERIFY_FAILED" -gt 0 ] && echo -e "  \033[0;31mFailed:\033[0m   $VERIFY_FAILED"
    echo
    [ "$VERIFY_FAILED" -eq 0 ]
}
