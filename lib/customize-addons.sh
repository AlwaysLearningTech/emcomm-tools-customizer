# shellcheck shell=bash
#
# lib/customize-addons.sh -- et-os-addons integration
#
# Single source of truth for both the live system and the ISO build.
# Requires lib/common.sh to be sourced first.
#
# Source: https://github.com/clifjones/et-os-addons
#
# ---------------------------------------------------------------------------
# WHAT THIS DOES, AND WHY NOT `scripts/install.sh`
#
# et-os-addons is not an overlay of launchers -- that was this file's previous
# assumption and it was wrong. The repo carries NINE real installers under
# scripts/, each of which downloads and installs an actual application, plus a
# test suite under tests/. The earlier version of this module copied only
# overlay/ files and never touched scripts/, which is why:
#
#   - the Kiwix launcher pointed at ETC's apt kiwix, whose webserver is broken
#     (install-kiwix.sh purges it and installs the official AppImage; the
#     broken webserver is what prevents et-hotspot from serving content)
#   - the et-launcher .desktop pointed at an AppImage nothing had installed
#     (install-et-launcher.sh installs it, to /opt/appimages)
#   - we hand-rolled GridTracker, WSJT-X Improved, QSSTV and XyGrib installers
#     that were strictly worse than the upstream ones: GridTracker pinned seven
#     months stale, WSJT-X missing the `apt purge wsjtx wsjtx-doc wsjtx-data`
#     that has to happen before Improved overwrites ETC's binary, and QSSTV
#     pulling a stale qsl.net tarball instead of the ON4QZ repo.
#
# We still do NOT run scripts/install.sh. That script runs ETC's own installer
# first, from a submodule pinned in .gitmodules to `branch = release/r6`. Using
# it would build an R6 image and lose everything in R7 -- the Reticulum stack,
# et-wwv, Mercury, modem73, Pat 1.0.0, VARA 4.4.0/4.9.0, the Nov 2026 data
# sets, and the CVE-2026-31431 mitigation.
#
# So: run the individual installers against OUR R7 base.
#
# HOW THE SHIM WORKS
#
# Every installer opens with
#   [ -z "$ET_ENV_LOADED" ] && . $(dirname $(readlink -f $0))/env.sh
# so exporting ET_ENV_LOADED=1 makes them skip env.sh entirely -- which is what
# we want, because that env.sh sources ETC's scripts/env.sh and functions.sh
# out of the r6 submodule, and also exports ET_EXPERT=1 (which would turn on
# ETC's Wikipedia download dialog).
#
# Verified by grep: the installers use only ET_DIST_DIR, ET_SRC_DIR, ET_HOME,
# ET_OS_ADDONS_BASE, ET_LAUNCHER_APP_DL, SKEL and the et-log command. None of
# them call exitIfNotRoot or handle_error, so nothing from functions.sh is
# needed. The values below are ETC R7's own, from its scripts/env.sh.
# ---------------------------------------------------------------------------

ADDONS_REPO="${ADDONS_REPO:-https://github.com/clifjones/et-os-addons.git}"

# Fetch (or refresh) the addons source, setting ADDONS_REPO_PATH on success.
#
# NOTE: this deliberately does NOT print the path on stdout for the caller to
# capture. log() writes to stdout, so `ov=$(fetch_addons ...)` swallowed the
# "Cloning..." line into the result and produced a path like
#   "[INFO] Cloning https://...\n/var/cache/.../overlay"
# Every subsequent source lookup then missed and the whole addon step silently
# installed nothing -- but only on a FIRST run, since a warm cache never logs.
# A global cannot be polluted this way.
ADDONS_REPO_PATH=""

fetch_addons() {
    local cache="$1"
    ADDONS_REPO_PATH=""
    if [ -d "${cache}/.git" ]; then
        git -C "$cache" pull -q --ff-only 2>/dev/null || \
            log "WARN" "Could not refresh addons cache -- using existing copy"
    else
        mkdir -p "$(dirname "$cache")"
        log "INFO" "Cloning ${ADDONS_REPO}..."
        # --depth 1 only; the r6 submodule is deliberately NOT initialized.
        git clone --depth 1 -q "$ADDONS_REPO" "$cache" || return 1
    fi
    [ -d "${cache}/scripts" ] && [ -d "${cache}/overlay" ] || return 1
    ADDONS_REPO_PATH="$cache"
    return 0
}

