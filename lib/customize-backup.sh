# shellcheck shell=bash
#
# lib/customize-backup.sh -- manifest-driven et-user-backup
#
# Single source of truth for both the live system and the ISO build.
# Requires lib/common.sh to be sourced first.
#
# Reads (optional, from secrets.env):
#   ENABLE_MANIFEST_BACKUP   yes|no  (default yes)
#   BACKUP_EXTRA_ITEMS       newline- or space-separated extra paths
#
# ---------------------------------------------------------------------------
# Why this exists: R7's et-user-backup and et-os-addons' fork each have
# something the other needs.
#
# R7's version (stock):
#   + filters BACKUP_DIRS down to paths that actually exist, logging skips,
#     so tar never errors on a missing directory
#   + uses --transform to normalise .local paths
#   - the list is HARDCODED in the script, so adding a directory means
#     editing a file that the next ETC release overwrites
#
# et-os-addons' version:
#   + manifest-driven (tar -T ~/BACKUP_ITEMS.lst) -- add a path, no code change
#   + its default manifest covers what an operator actually accumulates:
#     .wine32, .fldigi, .nbems, YAAC, qsstv, my-maps, Documents, .navit/maps
#   - dropped the existence filtering, so tar warns/errors on missing paths
#   - carries a bug: the summary loop reads "${BACKUP_DIRS[@]}", which it never
#     assigns, so "the following were backed up" prints an EMPTY list
#
# This takes R7's correctness and the addons' extensibility, and fixes the bug
# by construction (the summary iterates the filtered list that tar was given).
#
# The manifest is GENERATED AT BUILD TIME by extracting R7's own BACKUP_DIRS
# array out of the installed et-user-backup and unioning it with the extras
# below. That matters: when a future ETC release adds to its list -- as R7 did
# with Reticulum, Partyline, NomadNet and the JS8Call files -- we inherit the
# addition automatically instead of silently falling behind a hardcoded copy.
# ---------------------------------------------------------------------------

# Paths et-os-addons backs up that ETC does not. Kept here, not in
# secrets.env, because they describe how ETC and its apps lay out a home
# directory -- not an operator preference. Use BACKUP_EXTRA_ITEMS for that.
ET_BACKUP_EXTRAS=(
    ".local/share/WSJT-X"
    ".navit/bookmark.txt"
    ".fldigi"
    ".nbems"
    "YAAC"
    "qsstv"
    "itshfbc"
    "notes"
    "Documents"
    "add-ons"
)

# DELIBERATELY NOT in the list above, despite et-os-addons including it:
#
#   .wine32   ETC backs the Wine prefix up SEPARATELY, via et-wine-backup, and
#             restore_user_backup() in build-etc-iso.sh relies on that split --
#             it restores the user archive quickly and defers the Wine prefix.
#             On this machine the two archives are 642MB and 726MB; folding
#             .wine32 into the user backup would roughly double the "quick"
#             restore and make every routine backup carry a VARA install that
#             changes maybe twice a year.
#
#             Add it with BACKUP_EXTRA_ITEMS=".wine32" if you want one archive.
#
#   .navit/maps, my-maps
#             289MB + 344MB on a configured machine, and both are seeded into
#             /etc/skel by the ISO build (OSM_MAP_STATE / ET_MAP_REGION), so a
#             fresh install from your own ISO already has them. Including them
#             roughly doubles every backup to re-store bytes the installer just
#             wrote. Excluding them keeps the backup at ~704MB instead of
#             ~1337MB.
#
#             Trade-off: the backup is then only fully restorable onto an
#             install from an ISO carrying the same maps, not onto stock ETC.
#             Add BACKUP_EXTRA_ITEMS=".navit/maps my-maps" for a
#             self-contained archive, or if you hand-add custom map data.
#
#   wikipedia / ZIM files, map tilesets
#             Re-downloadable bulk content that the ISO already bakes in. A
#             single ZIM can be larger than everything else combined.

