#!/bin/bash
#
# Apply EmComm Tools customizations to an ALREADY-INSTALLED ETC system.
#
# This is the manual-install and upgrade path: no Cubic, no ISO rebuild, and
# no disk, partition or block-device operations of any kind. It only writes
# files into an existing filesystem, and backs up everything it touches.
#
# It shares lib/ with build-etc-iso.sh, so a live system and a freshly built
# ISO get byte-identical configuration.
#
# Usage:
#   sudo ./apply-to-live-system.sh                 # apply everything
#   sudo ./apply-to-live-system.sh --dry-run       # show what would change
#   sudo ./apply-to-live-system.sh --uninstall     # restore from newest backup
#   sudo ./apply-to-live-system.sh --list-backups
#
# Sections: --no-aprs  --no-radio  --no-addons
#
# Settings come from secrets.env (see secrets.env.template). Every value has a
# working default, so secrets.env is optional except for CALLSIGN and GRID_SQUARE
# -- and those are read from ~/.config/emcomm-tools/user.json if already set up.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="2.0.0"

ET_ROOT="/"
ET_PREFIX="/opt/emcomm-tools"
BACKUP_ROOT="${ET_PREFIX}/.customizer-backup"
STAMP=$(date +%Y%m%d-%H%M%S)
ET_BACKUP_DIR="${BACKUP_ROOT}/${STAMP}"
ET_DRY_RUN=0
SECRETS_FILE="${SECRETS_FILE:-${SCRIPT_DIR}/secrets.env}"
ADDONS_CACHE="${ADDONS_CACHE:-/var/cache/emcomm-tools-customizer/et-os-addons}"

DO_APRS=1; DO_RADIO=1; DO_ADDONS=1; UNINSTALL=0; LIST_BACKUPS=0

for arg in "$@"; do
  case "$arg" in
    --dry-run)      ET_DRY_RUN=1 ;;
    --uninstall)    UNINSTALL=1 ;;
    --list-backups) LIST_BACKUPS=1 ;;
    --no-aprs)      DO_APRS=0 ;;
    --no-radio)     DO_RADIO=0 ;;
    --no-addons)    DO_ADDONS=0 ;;
    -V|--version)   echo "apply-to-live-system.sh ${VERSION}"; exit 0 ;;
    -h|--help)      sed -n '3,24p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

export ET_ROOT ET_PREFIX ET_BACKUP_DIR ET_DRY_RUN ADDONS_CACHE

# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

step() { echo; echo "=== $* ==="; }