# installer table: "<enable-var>|<default>|<script>|<label>"
#
# Order follows upstream scripts/install.sh. install-et-os-addons.sh is the
# overlay copy and must stay LAST: each app installer places its own .desktop
# and icon, and the overlay step then fills in what has no installer
# (et-hotspot, the Wine add-on scripts, the Saildocs grib scripts).
ADDONS_INSTALLERS=(
    "ENABLE_ETOSADDONS_XYGRIB|yes|install-xygrib.sh|XyGrib weather maps"
    "ENABLE_ETOSADDONS_WSJTX_IMPROVED|yes|install-wsjtx.sh|WSJT-X Improved (purges stock wsjtx first)"
    "ENABLE_ETOSADDONS_QSSTV|yes|install-qsstv.sh|QSSTV (source build, slow)"
    "ENABLE_ETOSADDONS_GRIDTRACKER|yes|install-gridtracker.sh|GridTracker 2"
    "ENABLE_ETOSADDONS_KIWIX|yes|install-kiwix.sh|Kiwix AppImage (replaces the broken apt package)"
    "ENABLE_ETOSADDONS_JS8SPOTTER|yes|install-js8spotter.sh|JS8Spotter"
    "ENABLE_ETOSADDONS_NETCONTROL|no|install-netcontrol.sh|NetControl (needs Wine + the .exe)"
    "ENABLE_ETOSADDONS_COMMSTATONE|no|install-commstatone.sh|CommStatOne"
    "ENABLE_ETOSADDONS_ET_LAUNCHER|no|install-et-launcher.sh|et-launcher AppImage + autostart"
    "ENABLE_ETOSADDONS_DESKTOP|no|customize-desktop.sh|glib schema override (fights customize_desktop)"
    "ENABLE_ETOSADDONS_OVERLAY|yes|install-et-os-addons.sh|overlay files (et-hotspot, Wine add-ons, grib)"
)

# Run one addons script against $ET_ROOT.
#
# ET_ROOT="/"  -> exec directly
# otherwise    -> exec inside the unpacked squashfs via chroot
#
# cwd is set to the scripts directory because customize-desktop.sh refers to
# ../overlay with a relative path, exactly as upstream's install.sh does.
_addons_run() {
    local script="$1" rel="$2"

    # Separate declaration from assignment: the string interpolates a command
    # substitution, and `local x="$(...)"` masks its return value (SC2155).
    local base env_prefix
    base="$(basename "$script")"

    # ETC R7 scripts/env.sh values, plus SKEL, plus the guard that stops the
    # installers from sourcing the r6-submodule env.sh.
    env_prefix="
        export ET_ENV_LOADED=1
        export ET_HOME=/opt/emcomm-tools
        export ET_GROUP=et-data
        export ET_TEMP_DIR=/tmp/et
        export ET_LOG_FILE=/tmp/et/et.log
        export ET_DIST_DIR=/opt/dist
        export ET_SRC_DIR=/opt/src
        export SKEL=/etc/skel
        export ET_OS_ADDONS_BASE='${rel}'
        export DEBIAN_FRONTEND=noninteractive
        mkdir -p \"\$ET_DIST_DIR\" \"\$ET_SRC_DIR\" \"\$ET_TEMP_DIR\"
        cd '${rel}/scripts'
        ./${base}
    "

    if [ "$ET_ROOT" = "/" ]; then
        bash -c "$env_prefix"
    else
        chroot "$ET_ROOT" /bin/bash -c "$env_prefix"
    fi
}

