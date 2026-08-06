# shellcheck shell=bash
#
# lib/common.sh -- shared helpers for emcomm-tools-customizer
#
# Sourced by both apply-to-live-system.sh (live system, ET_ROOT=/) and
# build-etc-iso.sh (ISO build, ET_ROOT=$SQUASHFS_DIR). Every customization
# module operates on $ET_ROOT so the two paths cannot drift apart.
#
# Contract for callers:
#   ET_ROOT        target filesystem root ("/" for live, squashfs dir for ISO)
#   ET_DRY_RUN     1 = describe actions only
#   ET_BACKUP_DIR  where backup() stashes originals (live path only)
#
# build-etc-iso.sh already defines its own log(); guard so we don't clobber it.

ET_ROOT="${ET_ROOT:-/}"
ET_DRY_RUN="${ET_DRY_RUN:-0}"
ET_BACKUP_DIR="${ET_BACKUP_DIR:-}"

# ETC install prefix, relative to ET_ROOT
ET_PREFIX="${ET_PREFIX:-/opt/emcomm-tools}"

if ! declare -F log >/dev/null 2>&1; then
    _ET_RED=$'\033[0;31m'; _ET_GRN=$'\033[0;32m'
    _ET_YEL=$'\033[1;33m'; _ET_NC=$'\033[0m'
    log() {
        local level="$1"; shift
        case "$level" in
            SUCCESS|OK) echo "${_ET_GRN}[ OK ]${_ET_NC} $*" ;;
            WARN)       echo "${_ET_YEL}[WARN]${_ET_NC} $*" ;;
            ERROR)      echo "${_ET_RED}[FAIL]${_ET_NC} $*" >&2 ;;
            DEBUG)      [ "${DEBUG_MODE:-0}" -eq 1 ] && echo "[DBG ] $*" ;;
            *)          echo "[INFO] $*" ;;
        esac
        return 0
    }
fi

# Resolve a path inside the target root.
#   etpath /opt/emcomm-tools/bin  ->  /opt/emcomm-tools/bin        (live)
#                                 ->  /work/squashfs/opt/...       (ISO build)
etpath() {
    local p="$1"
    if [ "$ET_ROOT" = "/" ]; then
        printf '%s\n' "$p"
    else
        printf '%s\n' "${ET_ROOT%/}${p}"
    fi
}

# Back up a file before first modification, mirroring its path under
# ET_BACKUP_DIR. No-op when ET_BACKUP_DIR is unset (ISO builds -- the squashfs
# is disposable, so backups there are pointless).
backup() {
    local f="$1"
    [ -n "$ET_BACKUP_DIR" ] || return 0
    [ -e "$f" ] || [ -L "$f" ] || return 0
    if [ "$ET_DRY_RUN" -eq 1 ]; then
        echo "       would back up: $f"
        return 0
    fi
    local dest="${ET_BACKUP_DIR}${f}"
    mkdir -p "$(dirname "$dest")"
    cp -a "$f" "$dest"
}

# Write a file from stdin, backing up any existing copy first.
#   write_file <path> <mode>
write_file() {
    local path="$1" mode="${2:-644}"
    backup "$path"
    if [ "$ET_DRY_RUN" -eq 1 ]; then
        echo "       would write: $path (mode $mode)"
        cat >/dev/null
        return 0
    fi
    mkdir -p "$(dirname "$path")"
    cat > "$path" || return 1
    chmod "$mode" "$path"
}

# Install one file, backing up any existing copy.
#   install_file <src> <dest-path> <mode> [label]
install_file() {
    local src="$1" dest="$2" mode="$3" label="${4:-}"
    if [ ! -f "$src" ]; then
        log "WARN" "source missing, skipping: $src${label:+ ($label)}"
        return 1
    fi
    backup "$dest"
    if [ "$ET_DRY_RUN" -eq 1 ]; then
        echo "       would install: $dest${label:+  -- $label}"
        return 0
    fi
    mkdir -p "$(dirname "$dest")"
    if install -m "$mode" "$src" "$dest"; then
        log "SUCCESS" "$(basename "$dest")${label:+  -- $label}"
    else
        log "WARN" "failed to install $dest"
        return 1
    fi
}

# Compute the APRS-IS passcode for a callsign. The algorithm is public and the
# result is derivable by anyone who knows the callsign -- it is not a secret,
# which is why it is computed rather than stored in secrets.env.
aprs_passcode() {
    local call="${1%%-*}"
    call="${call^^}"
    local h=$((0x73e2)) i c
    for (( i=0; i<${#call}; i++ )); do
        printf -v c '%d' "'${call:$i:1}"
        if (( i % 2 == 0 )); then h=$(( h ^ (c << 8) )); else h=$(( h ^ c )); fi
    done
    echo $(( h & 0x7fff ))
}

# Convert a Maidenhead grid square to the decimal lat/long of its center.
# Prints "lat lon". Accepts 4- or 6-character grids.
grid_to_latlon() {
    local g="$1"
    [ ${#g} -ge 4 ] || { log "ERROR" "grid too short: $g"; return 1; }
    local F=${g:0:1} S=${g:1:1} f=${g:2:1} s=${g:3:1}
    local lon lat
    lon=$(( ( $(printf '%d' "'${F^^}") - 65 ) * 20 - 180 ))
    lat=$(( ( $(printf '%d' "'${S^^}") - 65 ) * 10 - 90 ))
    lon=$(( lon + f * 2 ))
    lat=$(( lat + s ))
    if [ ${#g} -ge 6 ]; then
        local u=${g:4:1} v=${g:5:1}
        awk -v lon="$lon" -v lat="$lat" \
            -v u="$(printf '%d' "'${u,,}")" -v v="$(printf '%d' "'${v,,}")" \
            'BEGIN {
               lon += (u-97)*(2.0/24) + (2.0/24)/2
               lat += (v-97)*(1.0/24) + (1.0/24)/2
               printf "%.4f %.4f\n", lat, lon
             }'
    else
        # 4-char grid: center of the 2x1 degree square
        awk -v lon="$lon" -v lat="$lat" \
            'BEGIN { printf "%.4f %.4f\n", lat+0.5, lon+1.0 }'
    fi
}

# NOTE for both probes below: direwolf and rigctl are invoked with no useful
# arguments and exit NON-ZERO (they print usage). Callers run with
# `set -o pipefail`, so `direwolf | grep -q ...` would report failure even when
# grep matches. Capture the output first and let grep alone decide.

# True if the direwolf that will run on the target was built with GPSD support.
# Only meaningful for the live path; ISO builds cannot exec the target binary.
direwolf_has_gpsd() {
    [ "$ET_ROOT" = "/" ] || return 1
    command -v direwolf >/dev/null 2>&1 || return 1
    local out
    out=$(direwolf 2>&1 </dev/null || true)
    printf '%s' "$out" | grep -qi 'optional support for.*gpsd'
}

# True if this Hamlib knows the AnyTone backend (model 37001).
hamlib_has_anytone() {
    command -v rigctl >/dev/null 2>&1 || return 1
    local out
    out=$(rigctl -l 2>/dev/null || true)
    printf '%s' "$out" | grep -qi anytone
}