# ---------------------------------------------------------------------------
list_backups() {
  step "Backups under ${BACKUP_ROOT}"
  if ! compgen -G "${BACKUP_ROOT}/*/" >/dev/null; then
    echo "  (none)"; return 0
  fi
  for d in "${BACKUP_ROOT}"/*/; do
    printf "  %-20s %s files\n" "$(basename "${d%/}")" "$(find "$d" -type f -o -type l | wc -l)"
  done
}

do_uninstall() {
  step "Uninstall -- restoring from the most recent backup"
  local latest
  latest=$(find "$BACKUP_ROOT" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort | tail -1)
  [ -n "$latest" ] || { log "ERROR" "No backup found under $BACKUP_ROOT"; exit 1; }
  echo "Restoring from: $latest"

  local n=0
  while IFS= read -r rel; do
    local src="${latest}/${rel#./}" dst="/${rel#./}"
    mkdir -p "$(dirname "$dst")"
    rm -f "$dst"
    cp -a "$src" "$dst" && { echo "  restored $dst"; n=$((n+1)); }
  done < <(cd "$latest" && find . -type f -o -type l)

  # Remove files we added that had no pre-existing counterpart to restore.
  local added
  for added in "${ET_PREFIX}/conf/radios.d/anytone-d578uv.json" \
               "${ET_PREFIX}/conf/radios.d/anytone-d578uv-com.json" \
               "${ET_PREFIX}/conf/radios.d/active-radio.json"; do
    [ -e "${latest}${added}" ] || [ -L "${latest}${added}" ] || rm -fv "$added" 2>/dev/null
  done

  log "SUCCESS" "Restored $n file(s). Run 'et-radio' to reselect a radio."
}

# ---------------------------------------------------------------------------
[ "$(id -u)" -eq 0 ] || { log "ERROR" "Must run as root: sudo $0"; exit 1; }
[ -d "$ET_PREFIX" ] || { log "ERROR" "$ET_PREFIX not found -- is this an ETC system?"; exit 1; }

[ "$LIST_BACKUPS" -eq 1 ] && { list_backups; exit 0; }
[ "$UNINSTALL" -eq 1 ]    && { do_uninstall; exit 0; }

echo "EmComm Tools Customizer ${VERSION} -- live system apply"
[ "$ET_DRY_RUN" -eq 1 ] && log "WARN" "DRY RUN -- nothing will be written"
echo "Backup directory: ${ET_BACKUP_DIR}"

# --- Settings --------------------------------------------------------------
if [ -f "$SECRETS_FILE" ]; then
  # shellcheck source=/dev/null
  source "$SECRETS_FILE"
  log "INFO" "Loaded settings from $SECRETS_FILE"
else
  log "INFO" "No secrets.env -- using defaults (copy secrets.env.template to customize)"
fi

# Fall back to ETC's own user.json so a configured system needs no secrets.env.
# Under sudo, $HOME is root's, so resolve the invoking user's home instead.
USER_HOME=""
if [ -n "${SUDO_USER:-}" ]; then
  USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
fi
USER_JSON="${USER_HOME:-$HOME}/.config/emcomm-tools/user.json"
if [ -z "${CALLSIGN:-}" ] && [ -f "$USER_JSON" ]; then
  CALLSIGN=$(jq -r '.callsign // empty' "$USER_JSON" 2>/dev/null)
  GRID_SQUARE="${GRID_SQUARE:-$(jq -r '.grid // empty' "$USER_JSON" 2>/dev/null)}"
  log "INFO" "Read callsign/grid from $USER_JSON"
fi
export CALLSIGN="${CALLSIGN:-N0CALL}" GRID_SQUARE="${GRID_SQUARE:-}"
log "INFO" "Station: ${CALLSIGN}${GRID_SQUARE:+ / $GRID_SQUARE}"

# --- Apply -----------------------------------------------------------------
if [ "$DO_APRS" -eq 1 ]; then
  step "1. APRS / Dire Wolf"
  # shellcheck source=lib/customize-aprs.sh
  source "${SCRIPT_DIR}/lib/customize-aprs.sh"
  customize_aprs
fi

if [ "$DO_RADIO" -eq 1 ]; then
  step "2. Anytone AT-D578UVIII radio profiles"
  # shellcheck source=lib/customize-radio.sh
  source "${SCRIPT_DIR}/lib/customize-radio.sh"
  customize_radio_configs
fi

if [ "$DO_ADDONS" -eq 1 ]; then
  step "3. et-os-addons features"
  # shellcheck source=lib/customize-addons.sh
  source "${SCRIPT_DIR}/lib/customize-addons.sh"
  integrate_etosaddons_features "$ADDONS_CACHE"
fi

# ---------------------------------------------------------------------------
step "Done"
if [ "$ET_DRY_RUN" -eq 1 ]; then
  log "WARN" "Dry run -- nothing was written."
else
  echo "Backups: ${ET_BACKUP_DIR}"
  echo "Undo:    sudo $0 --uninstall"
  echo
  echo "Next steps:"
  echo "  1. Plug in the DigiRig + D578UV, then:  systemctl status rigctld"
  echo "  2. Confirm radio selection:             et-radio"
  echo "  3. Verify PTT before trusting it on air:"
  echo "       rigctl -m 2 -r localhost:4532 T 1   # key"
  echo "       rigctl -m 2 -r localhost:4532 T 0   # unkey"
  echo "  4. Start APRS:                          et-mode -> aprs-digipeater"
  if ! hamlib_has_anytone; then
    echo
    log "WARN" "Hamlib has no AnyTone backend yet -- run ./build-hamlib-anytone.sh"
  fi
  if ! direwolf_has_gpsd; then
    log "INFO" "For GPS-tracked beaconing, run ./build-direwolf-gpsd.sh"
  fi
fi