integrate_etosaddons_features() {
    local cache="${1:-${ADDONS_CACHE:-/var/cache/emcomm-tools-customizer/et-os-addons}}"

    log "INFO" "Integrating et-os-addons..."

    if ! fetch_addons "$cache"; then
        log "WARN" "et-os-addons unavailable (network?) -- skipping"
        return 0
    fi
    log "DEBUG" "addons repo: $ADDONS_REPO_PATH"

    # Stage the repo where the scripts will run from. On a live system it can
    # run from the cache in place; for an ISO build it has to be inside the
    # squashfs so chroot can reach it.
    local rel staged
    if [ "$ET_ROOT" = "/" ]; then
        rel="$ADDONS_REPO_PATH"
    else
        rel="/tmp/et-os-addons"
        staged="${ET_ROOT%/}${rel}"
        rm -rf "$staged"
        mkdir -p "$staged"
        # Exclude .git: it is dead weight inside the image.
        tar -C "$ADDONS_REPO_PATH" --exclude=.git -cf - . | tar -C "$staged" -xf - \
            || { log "ERROR" "Could not stage addons into $staged"; return 1; }
    fi

    if [ "$ET_DRY_RUN" -eq 1 ]; then
        log "INFO" "dry run -- would run these addons installers:"
    fi

    local entry var def script label val rc failed=0 ran=0
    for entry in "${ADDONS_INSTALLERS[@]}"; do
        IFS='|' read -r var def script label <<< "$entry"
        val="${!var:-$def}"

        if [ "$val" != "yes" ]; then
            log "DEBUG" "${var}=${val} -- skipping ${script}"
            continue
        fi

        if [ ! -f "${ADDONS_REPO_PATH}/scripts/${script}" ]; then
            log "WARN" "${script} not in this addons revision -- skipping"
            continue
        fi

        if [ "$ET_DRY_RUN" -eq 1 ]; then
            echo "       ${script}  -- ${label}"
            continue
        fi

        log "INFO" "  ${script} -- ${label}"
        rc=0
        _addons_run "$script" "$rel" || rc=$?

        if [ "$rc" -eq 0 ]; then
            ran=$((ran + 1))
        else
            # Best-effort by design: these are third-party downloads whose URLs
            # rot. One dead link must not fail a two-hour build.
            log "WARN" "  ${script} failed (rc=${rc}) -- continuing"
            failed=$((failed + 1))
        fi
    done

    [ "$ET_DRY_RUN" -eq 1 ] && return 0

    # The overlay step copies an et-launcher autostart entry unconditionally.
    # Without install-et-launcher.sh having run, that entry points at an
    # AppImage that is not there and errors on every login -- which is exactly
    # the breakage this module used to be blamed for.
    if [ "${ENABLE_ETOSADDONS_ET_LAUNCHER:-no}" != "yes" ]; then
        local autostart
        autostart="$(etpath /etc/skel/.config/autostart/et-launcher.appimage.desktop)"
        if [ -e "$autostart" ]; then
            rm -f "$autostart"
            log "DEBUG" "Removed et-launcher autostart (et-launcher not installed)"
        fi
    fi

    # Tidy the staged copy out of the image.
    [ -n "${staged:-}" ] && rm -rf "$staged"

    if [ "$failed" -gt 0 ]; then
        log "WARN" "et-os-addons: ${ran} installed, ${failed} failed -- see the log"
    else
        log "SUCCESS" "et-os-addons: ${ran} installers completed"
    fi

    # ---------------------------------------------------------------------
    # Deliberately NOT run:
    #  - scripts/install.sh       : runs ETC's installer from the r6-pinned
    #                               submodule. Would downgrade us off R7.
    #  - scripts/init-submodules.sh : fetches that r6 submodule, and overwrites
    #                               /etc/apt/sources.list on the way. We fix
    #                               apt sources ourselves, earlier.
    #  - scripts/pre-install.sh   : only mkdir's ET_DIST_DIR, which _addons_run
    #                               already does.
    #  - customize-desktop.sh     : OFF by default. It installs a glib schema
    #                               override that changes desktop defaults
    #                               system-wide, competing with
    #                               customize_desktop()'s dconf database.
    #
    # ORDERING NOTE: install-et-os-addons.sh copies overlay/etc/skel/* wholesale,
    # which includes its own BACKUP_ITEMS.lst, and overlay/opt/emcomm-tools/*,
    # which includes its own et-user-backup. Both are superseded by
    # customize_user_backup_manifest(), so that step MUST run after this one.
    # main()'s step table is ordered accordingly.
    # ---------------------------------------------------------------------
    return 0
}
