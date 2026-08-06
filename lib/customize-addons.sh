# shellcheck shell=bash
#
# lib/customize-addons.sh -- et-os-addons optional features
#
# Single source of truth for both the live system and the ISO build.
# Requires lib/common.sh to be sourced first.
#
# Source: https://github.com/clifjones/et-os-addons
#
# Each feature is grouped by whether it actually WORKS on a stock ETC v6 system,
# because most of them ship only a launcher and depend on an application that
# ETC does not install. v1 of this repo installed them all silently and reported
# success, leaving launchers that error on click.
#
# Reads (optional, from secrets.env): ENABLE_ETOSADDONS_* -- see secrets.env.template

ADDONS_REPO="${ADDONS_REPO:-https://github.com/clifjones/et-os-addons.git}"

# Fetch (or refresh) the addons source. Prints the overlay path on stdout.
fetch_addons() {
    local cache="$1"
    if [ -d "${cache}/.git" ]; then
        git -C "$cache" pull -q --ff-only 2>/dev/null || \
            log "WARN" "Could not refresh addons cache -- using existing copy"
    else
        mkdir -p "$(dirname "$cache")"
        log "INFO" "Cloning ${ADDONS_REPO}..."
        git clone --depth 1 -q "$ADDONS_REPO" "$cache" || return 1
    fi
    [ -d "${cache}/overlay" ] || return 1
    printf '%s\n' "${cache}/overlay"
}

integrate_etosaddons_features() {
    local cache="${1:-${ADDONS_CACHE:-/var/cache/emcomm-tools-customizer/et-os-addons}}"

    log "INFO" "Integrating et-os-addons features..."

    local ov
    if ! ov=$(fetch_addons "$cache"); then
        log "WARN" "et-os-addons unavailable (network?) -- skipping"
        return 0
    fi

    local BIN TPL APPS PIX
    BIN="$(etpath "${ET_PREFIX}/bin")"
    TPL="$(etpath "${ET_PREFIX}/conf/template.d")"
    APPS="$(etpath /usr/share/applications)"
    PIX="$(etpath /usr/share/pixmaps)"

    # add <enable-var> <default> <src-rel> <dest-dir> <mode> <label>
    add() {
        local var="$1" def="$2" src="$3" dest="$4" mode="$5" label="$6"
        local val="${!var:-$def}"
        if [ "$val" != "yes" ]; then
            log "DEBUG" "${var}=${val} -- skipping $(basename "$src")"
            return 0
        fi
        install_file "${ov}/${src}" "${dest}/$(basename "$src")" "$mode" "$label"
    }

    echo "-- Working immediately (no extra packages needed) --"
    add ENABLE_ETOSADDONS_HOTSPOT yes \
        opt/emcomm-tools/bin/et-hotspot "$BIN" 755 "WiFi hotspot (nmcli wrapper)"
    add ENABLE_ETOSADDONS_KIWIX yes \
        usr/share/applications/kiwix.desktop "$APPS" 644 "Kiwix launcher"
    add ENABLE_ETOSADDONS_KIWIX yes \
        usr/share/pixmaps/kiwix-desktop.svg "$PIX" 644 "Kiwix icon"

    echo "-- Wine apps (launcher installs; the .exe is a separate install) --"
    add ENABLE_ETOSADDONS_NETCONTROL yes \
        opt/emcomm-tools/bin/et-netcontrol "$BIN" 755 "needs drive_c/netcontrol/NetControl.exe"
    add ENABLE_ETOSADDONS_NETCONTROL yes \
        usr/share/applications/netcontrol.desktop "$APPS" 644 "NetControl launcher"
    add ENABLE_ETOSADDONS_NETCONTROL yes \
        usr/share/pixmaps/netcontrol.png "$PIX" 644 "NetControl icon"
    add ENABLE_ETOSADDONS_VARAC yes \
        opt/emcomm-tools/bin/et-varac "$BIN" 755 "needs drive_c/VarAC/VarAC.exe"
    add ENABLE_ETOSADDONS_VARA_EXTRAS yes \
        opt/emcomm-tools/bin/et-vara-chat "$BIN" 755 "VARA Chat"
    add ENABLE_ETOSADDONS_VARA_EXTRAS yes \
        opt/emcomm-tools/bin/et-vara-sat "$BIN" 755 "VARA SAT"
    add ENABLE_ETOSADDONS_VARA_EXTRAS yes \
        opt/emcomm-tools/bin/et-vara-terminal "$BIN" 755 "VARA Terminal"

    echo "-- Launchers whose application is not installed by ETC --"
    add ENABLE_ETOSADDONS_QSSTV yes \
        opt/emcomm-tools/bin/et-qsstv "$BIN" 755 "needs /usr/local/bin/qsstv"
    add ENABLE_ETOSADDONS_QSSTV yes \
        opt/emcomm-tools/conf/template.d/qsstv_9.0.conf "$TPL" 644 "QSSTV config template"
    add ENABLE_ETOSADDONS_JS8SPOTTER yes \
        opt/emcomm-tools/bin/et-js8spotter "$BIN" 755 "needs ~/apps/js8spotter"
    add ENABLE_ETOSADDONS_JS8SPOTTER yes \
        usr/share/applications/js8spotter.desktop "$APPS" 644 "JS8Spotter launcher"
    add ENABLE_ETOSADDONS_COMMSTATONE yes \
        opt/emcomm-tools/bin/et-commstatone "$BIN" 755 "needs ~/apps CommStatOne"
    add ENABLE_ETOSADDONS_COMMSTATONE yes \
        opt/emcomm-tools/conf/template.d/commstatone.ini "$TPL" 644 "CommStatOne template"

    echo "-- Misc --"
    add ENABLE_ETOSADDONS_VR_N76 yes \
        opt/emcomm-tools/bin/et-vr-n76-old "$BIN" 755 "VR-N76 legacy BT TNC (needs expect)"

    # Opt-in only: stock ETC v6 already ships et-user-backup. The addons version
    # swaps in a BACKUP_ITEMS.lst manifest, silently changing what gets backed up.
    add ENABLE_ETOSADDONS_USERBACKUP no \
        opt/emcomm-tools/bin/et-user-backup "$BIN" 755 "REPLACES stock et-user-backup"

    # -----------------------------------------------------------------------
    # Deliberately NOT installed, and why:
    #  - etc/apt/sources.list  : repointing apt on a working system is invasive.
    #  - glib schema override  : needs glib-compile-schemas and changes desktop
    #                            defaults system-wide.
    #  - et-launcher autostart : points at an AppImage ETC does not install, so
    #                            it errors on every login.
    #  - vgc-vrn76.bt.json     : already present in stock radios.d -- no-op.
    #  - et-wsjtx              : NOT in the addons repo at all. Stock v6 already
    #                            ships /opt/emcomm-tools/bin/et-wsjtx. v1's
    #                            ENABLE_ETOSADDONS_WSJTX flag was dead code that
    #                            silently did nothing.
    # -----------------------------------------------------------------------

    if [ "$ET_DRY_RUN" -eq 0 ] && [ "$ET_ROOT" = "/" ] && \
       command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$APPS" 2>/dev/null || true
    fi

    log "SUCCESS" "et-os-addons features integrated"
    return 0
}
