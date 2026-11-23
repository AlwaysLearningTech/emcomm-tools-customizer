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

# Fallback Hamlib headers, used only when the system ones are Hamlib 5 (where
# hamlib_port_t is opaque and no Dire Wolf release will compile). Staged
# privately; nothing installed on the system is modified.
HAMLIB_45_VER="${HAMLIB_45_VER:-4.5}"
HAMLIB_45_URL="https://github.com/Hamlib/Hamlib/releases/download/${HAMLIB_45_VER}/hamlib-${HAMLIB_45_VER}.tar.gz"
HDR_STAGE="${HDR_STAGE:-/usr/local/src/hamlib-${HAMLIB_45_VER}-headers}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"   # for check_eol_apt_sources()

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
  # Herestrings, not pipes: grep -m1 exits early and can SIGPIPE the writer,
  # which pipefail would then report as failure. See lib/common.sh.
  ver=$(grep -m1 -i 'Dire Wolf version' <<< "$out")
  caps=$(grep -m1 -i 'optional support for' <<< "$out")
  echo "  version : ${ver:-<unknown>}"
  echo "  caps    : ${caps:-<none reported>}"
  echo
  if grep -qi gpsd <<< "$caps"; then
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

if direwolf_has_gpsd; then
  info "This Dire Wolf ALREADY has GPSD support -- nothing to do."
  verify
  exit 0
fi

step "Installing build dependencies"

# libgps-dev must match the installed libgps runtime, or direwolf will build
# against headers that do not correspond to the library it loads.
if [ -f /usr/include/gps.h ]; then
    info "libgps headers already present"
else
    if ! apt-get update -qq 2>/dev/null; then
        warn "apt-get update failed"
        check_eol_apt_sources || exit 1
        warn "Continuing with cached package lists"
    fi

    if ! apt-cache show libgps-dev >/dev/null 2>&1; then
        err "libgps-dev is not available from any configured repository."
        check_eol_apt_sources || exit 1
        err "Cannot continue without libgps-dev."
        exit 1
    fi

    apt-get install -y git build-essential cmake gpsd libgps-dev \
        libasound2-dev libudev-dev pkg-config \
      || { err "Failed to install build dependencies"; exit 1; }
fi

# Everything else is usually already present on ETC; install quietly if not.
apt-get install -y git build-essential cmake libasound2-dev libudev-dev pkg-config \
    >/dev/null 2>&1 || warn "Some optional build tools could not be installed"

if [ ! -f /usr/include/gps.h ]; then
    err "gps.h still missing after install -- cmake will not enable GPSD."
    exit 1
fi

local_gps=$(dpkg -s libgps-dev 2>/dev/null | awk '/^Version:/{print $2}')
runtime_gps=$(dpkg -s libgps28 2>/dev/null | awk '/^Version:/{print $2}')
if [ -n "$local_gps" ] && [ -n "$runtime_gps" ] && [ "$local_gps" != "$runtime_gps" ]; then
    warn "libgps-dev ($local_gps) differs from the runtime libgps28 ($runtime_gps)"
fi
info "Build dependencies installed (libgps-dev ${local_gps:-present})"

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
# Dire Wolf vs Hamlib 5 headers
#
# src/ptt.c declares `hamlib_port_t hport;` on the stack. In Hamlib 4.x that is
# a complete type; Hamlib 5 made it OPAQUE (`typedef struct hamlib_port
# hamlib_port_t;` with no struct body), so the build dies with:
#     error: storage size of 'hport' isn't known
# Every Dire Wolf release -- 1.7, 1.8, dev, master -- still declares it this
# way, so there is no newer Dire Wolf that fixes this. The only option is to
# compile against Hamlib 4.x headers.
#
# This matters here because build-hamlib-anytone.sh installs the CowboyPilot
# fork (Hamlib 5) to /usr/local, and /usr/local/include/hamlib is a SYMLINK into
# /opt/hamlib -- so that install replaces ETC's Hamlib 4.5 headers in place.
# The 4.0.5 runtime library survives (different soname), which is what we link.
step "Checking Hamlib headers"

hamlib_headers_usable() {
    local inc="$1" t rc
    t=$(mktemp --suffix=.c) || return 1
    printf '#include <hamlib/rig.h>\nint main(void){hamlib_port_t h;(void)h;return 0;}\n' > "$t"
    gcc -c "$t" -I "$inc" -o /dev/null 2>/dev/null
    rc=$?
    rm -f "$t"
    return $rc
}

