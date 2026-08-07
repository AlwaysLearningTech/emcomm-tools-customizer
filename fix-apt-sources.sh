#!/bin/bash
#
# Repoint apt at old-releases.ubuntu.com for an end-of-life Ubuntu release.
#
# WHY
#   ETC v6 is built on Ubuntu 22.10 "kinetic", which reached end of life in
#   July 2023. Its packages were removed from archive.ubuntu.com and
#   security.ubuntu.com and moved to old-releases.ubuntu.com. Until you repoint
#   apt, every `apt-get update` reports
#       The repository '... kinetic Release' does not have a Release file
#   and every install fails with "Unable to locate package <anything>".
#
#   This blocks build-direwolf-gpsd.sh (needs libgps-dev), CHIRP, and anything
#   else you try to install.
#
# WHAT IT TOUCHES
#   /etc/apt/sources.list only. Files in /etc/apt/sources.list.d/ are left
#   alone -- third-party repos (Brave, VS Code, the Cubic PPA) are still live
#   and must not be redirected. No packages are installed or removed; this only
#   rewrites URLs and refreshes the package lists.
#
# Usage:
#   sudo ./fix-apt-sources.sh              # back up, rewrite, apt-get update
#   sudo ./fix-apt-sources.sh --dry-run    # show the diff, change nothing
#   sudo ./fix-apt-sources.sh --revert     # restore the most recent backup
#   ./fix-apt-sources.sh --check           # report status only (no root needed)

set -uo pipefail

SOURCES=/etc/apt/sources.list
BACKUP_DIR=/opt/emcomm-tools/.customizer-backup/apt
OLD_HOST="http://old-releases.ubuntu.com"

RED=$'\033[0;31m'; GRN=$'\033[0;32m'; YEL=$'\033[1;33m'; NC=$'\033[0m'
info() { echo "${GRN}[ OK ]${NC} $*"; }
warn() { echo "${YEL}[WARN]${NC} $*"; }
err()  { echo "${RED}[FAIL]${NC} $*" >&2; }
step() { echo; echo "=== $* ==="; }

# Rewrite Ubuntu archive/security hosts to old-releases. Handles country
# mirrors (us.archive, gb.archive, ...) and both http and https.
rewrite() {
    sed -E \
        -e 's|https?://([a-z]{2,3}\.)?archive\.ubuntu\.com|'"$OLD_HOST"'|g' \
        -e 's|https?://security\.ubuntu\.com|'"$OLD_HOST"'|g' \
        -e 's|https?://ports\.ubuntu\.com|'"$OLD_HOST"'|g' \
        "$1"
}

codename() { lsb_release -cs 2>/dev/null || echo unknown; }

is_eol() {
    case "$(codename)" in
        warty|hoary|breezy|dapper|edgy|feisty|gutsy|hardy|intrepid|jaunty|karmic|\
        lucid|maverick|natty|oneiric|precise|quantal|raring|saucy|trusty|utopic|\
        vivid|wily|xenial|yakkety|zesty|artful|bionic|cosmic|disco|eoan|focal|\
        groovy|hirsute|impish|kinetic|lunar|mantic) return 0 ;;
        *) return 1 ;;
    esac
}

do_check() {
    step "Status"
    echo "  Release : $(codename) $(is_eol && echo '(END OF LIFE)' || echo '(supported)')"
    echo "  Sources : $SOURCES"
    local stale
    stale=$(grep -cE '^[[:space:]]*deb .*(archive|security|ports)\.ubuntu\.com' "$SOURCES" 2>/dev/null)
    local fixed
    fixed=$(grep -cE '^[[:space:]]*deb .*old-releases\.ubuntu\.com' "$SOURCES" 2>/dev/null)
    echo "  Lines pointing at live mirrors  : ${stale:-0}"
    echo "  Lines pointing at old-releases  : ${fixed:-0}"
    echo
    if [ "${stale:-0}" -gt 0 ] && is_eol; then
        warn "This release is EOL but still points at the live mirrors."
        warn "apt cannot find packages. Run: sudo $0"
        return 1
    fi
    if [ "${fixed:-0}" -gt 0 ]; then
        info "Sources already point at old-releases.ubuntu.com"
    fi
    # Is the package we actually need visible?
    if apt-cache show libgps-dev >/dev/null 2>&1; then
        info "libgps-dev is visible to apt ($(apt-cache policy libgps-dev 2>/dev/null | awk '/Candidate:/{print $2}'))"
    else
        warn "libgps-dev is NOT visible to apt (needed by build-direwolf-gpsd.sh)"
        return 1
    fi
    return 0
}

