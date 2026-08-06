#!/bin/bash
#
# Rebuild Dire Wolf with GPSD support (ENABLE_GPSD), enabling GPS-tracked APRS
# beaconing (the GPSD + TBEACON directives) instead of a fixed PBEACON position.
#
# WHY THIS IS NEEDED
#   ETC v6 ships a Dire Wolf built WITHOUT gpsd. Check for yourself:
#       direwolf | grep 'optional support'
#   A stock v6 build reports only "hamlib cm108-ptt". With no gpsd support the
#   GPSD directive is a hard config error and direwolf refuses to start, so
#   lib/customize-aprs.sh deliberately falls back to a fixed beacon.
#
# WHAT IT DOES
#   Installs gpsd/libgps-dev, builds Dire Wolf from source into its own prefix
#   (/opt/direwolf-<ver>-gpsd), and points /usr/local/bin/direwolf at it. The
#   existing build is left completely untouched, so --revert is instant.
#
# Usage:
#   sudo ./build-direwolf-gpsd.sh            # build + install + switch
#   sudo ./build-direwolf-gpsd.sh --revert   # switch back to the stock build
#   ./build-direwolf-gpsd.sh --verify        # report what's active now

set -uo pipefail

DW_VERSION="${DW_VERSION:-1.7}"
REPO="https://github.com/wb2osz/direwolf.git"
SRC="${SRC:-/usr/local/src/direwolf-gpsd}"
PREFIX="/opt/direwolf-${DW_VERSION}-gpsd"
STATE=/opt/emcomm-tools/.customizer-backup/direwolf-original

RED=$'\033[0;31m'; GRN=$'\033[0;32m'; YEL=$'\033[1;33m'; NC=$'\033[0m'
info() { echo "${GRN}[ OK ]${NC} $*"; }
warn() { echo "${YEL}[WARN]${NC} $*"; }
err()  { echo "${RED}[FAIL]${NC} $*" >&2; }
step() { echo; echo "=== $* ==="; }

verify() {
  step "Active Dire Wolf"
  local dw; dw=$(command -v direwolf)
  echo "  path    : ${dw:-<not found>}"
  [ -n "$dw" ] && echo "  real    : $(readlink -f "$dw")"
  # direwolf with no args prints usage and exits non-zero; under pipefail a
  # `direwolf | grep` pipeline would report failure even on a match. Capture
  # once, then grep the captured text.
  local out caps ver
  out=$(direwolf 2>&1 </dev/null || true)
  ver=$(printf '%s' "$out" | grep -m1 -i 'Dire Wolf version')
  caps=$(printf '%s' "$out" | grep -m1 -i 'optional support for')
  echo "  version : ${ver:-<unknown>}"
  echo "  caps    : ${caps:-<none reported>}"
  echo
  if echo "$caps" | grep -qi gpsd; then
    info "GPSD support present -- GPSD/TBEACON directives will work"
  else
    warn "No GPSD support -- GPSD/TBEACON would be a config error"
  fi
  echo
  echo "  gpsd service : $(systemctl is-active gpsd 2>/dev/null)"
  if [ -e /dev/et-gps ]; then
    echo "  /dev/et-gps  : present -> $(readlink -f /dev/et-gps)"
  else
    echo "  /dev/et-gps  : absent (plug in a supported USB GPS; see 92-et-u-blox.rules)"
  fi
}

case "${1:-}" in
  --verify) verify; exit 0 ;;
  --revert)
    [ "$(id -u)" -eq 0 ] || { err "Must run as root"; exit 1; }
    [ -f "$STATE" ] || { err "No saved original at $STATE -- nothing to revert"; exit 1; }
    step "Reverting to the original Dire Wolf"
    orig=$(cat "$STATE")
    [ -e "$orig" ] || { err "Original binary missing: $orig"; exit 1; }
    ln -sfn "$orig" /usr/local/bin/direwolf
    info "/usr/local/bin/direwolf -> $orig"
    warn "Your APRS template may still contain GPSD/TBEACON. If direwolf now"
    warn "refuses to start, re-run: sudo ./apply-to-live-system.sh --no-radio --no-addons"
    verify
    exit 0 ;;
  "") : ;;
  -h|--help) sed -n '3,20p' "$0"; exit 0 ;;
  *) err "Unknown option: $1"; exit 1 ;;