HAMLIB_INC=""
HAMLIB_LIB=""

if hamlib_headers_usable /usr/local/include; then
    info "System Hamlib headers are compatible with Dire Wolf"
else
    warn "Hamlib headers at /usr/local/include are INCOMPATIBLE with Dire Wolf"
    warn "(hamlib_port_t is opaque -- this is Hamlib 5)"

    # Stage a private copy of the 4.5 headers. Nothing on the system is touched.
    if ! hamlib_headers_usable "${HDR_STAGE}/include"; then
        info "Staging Hamlib ${HAMLIB_45_VER} headers into ${HDR_STAGE}"
        rm -rf "$HDR_STAGE"; mkdir -p "$HDR_STAGE"
        tmp=$(mktemp -d)
        if ! curl -sL --max-time 300 -o "${tmp}/hl.tar.gz" "$HAMLIB_45_URL"; then
            err "Could not download Hamlib ${HAMLIB_45_VER} headers"; rm -rf "$tmp"; exit 1
        fi
        tar xzf "${tmp}/hl.tar.gz" -C "$tmp" --strip-components=1 || {
            err "Could not unpack Hamlib source"; rm -rf "$tmp"; exit 1; }
        mkdir -p "${HDR_STAGE}/include"
        cp -a "${tmp}/include/hamlib" "${HDR_STAGE}/include/" || {
            err "Could not stage headers"; rm -rf "$tmp"; exit 1; }
        rm -rf "$tmp"
    fi

    hamlib_headers_usable "${HDR_STAGE}/include" || {
        err "Staged headers still do not compile -- aborting"; exit 1; }
    info "Using Hamlib ${HAMLIB_45_VER} headers from ${HDR_STAGE}/include"
    HAMLIB_INC="${HDR_STAGE}/include"

    # Link against ETC's original 4.0.5 library (soname libhamlib.so.4), which
    # is what the rest of ETC uses. NOT /usr/local/lib/libhamlib.so, which now
    # resolves to the fork's .so.5.
    for cand in /opt/hamlib/lib/libhamlib.so /usr/local/lib/libhamlib.so.4; do
        if [ -e "$cand" ]; then HAMLIB_LIB="$cand"; break; fi
    done
    [ -n "$HAMLIB_LIB" ] || { err "No Hamlib 4.x library found to link against"; exit 1; }
    info "Linking against $HAMLIB_LIB -> $(readlink -f "$HAMLIB_LIB" | xargs basename)"
fi

step "Building with ENABLE_GPSD into ${PREFIX}"
rm -rf build && mkdir -p build && cd build || exit 1

# HAMLIB_INCLUDE_DIR / HAMLIB_LIBRARY are the cache variables Findhamlib.cmake
# populates; setting them explicitly bypasses its search entirely.
cmake .. -DCMAKE_INSTALL_PREFIX="$PREFIX" -DENABLE_GPSD=1 \
  ${HAMLIB_INC:+-DHAMLIB_INCLUDE_DIR="$HAMLIB_INC"} \
  ${HAMLIB_LIB:+-DHAMLIB_LIBRARY="$HAMLIB_LIB"} \
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

# binary_has_gpsd(), not an inline pipeline: direwolf exits non-zero after
# printing its banner, so under `set -o pipefail` a `"$NEW" | grep -q` test
# reports failure even on a match -- which would reject a perfectly good build.
if binary_has_gpsd "$NEW"; then
  info "New build reports GPSD support"
else
  err "New build does NOT report GPSD support -- refusing to switch."
  err "libgps-dev was probably not picked up. Not changing anything."
  exit 1
fi

# The rest of ETC uses libhamlib.so.4. If this binary picked up the fork's
# .so.5 instead, say so -- it will still run, but it is not the same library
# stack as the Dire Wolf it replaces.
NEW_HAMLIB=$(ldd "$NEW" 2>/dev/null | grep -o 'libhamlib\.so\.[0-9]*' | head -1)
case "$NEW_HAMLIB" in
  libhamlib.so.4) info "Links $NEW_HAMLIB (same as ETC's stock Dire Wolf)" ;;
  "")             warn "Links no libhamlib -- 'PTT RIG' will not work" ;;
  *)              warn "Links $NEW_HAMLIB, but the rest of ETC uses libhamlib.so.4" ;;
esac
NEW_GPS=$(ldd "$NEW" 2>/dev/null | grep -o 'libgps\.so\.[0-9]*' | head -1)
info "Links ${NEW_GPS:-<no libgps>}"

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
