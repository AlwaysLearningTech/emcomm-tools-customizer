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
# HOW THE SHIM WORKS -- two layers, because one is not enough
#
# MOST installers open with
#   [ -z "$ET_ENV_LOADED" ] && . $(dirname $(readlink -f $0))/env.sh
# so exporting ET_ENV_LOADED=1 makes them skip env.sh -- which is what we want,
# because that env.sh sources ETC's scripts/env.sh and functions.sh out of the
# r6 submodule, and exports ET_EXPERT=1 (which would turn on ETC's interactive
# Wikipedia download dialog and stall an unattended build).
#
# install-qsstv.sh does NOT have that guard. It runs `. ./env.sh`
# unconditionally, and it is `set -e`, so with an un-initialized submodule it
# aborts before installing anything. Relying on the guard alone therefore
# silently loses QSSTV -- and would lose any other script that drops it.
#
# So layer two: _addons_write_env_stubs() writes a stub env.sh and functions.sh
# into the empty submodule directory, exporting ETC R7's values and defining
# the two helpers upstream's functions.sh provides. Any script that sources the
# chain now gets our values, ET_EXPERT included (absent, on purpose).
#
# Verified by grep that the installers need only ET_DIST_DIR, ET_SRC_DIR,
# ET_HOME, ET_OS_ADDONS_BASE, ET_LAUNCHER_APP_DL, SKEL and the et-log command.
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
    "ENABLE_ETOSADDONS_COMMSTATONE|yes|install-commstatone.sh|CommStatOne JS8Call dashboard"
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
    #
    # PATH includes /opt/emcomm-tools/bin defensively. ETC symlinks et-log into
    # /usr/local/bin, which is on sudo's secure_path, so this is belt-and-braces
    # rather than required -- but every one of these scripts is `set -e` with
    # et-log as its first statement, so a missing et-log means a silent no-op.
    env_prefix="
        export PATH=\"/opt/emcomm-tools/bin:\$PATH\"
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

    # stdin from /dev/null: an unexpected apt or unzip prompt must fail rather
    # than block a two-hour unattended build waiting on a terminal.
    if [ "$ET_ROOT" = "/" ]; then
        bash -c "$env_prefix" </dev/null
    else
        chroot "$ET_ROOT" /bin/bash -c "$env_prefix" </dev/null
    fi
}

# Write stub env.sh / functions.sh into the un-initialized submodule directory.
#
# Most installers guard with `[ -z "$ET_ENV_LOADED" ] && . env.sh`, so the
# ET_ENV_LOADED=1 we export is enough. install-qsstv.sh does NOT: it runs
# `. ./env.sh` unconditionally. That file does
#
#     . ${ET_OS_ADDONS_BASE}/emcomm-tools-os-community/scripts/env.sh
#     . ${ET_OS_ADDONS_BASE}/emcomm-tools-os-community/scripts/functions.sh
#
# and we clone --depth 1 WITHOUT the submodule (deliberately -- it is pinned to
# release/r6). That directory is therefore empty, both sources fail, and under
# `set -e` QSSTV aborts before installing anything.
#
# Rather than depend on every upstream script keeping its guard, satisfy the
# chain: stubs that export ETC R7's values and define the two helpers the real
# functions.sh provides. Any script that sources env.sh now gets our values
# instead of the r6 submodule's -- notably WITHOUT ET_EXPERT=1, which upstream
# sets and which would switch on ETC's interactive Wikipedia dialog.
_addons_write_env_stubs() {
    local repo="$1"
    local stub_dir="${repo}/emcomm-tools-os-community/scripts"
    mkdir -p "$stub_dir" || return 1

    cat > "${stub_dir}/env.sh" <<'STUBEOF'
# Stub written by emcomm-tools-customizer.
#
# The real file lives in et-os-addons' submodule, which is pinned to ETC
# release/r6 and is deliberately not initialized -- we build against R7. These
# are ETC R7's own scripts/env.sh values.
#
# ET_EXPERT is deliberately NOT exported. Upstream's env.sh sets it to 1, which
# turns on ETC's interactive Wikipedia download dialog and would stall an
# unattended build.
export ET_HOME=/opt/emcomm-tools
export ET_GROUP=et-data
export ET_TEMP_DIR=/tmp/et
export ET_LOG_FILE=$ET_TEMP_DIR/et.log
export ET_DIST_DIR=/opt/dist
export ET_SRC_DIR=/opt/src
export SKEL=/etc/skel
export ET_ENV_LOADED=1
STUBEOF

    cat > "${stub_dir}/functions.sh" <<'STUBEOF'
# Stub written by emcomm-tools-customizer. See env.sh in this directory.
#
# Only the two helpers upstream's env.sh calls or defines. Verified by grep
# that none of the install-*.sh scripts use anything else from functions.sh.
exitIfNotRoot() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root." >&2
    exit 1
  fi
}

handle_error() {
  echo "Error in ${1:-?} on line ${2:-?}: ${3:-?}" >&2
  exit 1
}
STUBEOF

    return 0
}

integrate_etosaddons_features() {
    local cache="${1:-${ADDONS_CACHE:-/var/cache/emcomm-tools-customizer/et-os-addons}}"

    log "INFO" "Integrating et-os-addons..."

    if ! fetch_addons "$cache"; then
        log "WARN" "et-os-addons unavailable (network?) -- skipping"
        return 0
    fi
    log "DEBUG" "addons repo: $ADDONS_REPO_PATH"

    local entry var def script label val rc failed=0 ran=0

    # Report and return BEFORE touching anything. The staging below rm -rf's
    # and untars inside the target root, which a dry run must not do.
    if [ "$ET_DRY_RUN" -eq 1 ]; then
        log "INFO" "dry run -- would run these addons installers:"
        for entry in "${ADDONS_INSTALLERS[@]}"; do
            IFS='|' read -r var def script label <<< "$entry"
            val="${!var:-$def}"
            [ "$val" = "yes" ] || continue
            [ -f "${ADDONS_REPO_PATH}/scripts/${script}" ] || continue
            echo "       ${script}  -- ${label}"
        done
        return 0
    fi

    # Stage the repo where the scripts will run from. On a live system it can
    # run from the cache in place; for an ISO build it has to be inside the
    # squashfs so chroot can reach it.
    local rel staged
    if [ "$ET_ROOT" = "/" ]; then
        rel="$ADDONS_REPO_PATH"
        _addons_write_env_stubs "$ADDONS_REPO_PATH" \
            || { log "ERROR" "Could not write env stubs"; return 1; }
    else
        rel="/tmp/et-os-addons"
        staged="${ET_ROOT%/}${rel}"
        rm -rf "$staged"
        mkdir -p "$staged"
        # Exclude .git: it is dead weight inside the image.
        tar -C "$ADDONS_REPO_PATH" --exclude=.git -cf - . | tar -C "$staged" -xf - \
            || { log "ERROR" "Could not stage addons into $staged"; return 1; }
        _addons_write_env_stubs "$staged" \
            || { log "ERROR" "Could not write env stubs into $staged"; return 1; }
    fi
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

    # NOTE: no et-launcher autostart cleanup here. install-et-os-addons.sh
    # copies `overlay/etc/skel/*`, and that glob cannot match the `.config`
    # dot-directory holding et-launcher.appimage.desktop -- so the overlay step
    # never places it. Only install-et-launcher.sh does, and that is gated.

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