# Pull the BACKUP_DIRS array out of ETC's own et-user-backup.
#
# Parsed rather than duplicated so upstream's list stays authoritative. If the
# parse finds nothing the caller falls back to a known-good baseline instead of
# writing an empty manifest, which would back up nothing at all while looking
# like it worked.
_extract_etc_backup_dirs() {
    local script="$1"
    [ -f "$script" ] || return 1
    sed -n '/^BACKUP_DIRS=(/,/^)/p' "$script" \
        | grep -oE '"[^"]+"' \
        | tr -d '"'
}

customize_user_backup_manifest() {
    if [ "${ENABLE_MANIFEST_BACKUP:-yes}" != "yes" ]; then
        log "DEBUG" "ENABLE_MANIFEST_BACKUP=no -- leaving stock et-user-backup"
        return 0
    fi

    log "INFO" "Building manifest-driven et-user-backup..."

    local bin_dir skel manifest script
    bin_dir="$(etpath "${ET_PREFIX}/bin")"
    skel="$(etpath /etc/skel)"
    manifest="${skel}/BACKUP_ITEMS.lst"
    script="${bin_dir}/et-user-backup"

    # --- Assemble the manifest ------------------------------------------
    local -a items=()
    local line

    if [ -f "$script" ]; then
        while IFS= read -r line; do
            [ -n "$line" ] && items+=("$line")
        done < <(_extract_etc_backup_dirs "$script" || true)
    fi

    if [ "${#items[@]}" -eq 0 ]; then
        log "WARN" "Could not parse BACKUP_DIRS from ${script}"
        log "WARN" "  Falling back to the R7 baseline list. If ETC changed the"
        log "WARN" "  format, update _extract_etc_backup_dirs()."
        items=(
            ".config/emcomm-tools"
            ".config/partyline"
            ".local/share/JS8Call/ALL.TXT"
            ".local/share/JS8Call/DIRECTED.TXT"
            ".local/share/JS8Call/inbox.db3"
            ".local/share/emcomm-tools"
            ".local/share/pat"
            ".nomadnetwork"
            ".reticulum"
            ".reticulum-meshchat"
        )
    else
        log "SUCCESS" "Inherited ${#items[@]} paths from ETC's own et-user-backup"
    fi

    items+=("${ET_BACKUP_EXTRAS[@]}")

    # Operator additions from secrets.env, whitespace-separated.
    if [ -n "${BACKUP_EXTRA_ITEMS:-}" ]; then
        local extra
        for extra in ${BACKUP_EXTRA_ITEMS}; do
            items+=("$extra")
        done
        log "DEBUG" "Added operator extras from BACKUP_EXTRA_ITEMS"
    fi

    # The manifest lists itself, so a restored home keeps its own customizations.
    # Dedupe while preserving order; sort -u would scramble a list humans edit.
    local -a uniq=()
    local i seen
    for i in "BACKUP_ITEMS.lst" "${items[@]}"; do
        seen=0
        local u
        for u in "${uniq[@]:-}"; do [ "$u" = "$i" ] && { seen=1; break; }; done
        [ "$seen" -eq 0 ] && uniq+=("$i")
    done

    write_file "$manifest" 644 <<EOF
# BACKUP_ITEMS.lst -- what et-user-backup saves. Paths are relative to \$HOME.
#
# Generated by emcomm-tools-customizer. Edit freely; it is backed up with
# everything else, so your changes survive a restore.
#
# Paths above the marker came from ETC's own et-user-backup, so they track
# upstream. Paths below it are additions. A path that does not exist is
# skipped with a log line, never an error.
$(printf '%s\n' "${uniq[@]}")
EOF
    log "SUCCESS" "Wrote BACKUP_ITEMS.lst (${#uniq[@]} entries)"

    # --- Install the manifest-aware et-user-backup ----------------------
    # R7's logic, with the hardcoded array replaced by the manifest and the
    # existence filter kept.
    backup "$script"
    write_file "$script" 755 <<'BACKUPEOF'
#!/bin/bash
# Author  : Gaston Gonzalez
# Purpose : Back up select files from the user's home directory.
#
# Manifest-driven variant installed by emcomm-tools-customizer. Reads the list
# from ~/BACKUP_ITEMS.lst so paths can be added without editing this script.
# Falls back to the stock hardcoded list if the manifest is missing.
#
# Keeps ETC's existence filtering: tar is only ever handed paths that exist,
# so a missing directory produces a log line rather than a tar error.

TODAY=$(date +"%Y%m%d")
BACKUP_FILE="${HOME}/etc-user-backup-${HOSTNAME}-${TODAY}.tar.gz"
BACKUP_ITEMS_FILE="${HOME}/BACKUP_ITEMS.lst"

ESC="\033"
CYAN="$ESC[36m"
GREEN="$ESC[0;32m"
RED="$ESC[0;31m"
WHITE="$ESC[1;37m"
YELLOW="$ESC[1;33m"
NC="$ESC[0m"

if [ -e "${BACKUP_FILE}" ]; then
  echo -e -n "${RED}A backup file for today exists. Can ${WHITE}${BACKUP_FILE} ${RED}be overwritten? (y/n) ${NC}"
  read response
  [[ $response != [yY] ]] && echo "Skipping backup and exiting." && exit 1
fi

# All paths are relative to $HOME.
BACKUP_DIRS=()
if [ -r "${BACKUP_ITEMS_FILE}" ]; then
  while IFS= read -r line; do
    # Skip blanks and comments.
    [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue
    BACKUP_DIRS+=("${line}")
  done < "${BACKUP_ITEMS_FILE}"
fi

if [ ${#BACKUP_DIRS[@]} -eq 0 ]; then
  et-log "No usable ${BACKUP_ITEMS_FILE}; using the built-in list."
  BACKUP_DIRS=(
    ".config/emcomm-tools"
    ".config/partyline"
    ".local/share/JS8Call/ALL.TXT"
    ".local/share/JS8Call/DIRECTED.TXT"
    ".local/share/JS8Call/inbox.db3"
    ".local/share/emcomm-tools"
    ".local/share/pat"
    ".nomadnetwork"
    ".reticulum"
    ".reticulum-meshchat"
  )
fi

EXISTING_DIRS=()
for dir in "${BACKUP_DIRS[@]}"; do
  if [[ -e "${HOME}/${dir}" ]]; then
    EXISTING_DIRS+=("${dir}")
  else
    et-log "Skipping nonexistent directory or file: ${dir}"
  fi
done

if [ ${#EXISTING_DIRS[@]} -eq 0 ]; then
  et-log "Nothing to back up -- none of the listed paths exist."
  exit 1
fi

tar -czf ${BACKUP_FILE} \
   --transform 's|^.*\.local|.local|' \
   -C "${HOME}" "${EXISTING_DIRS[@]}"

[ $? -ne 0 ] && et-log "Error creating backup" && exit 1

# Test that we can read it after we create it.
TAR_OUT=$(tar -tzf ${BACKUP_FILE})
[ $? -ne 0 ] && et-log "Can't read backup file: ${BACKUP_FILE}. Error creating backup." && exit 1

echo -e "${GREEN}Backup created: ${WHITE}${BACKUP_FILE}\n"

# Iterate the SAME list tar was given. The et-os-addons fork looped over an
# unassigned BACKUP_DIRS here and printed an empty summary.
echo -e "${CYAN}Note: Only the following directories and files were backed up:"
for dir in "${EXISTING_DIRS[@]}"; do
  echo "* $dir"
done

echo -e "\nAdd paths to ${BACKUP_ITEMS_FILE} to include more.\n${NC}"

read -p  "Do you want see the full list of files backed up? (y/n) " response
[[ $response != [yY] ]] && exit 0

echo -e "1. ${YELLOW}Press ${WHITE}[SPACE]${YELLOW} to page through the list of files.${NC}"
echo -e "2. ${YELLOW}Press ${WHITE}[UP/DOWN]${YELLOW} to scroll through the list of files.${NC}"
echo -e "3. ${YELLOW}Press ${WHITE}q${YELLOW} when done viewing the list of files.\n${NC}"
read -p "Press any key to view the backup."

tar -tzf ${BACKUP_FILE} | less
BACKUPEOF
    log "SUCCESS" "Installed manifest-aware et-user-backup"

    return 0
}