case "${1:-}" in
    --check) do_check; exit $? ;;
    --dry-run) DRY=1 ;;
    --revert) REVERT=1 ;;
    -h|--help) sed -n '3,27p' "$0"; exit 0 ;;
    "") : ;;
    *) err "Unknown option: $1"; exit 1 ;;
esac
DRY="${DRY:-0}"; REVERT="${REVERT:-0}"

[ "$(id -u)" -eq 0 ] || { err "Must run as root: sudo $0"; exit 1; }

# ---------------------------------------------------------------------------
if [ "$REVERT" -eq 1 ]; then
    step "Reverting $SOURCES"
    latest=$(find "$BACKUP_DIR" -maxdepth 1 -name 'sources.list.*' -type f 2>/dev/null | sort | tail -1)
    [ -n "$latest" ] || { err "No backup found in $BACKUP_DIR"; exit 1; }
    cp -a "$latest" "$SOURCES" || { err "Restore failed"; exit 1; }
    info "Restored from $latest"
    apt-get update -qq 2>/dev/null || warn "apt-get update reported errors (expected if the release is EOL)"
    exit 0
fi

# ---------------------------------------------------------------------------
step "Preflight"
[ -f "$SOURCES" ] || { err "$SOURCES not found"; exit 1; }
echo "  Release: $(codename)"

if ! is_eol; then
    warn "$(codename) is not a known end-of-life release."
    warn "Repointing a supported release at old-releases would BREAK updates."
    err  "Refusing to modify $SOURCES."
    exit 1
fi
info "$(codename) is end-of-life -- old-releases.ubuntu.com is the correct host"

if ! grep -qE '^[[:space:]]*deb .*(archive|security|ports)\.ubuntu\.com' "$SOURCES"; then
    info "No live-mirror entries left in $SOURCES -- nothing to do"
    do_check
    exit 0
fi

# ---------------------------------------------------------------------------
step "Proposed change"
TMP=$(mktemp)
rewrite "$SOURCES" > "$TMP"

if diff -u "$SOURCES" "$TMP" > /dev/null 2>&1; then
    info "No change needed"
    rm -f "$TMP"; exit 0
fi
diff -u "$SOURCES" "$TMP" | sed 's/^/  /'

if [ "$DRY" -eq 1 ]; then
    echo
    warn "Dry run -- nothing written."
    rm -f "$TMP"; exit 0
fi

# Sanity-check the rewrite before installing it: same number of deb lines in,
# same number out. Guards against a bad regex silently dropping repositories.
in_n=$(grep -cE '^[[:space:]]*deb ' "$SOURCES")
out_n=$(grep -cE '^[[:space:]]*deb ' "$TMP")
if [ "$in_n" -ne "$out_n" ]; then
    err "Rewrite changed the number of deb lines ($in_n -> $out_n). Aborting."
    rm -f "$TMP"; exit 1
fi
info "deb line count preserved ($in_n)"

# ---------------------------------------------------------------------------
step "Applying"
mkdir -p "$BACKUP_DIR"
STAMP=$(date +%Y%m%d-%H%M%S)
cp -a "$SOURCES" "${BACKUP_DIR}/sources.list.${STAMP}"
cp -a "$SOURCES" "${SOURCES}.bak"
info "Backed up to ${BACKUP_DIR}/sources.list.${STAMP} (and ${SOURCES}.bak)"

cat "$TMP" > "$SOURCES"
rm -f "$TMP"
info "Rewrote $SOURCES"

step "Refreshing package lists"
if apt-get update 2>&1 | tail -15; then
    info "apt-get update completed"
else
    warn "apt-get update reported errors -- review the output above"
fi

# ---------------------------------------------------------------------------
step "Verification"
if do_check; then
    echo
    info "apt is working again."
    echo
    echo "Next: sudo ./build-direwolf-gpsd.sh"
else
    echo
    err "Something is still wrong -- see above."
    err "Revert with: sudo $0 --revert"
    exit 1
fi
