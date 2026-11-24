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
#   sudo ./apply-to-live-system.sh                 # APRS, radio, backup manifest
#   sudo ./apply-to-live-system.sh --addons        # ALSO run et-os-addons installers
#   sudo ./apply-to-live-system.sh --dry-run       # show what would change
#   sudo ./apply-to-live-system.sh --verify        # check the system, change nothing
#   sudo ./apply-to-live-system.sh --uninstall     # restore from newest backup
#   sudo ./apply-to-live-system.sh --list-backups
#
# This is the ROOT-level script. Its companion post-install.sh runs as YOUR user
# and handles home-directory work (backup restore, CHIRP). They do not overlap;
# verification is shared via lib/verify.sh.
#
# Sections: --no-aprs  --no-radio  --no-backup  --addons
#
# --addons is OPT-IN because it runs upstream et-os-addons installers that
# apt-purge and replace system packages. --uninstall restores files only, so it
# cannot reverse those; everything else here is file-only and fully reversible.
#
# Settings come from secrets.env (see secrets.env.template). Every value has a
# working default, so secrets.env is optional except for CALLSIGN and GRID_SQUARE
# -- and those are read from ~/.config/emcomm-tools/user.json if already set up.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ET_ROOT="/"
ET_PREFIX="/opt/emcomm-tools"
BACKUP_ROOT="${ET_PREFIX}/.customizer-backup"
STAMP=$(date +%Y%m%d-%H%M%S)
ET_BACKUP_DIR="${BACKUP_ROOT}/${STAMP}"
ET_DRY_RUN=0
SECRETS_FILE="${SECRETS_FILE:-${SCRIPT_DIR}/secrets.env}"
ADDONS_CACHE="${ADDONS_CACHE:-/var/cache/emcomm-tools-customizer/et-os-addons}"

# Sourced BEFORE argument parsing: --version prints CUSTOMIZER_VERSION, which
# lives in common.sh, and `set -u` would abort on it otherwise.
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# DO_ADDONS defaults to 0, deliberately.
#
# et-os-addons integration used to be a file copy, safe to run by default. It
# now executes upstream's installers, which `apt purge wsjtx wsjtx-doc
# wsjtx-data`, `apt purge kiwix`, pip-install into the system, and build QSSTV
# from source. None of that goes through backup(), so --uninstall cannot
# reverse it -- and this script's contract is that everything it touches is
# backed up. Opt in with --addons on a machine you are willing to change.
DO_APRS=1; DO_RADIO=1; DO_ADDONS=0; DO_BACKUP=1
UNINSTALL=0; LIST_BACKUPS=0; VERIFY_ONLY=0

for arg in "$@"; do
  case "$arg" in
    --dry-run)      ET_DRY_RUN=1 ;;
    --verify)       VERIFY_ONLY=1 ;;
    --uninstall)    UNINSTALL=1 ;;
    --list-backups) LIST_BACKUPS=1 ;;
    --no-aprs)      DO_APRS=0 ;;
    --no-radio)     DO_RADIO=0 ;;
    --addons)       DO_ADDONS=1 ;;
    --no-addons)    DO_ADDONS=0 ;;   # kept for compatibility; already the default
    --no-backup)    DO_BACKUP=0 ;;
    -V|--version)   echo "apply-to-live-system.sh ${CUSTOMIZER_VERSION}"; exit 0 ;;
    -h|--help)      sed -n '3,30p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

export ET_ROOT ET_PREFIX ET_BACKUP_DIR ET_DRY_RUN ADDONS_CACHE

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
  # anytone-d578uv-com.json was dropped in 7.0.2-1 but is still listed so an
  # uninstall on a system built by an older revision cleans it up.
  for added in "${ET_PREFIX}/conf/radios.d/anytone-d578uv.json" \
               "${ET_PREFIX}/conf/radios.d/anytone-d578uv-com.json" \
               "${ET_PREFIX}/conf/radios.d/anytone-d890.bt.json" \
               "${ET_PREFIX}/bin/et-anytone-d890" \
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

if [ "$VERIFY_ONLY" -eq 1 ]; then
  # Shared with post-install.sh --verify. Resolve the invoking user's home so
  # the user.json check looks at your account, not root's.
  if [ -n "${SUDO_USER:-}" ]; then
    VERIFY_USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    export VERIFY_USER_HOME
  fi
  # shellcheck source=lib/verify.sh
  source "${SCRIPT_DIR}/lib/verify.sh"
  echo "EmComm Tools Customizer ${CUSTOMIZER_VERSION} -- verification"
  verify_system
  exit $?
fi

echo "EmComm Tools Customizer ${CUSTOMIZER_VERSION} -- live system apply"
[ "$ET_DRY_RUN" -eq 1 ] && log "WARN" "DRY RUN -- nothing will be written"
echo "Backup directory: ${ET_BACKUP_DIR}"

# --- Settings --------------------------------------------------------------
if [ -f "$SECRETS_FILE" ]; then
  check_secrets_syntax "$SECRETS_FILE" || exit 1
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

if [ "$DO_BACKUP" -eq 1 ]; then
  step "3. et-user-backup manifest"
  # shellcheck source=lib/customize-backup.sh
  source "${SCRIPT_DIR}/lib/customize-backup.sh"
  # Snapshot the stock script first so its path list can be inherited, exactly
  # as the ISO build does. Harmless if a snapshot already exists.
  snapshot_stock_user_backup
  customize_user_backup_manifest
fi

if [ "$DO_ADDONS" -eq 1 ]; then
  step "4. et-os-addons installers"
  log "WARN" "These run upstream's installers, which change system packages:"
  log "WARN" "  apt purge wsjtx wsjtx-doc wsjtx-data   (WSJT-X Improved replaces it)"
  log "WARN" "  apt purge kiwix                        (AppImage replaces it)"
  log "WARN" "  pip installs, and a QSSTV source build"
  log "WARN" "--uninstall restores FILES only; it cannot undo package changes."
  if [ "$ET_DRY_RUN" -eq 0 ]; then
    log "WARN" "Ctrl-C within 10 seconds to abort."
    sleep 10
  fi
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
