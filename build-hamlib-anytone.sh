#!/bin/bash
#
# Build and install CowboyPilot/Hamlib, which adds the AnyTone AT-D578UVIII
# backend (RIG_MODEL_ATD578UVIII = 37001). Stock Hamlib 4.5 as shipped with
# ETC v6 has no AnyTone backend at all, so model 37001 is rejected without this.
#
# Follows the fork's README build method exactly:
#   ./bootstrap && ./configure --prefix=/usr/local && make && make install
#
# IMPORTANT -- what this does to your existing install:
#   ETC does not use a packaged Hamlib. It builds Hamlib into /opt/hamlib and
#   symlinks ~24 entries from /usr/local/{bin,lib,include,share} into it.
#   Installing to --prefix=/usr/local REPLACES those symlinks with real files.
#   /opt/hamlib itself is left untouched, so this script records the symlink
#   manifest beforehand and --revert restores it.
#
#   /usr/local/lib precedes /usr/lib in the linker path, and direwolf, fldigi,
#   js8call and wsjtx all resolve libhamlib.so.4 through it. They will pick up
#   the new library. Same .so.4 soname, so this is normally fine -- but if a
#   hamlib app misbehaves afterwards, --revert is the first thing to try.
#
# Usage:
#   sudo ./build-hamlib-anytone.sh            # build + install
#   sudo ./build-hamlib-anytone.sh --revert   # restore ETC's original symlinks
#   sudo ./build-hamlib-anytone.sh --verify   # just check what's installed now

set -uo pipefail

REPO="https://github.com/CowboyPilot/Hamlib.git"
SRC="${SRC:-/usr/local/src/hamlib-anytone}"
PREFIX=/usr/local
MANIFEST=/opt/emcomm-tools/.customizer-backup/hamlib-symlinks.manifest
EXPECT_MODEL=37001

RED=$'\033[0;31m'; GRN=$'\033[0;32m'; YEL=$'\033[1;33m'; NC=$'\033[0m'
info() { echo "${GRN}[ OK ]${NC} $*"; }
warn() { echo "${YEL}[WARN]${NC} $*"; }
err()  { echo "${RED}[FAIL]${NC} $*" >&2; }
step() { echo; echo "=== $* ==="; }

verify() {
  step "Current Hamlib"
  echo "rigctl:  $(command -v rigctl)"
  rigctl --version 2>/dev/null | head -1
  echo "libhamlib resolves to: $(ldconfig -p | awk '/libhamlib.so.4/{print $NF; exit}')"
  echo
  if rigctl -l 2>/dev/null | grep -qi anytone; then
    info "AnyTone backend present:"
    rigctl -l 2>/dev/null | grep -i anytone | sed 's/^/       /'
  else
    warn "No AnyTone backend -- model ${EXPECT_MODEL} will be rejected."
  fi
}

case "${1:-}" in
  --verify) verify; exit 0 ;;
  --revert)
    [ "$(id -u)" -eq 0 ] || { err "Must run as root"; exit 1; }
    [ -f "$MANIFEST" ] || { err "No manifest at $MANIFEST -- nothing to revert"; exit 1; }
    step "Restoring ETC's original Hamlib symlinks"
    restored=0
    while IFS='|' read -r link target; do
      [ -n "$link" ] || continue
      rm -rf "$link"
      ln -s "$target" "$link" && { echo "  $link -> $target"; restored=$((restored+1)); }
    done < "$MANIFEST"
    ldconfig
    info "Restored $restored symlinks; ran ldconfig"
    verify
    exit 0 ;;
  "") : ;;
  -h|--help) sed -n '3,30p' "$0"; exit 0 ;;
  *) err "Unknown option: $1"; exit 1 ;;
esac

[ "$(id -u)" -eq 0 ] || { err "Must run as root: sudo $0"; exit 1; }

# ---------------------------------------------------------------------------
step "Preflight"
missing=""
for p in git build-essential automake autoconf libtool pkg-config libusb-1.0-0-dev; do
  dpkg -s "$p" >/dev/null 2>&1 || missing="$missing $p"
done
if [ -n "$missing" ]; then
  warn "Missing build deps:$missing"
  echo "Installing..."
  apt-get update -qq && apt-get install -y $missing || { err "apt install failed"; exit 1; }
fi
info "Build dependencies present"

echo "Before:"
rigctl --version 2>/dev/null | head -1 | sed 's/^/       /'

# ---------------------------------------------------------------------------
step "Recording ETC's existing Hamlib symlink manifest"
mkdir -p "$(dirname "$MANIFEST")"
if [ -f "$MANIFEST" ]; then
  info "Manifest already exists (from an earlier run) -- keeping the original"
  echo "       $(wc -l < "$MANIFEST") entries at $MANIFEST"
else
  : > "$MANIFEST"
  # Capture every /usr/local symlink that points into /opt/hamlib
  find /usr/local -maxdepth 3 -type l 2>/dev/null | while read -r l; do
    t=$(readlink "$l")
    case "$(readlink -f "$l")" in
      /opt/hamlib/*) printf '%s|%s\n' "$l" "$t" >> "$MANIFEST" ;;
    esac
  done
  info "Recorded $(wc -l < "$MANIFEST") symlinks -> $MANIFEST"
  echo "       Revert any time with: sudo $0 --revert"
fi

# ---------------------------------------------------------------------------
step "Fetching source"
if [ -d "${SRC}/.git" ]; then
  echo "Updating existing clone at $SRC"
  git -C "$SRC" pull --ff-only || { err "git pull failed"; exit 1; }
else
  mkdir -p "$(dirname "$SRC")"
  git clone "$REPO" "$SRC" || { err "git clone failed (network?)"; exit 1; }
fi
cd "$SRC" || exit 1
info "Source at $SRC ($(git rev-parse --short HEAD), branch $(git rev-parse --abbrev-ref HEAD))"

# Sanity-check the backend is actually in this tree before spending a build on it
if [ ! -f rigs/anytone/d578.c ]; then
  err "rigs/anytone/d578.c not found -- wrong repo or branch?"
  exit 1
fi
info "AnyTone backend source present (rigs/anytone/)"

# ---------------------------------------------------------------------------
step "Building (README method: --prefix=${PREFIX})"
./bootstrap                    || { err "bootstrap failed"; exit 1; }
./configure --prefix="$PREFIX" || { err "configure failed"; exit 1; }
make -j"$(nproc)"              || { err "make failed"; exit 1; }
info "Build complete"

step "Installing"
make install || { err "make install failed"; exit 1; }
ldconfig
info "Installed to $PREFIX and ran ldconfig"

# ---------------------------------------------------------------------------
step "Verification"
verify

if rigctl -l 2>/dev/null | awk -v m="$EXPECT_MODEL" '$1==m{f=1} END{exit !f}'; then
  info "Model ${EXPECT_MODEL} is available -- ETC radio profiles will work"
  echo
  echo "Next: sudo ./apply-to-live-system.sh --no-aprs --no-addons"
  echo "      (writes the two D578UV profiles and sets the active radio)"
else
  err "Model ${EXPECT_MODEL} NOT found after install."
  err "Revert with: sudo $0 --revert"
  exit 1
fi