esac

[ "$(id -u)" -eq 0 ] || { err "Must run as root: sudo $0"; exit 1; }

# ---------------------------------------------------------------------------
step "Preflight"
current=$(command -v direwolf) || { err "direwolf not found -- is this an ETC system?"; exit 1; }
current_real=$(readlink -f "$current")
info "Current direwolf: $current_real"

if direwolf 2>&1 </dev/null | grep -qi 'optional support for.*gpsd'; then
  info "This Dire Wolf ALREADY has GPSD support -- nothing to do."
  verify
  exit 0
fi

step "Installing build dependencies"
apt-get update -qq || warn "apt-get update failed -- continuing with cached lists"
apt-get install -y git build-essential cmake gpsd libgps-dev \
    libasound2-dev libudev-dev pkg-config libhamlib-dev 2>/dev/null \
  || apt-get install -y git build-essential cmake gpsd libgps-dev \
       libasound2-dev libudev-dev pkg-config \
  || { err "Failed to install build dependencies"; exit 1; }
info "Build dependencies installed"

# ---------------------------------------------------------------------------
step "Fetching Dire Wolf ${DW_VERSION} source"
if [ -d "${SRC}/.git" ]; then
  git -C "$SRC" fetch --all --tags -q || warn "fetch failed -- using existing checkout"
else
  mkdir -p "$(dirname "$SRC")"
  git clone -q "$REPO" "$SRC" || { err "git clone failed (network?)"; exit 1; }
fi
cd "$SRC" || exit 1
git checkout -q "$DW_VERSION" 2>/dev/null || warn "Tag ${DW_VERSION} not found -- building the default branch"
info "Source at $SRC ($(git describe --tags --always 2>/dev/null))"

# ---------------------------------------------------------------------------
step "Building with ENABLE_GPSD into ${PREFIX}"
rm -rf build && mkdir -p build && cd build || exit 1

cmake .. -DCMAKE_INSTALL_PREFIX="$PREFIX" -DENABLE_GPSD=1 \
  || { err "cmake failed"; exit 1; }

# Confirm cmake actually found libgps before spending a full build on it.
if ! grep -qiE 'gpsd|libgps' CMakeCache.txt 2>/dev/null; then
  warn "cmake cache shows no gpsd reference -- libgps-dev may not be detected"
fi

make -j"$(nproc)" || { err "make failed"; exit 1; }
make install      || { err "make install failed"; exit 1; }
info "Installed to $PREFIX"

# ---------------------------------------------------------------------------
step "Switching /usr/local/bin/direwolf"
NEW="${PREFIX}/bin/direwolf"
[ -x "$NEW" ] || { err "Built binary not found at $NEW"; exit 1; }

if "$NEW" 2>&1 </dev/null | grep -qi 'optional support for.*gpsd'; then
  info "New build reports GPSD support"
else
  err "New build does NOT report GPSD support -- refusing to switch."
  err "libgps-dev was probably not picked up. Not changing anything."
  exit 1
fi

# Record the original exactly once so --revert always finds the stock build.
mkdir -p "$(dirname "$STATE")"
[ -f "$STATE" ] || { printf '%s\n' "$current_real" > "$STATE"; info "Recorded original: $current_real"; }

ln -sfn "$NEW" /usr/local/bin/direwolf
info "/usr/local/bin/direwolf -> $NEW"

# ---------------------------------------------------------------------------
verify

echo
echo "Next: enable GPS beaconing by setting APRS_BEACON_MODE=\"gps\" in secrets.env,"
echo "      then: sudo ./apply-to-live-system.sh --no-radio --no-addons"
echo "Revert at any time with: sudo $0 --revert"
