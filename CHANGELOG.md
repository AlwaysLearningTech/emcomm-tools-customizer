# Changelog

## 7.0.2-2 (ETC R7) — Backups that actually restore; scripts ship in the ISO

### Fixed — `post-install.sh --restore` never found the staged backups

The build staged both full archives in `/etc/skel/.etc-backups`, so they landed
in `~/.etc-backups/` on the installed system. `post-install.sh` searched only
`$HOME` (depth 1) and the repo's `cache/`, so every install reported
"No backup archives found". Archives are now staged once at
`/opt/emcomm-customizer-cache/backups/`, and `post-install.sh` searches that,
`$HOME`, `~/.etc-backups/` (for ISOs built before this release) and `cache/`.

### Fixed — the Wine backup was in the image twice

`restore_user_backup()` copied it into skel and `embed_cache_files()` copied it
again into `/opt/emcomm-customizer-cache`. On the installed system the skel
copy was then duplicated into every new home directory. It is now staged once.
The first-login `restore-wine.sh` was never called by anything and is removed;
the Wine restore stays manual, because it overwrites `~/.wine32` and VARA.

### Fixed — `post-install.sh` built a second CHIRP

The ISO installs CHIRP in `/opt/chirp-venv`; `install_chirp` only recognised
the per-user venv, warned about "a chirp not from this script" and built
another one. It now recognises the system install.

### Added

- The repo's tracked files are embedded at `/opt/emcomm-tools-customizer`
  (`git ls-files` only, so `secrets.env` cannot be included), so the installed
  system needs no clone to run `post-install.sh`.
- `post-install.sh`: "Everything" menu option and `--everything`, which include
  the Wine restore; `--vscode` sets `password-store` in `~/.vscode/argv.json`
  for VS Code's "OS keyring couldn't be identified" warning.
- Verification reports VS Code, gh, CHIRP, gnome-keyring, the embedded cache
  and staged backups, and warns on two WiFi profiles for one SSID.
- Build verification warns when gh, the embedded scripts or the staged backups
  are missing.

## 7.0.2-1 (ETC R7) — Target ETC R7; fix the applications that were never installed

Retargets the build at **EmComm Tools Community R7 (7.0.2)** and fixes a set of
customizations that reported success on every build while doing nothing at all.
`-r stable` now resolves to R7; Ubuntu 22.10 remains the base.

### Fixed — AnyTone CAT control was absent from every ISO

`lib/customize-radio.sh` writes D578UVIII profiles pinned to Hamlib model
**37001** (`RIG_MODEL_ATD578UVIII`). Stock Hamlib 4.5, which ETC ships, has no
AnyTone backend at all — and `build-etc-iso.sh` never called
`build-hamlib-anytone.sh`. There was not a single reference to it in the build.

So every ISO produced by this project booted with correct-looking radio
profiles, a `rigctld` that rejected model 37001 outright, and therefore **no CAT
control and no PTT**. The live system worked only if you had run
`build-hamlib-anytone.sh` by hand.

`install_hamlib_anytone()` now runs that same script inside the chroot — not a
reimplementation, so the ISO and the live system get identical treatment,
including the symlink manifest that `--revert` depends on. It then independently
confirms `rigctl -l` reports an AnyTone model, and fails the build if not.

### Fixed — VS Code was never installed

`customize_additional_packages()` ran `apt-get install -y -qq code`. Ubuntu
22.10 has no `code` package, and the same function deletes the Microsoft apt
repos 25 lines earlier, so this could never succeed. The failure was absorbed
by a `|| log WARN`. `setup_vscode_workspace()` then wrote a `.code-workspace`
for an editor that was not present.

VS Code now installs from a `.deb` (`VSCODE_DEB`, or downloaded), and a failure
fails the build.

### Fixed — CHIRP was never installed, on any of three paths

All three install paths used the name `chirp` from PyPI, which belongs to an
unrelated 2013 package for analyzing **bioacoustic recordings**:

- `python3 -m pip install chirp` in the first-boot script
- `pipx install chirp` in `post-install.sh`, falling back to `pip3 install --user chirp`
- `apt-get install chirp` in the `profile.d` fallback — real, but CHIRP 20200227

Anyone who ran these ended up with a working `chirp` command that cannot
program a radio. CHIRP now builds from `github.com/kk7ds/chirp` into a venv with
`--system-site-packages` (the distro `python3-wxgtk4.0` must be visible).
`archive.chirpmyradio.com` is not usable from a script — it serves HTTP 403 to
every non-browser request.

### Fixed — three dconf keys that do not exist

dconf compiles a keyfile containing an unknown key or a mistyped value and
**silently drops it**, so these looked exactly like success:

| Written | Reality |
| --- | --- |
| `power-profile-daemon` | Not a dconf key. The power profile is owned by power-profiles-daemon over D-Bus. `POWER_MODE` never did anything and has been removed. |
| `.../power/battery-saver` → `enable-battery-saver` | No such schema path. The real key is `power-saver-profile-on-low-battery`. |
| `org/gnome/desktop/session` → `auto-save-session-timeout` | No such key. The idle key there is `idle-delay`, a uint32. |

Also fixed in the same area:

- `sleep-display-ac` / `sleep-display-battery` were written **quoted**. They are
  integer keys, so screen blanking was never configured.
- The accessibility block re-declared `text-scaling-factor=1.0`, silently
  overriding `DESKTOP_SCALING_FACTOR` for anyone who changed it.
- `DISABLE_ACCESSIBILITY=yes` set `always-show-universal-access-status=true`,
  pinning the accessibility menu into the top bar — the opposite of the intent.
- `yes`/`no` from `secrets.env` are now normalized to dconf's `true`/`false`
  via `dconf_bool()`, and numbers to doubles via `dconf_double()`.

### Removed — all power and battery management

`customize_power()` and `customize_timezone()` were both dead code: neither was
ever called from `main()`, so every `POWER_*` setting and `TIMEZONE` in
`secrets.env` was silently ignored.

`customize_timezone()` is now wired in and works. Power management is **gone
entirely** rather than fixed — the function, the `POWER_*` and
`AUTOMATIC_SUSPEND` / `AUTOMATIC_POWER_SAVER` settings, and a
`customize_upower()` that briefly implemented battery-percentage actions. Three
of the keys the old code wrote did not exist (see above), so nothing it claimed
to configure had ever taken effect on any build.

**Consequence worth knowing:** the image now inherits GNOME and UPower's stock
behaviour, which on battery means suspend-on-idle. If a laptop running a net
must stay awake, set it on the installed system — `gnome-control-center power`,
or `powerprofilesctl set performance` — rather than in `secrets.env`.

### Fixed — verification checked for things the build deliberately no longer does

`verify_customizations()` tested for a `wrapper-rigctld.sh` "Anytone
preservation" patch, a `99-install-chirp-edge.sh` profile script, and a
`99-emcomm-tools-cat.rules` udev rule. All three were removed on purpose in
v2.0.0 (the first guarded a function that is never called; the last let an
unrelated USB serial device steal `/dev/et-cat`). They failed on every run,
which trained the reader to ignore the whole section.

Verification now covers what the build actually produces — including the
AnyTone backend, VS Code, CHIRP and the active-radio symlink being *relative* —
and **aborts before** the 20–40 minute squashfs step instead of printing
"Build will continue but ISO may not work correctly".

### Changed — ETC R7 redundancies removed

- `install_kiwix()` **removed**. Kiwix has been native since R4; installing
  `kiwix-tools` over the top risked a version ETC's own integration does not
  expect. `setup_wikipedia_tools()` is unaffected — it builds small targeted
  ZIM files, which is a different thing.
- Screen dimming, blanking and automatic brightness are now hardcoded **off**,
  matching R7. The old `DIM_SCREEN` default of `true` was re-enabling, on every
  build, the dimming R7 had just turned off. These are no longer settings — see
  "`secrets.env` holds only real decisions" below.
- `ENABLE_ETOSADDONS_KIWIX` is **on**. It was briefly set to `no` during this
  release on the mistaken belief that it duplicated ETC's kiwix; it replaces a
  broken one. See "et-os-addons was never actually installing anything".
- The hardcoded package list is documented with what **not** to add: R7 ships
  Thunderbird, VLC, Python 3.11.17 and Rust natively.

The R5 release tag hardcoded in the generated `download-et-maps.sh` is
**correct and intentional** — R7 ships no release assets, so the offline map
tilesets still live on the R5 release.

### Removed — Microsoft Edge, and the duplicate first-boot machinery

Edge was never a requirement, ETC ships the Min browser, and it was installed
by two competing code paths, one of them using `apt-key` (deprecated and
removed). Both are gone.

First-boot work had collapsed into three overlapping mechanisms: two systemd
units (`emcomm-first-boot.service`, `emcomm-first-boot-apps.service`) and an
`/etc/profile.d/99-install-chirp-edge.sh` written twice — once at build time,
then overwritten at runtime by one of the services. They raced and duplicated
each other. Now that applications install at build time, one small idempotent
service remains, re-asserting the active-radio symlink only if it is missing.

### Added — AnyTone AT-D890UV Bluetooth KISS TNC

New `lib/customize-anytone-dmr.sh` writes an `anytone-d890.bt.json` profile and
an `et-anytone-d890` helper (`pair` / `connect` / `unpair`), following ETC's own
`et-uv-pro` pattern so `et-mode` and `et-kill-all` keep working. The D890UV is
a DMR handheld, so packet runs over Bluetooth KISS rather than serial CAT.

Two deliberate deviations from the R6 original it is modelled on:

- `get_mac_or_exit()` rejects an **empty** MAC, not just a missing key. R6's
  `jq -e -r .bluetooth.mac` succeeds on `""` and hands an empty MAC to
  `rfcomm`. R7 fixed this upstream; this carries the fix for R6 hosts.
- Pairing writes the MAC back with `jq` instead of
  `sed -i 's|.*mac.*|...|g'`, which matches every line containing "mac" —
  including `deviceName` — and corrupts the JSON.

Radio firmware 1.05 (May 2026) or newer is recommended; earlier firmware has
known Bluetooth KISS TNC and APRS beacon defects.

### Added — GitHub CLI

`install_gh()` bakes `gh` into the ISO from the official `.deb`, falling back to
apt if the download fails. It resolves the **latest** release from GitHub's API
rather than carrying a pinned version.

A pin was tried first and was worse than useless. The URL was
`/releases/latest/download/gh_<pinned>_linux_amd64.deb`, and GitHub's
`/latest/download/` path only serves filenames belonging to the *current*
release — so the pin would 404 the moment gh published a new version, silently
falling back to apt's three-year-old build. Verified: that URL with any
non-current version returns 404. Kinetic's apt version is gh **2.14.4+dfsg1-1** from
mid-2022, which is old for a tool whose entire job is a remote API — but the
fallback means an offline or rate-limited build still gets a working `gh`.

This is also the answer to git credentials on the installed system. `gh auth
login && gh auth setup-git` registers gh as git's credential helper, so
`git push` works from a plain terminal. Deliberately *not* run at build time —
that would bake a personal token into the image.

Context: VS Code's GitHub extension keeps its token in VS Code's own encrypted
secret store and bridges it to git only via `GIT_ASKPASS` in the **integrated
terminal**. Any other shell on the box — a plain terminal, a script, an agent —
has no credential helper at all, and `git-credential-libsecret` is not even
compiled on a stock ETC install (only the `.c` and Makefile ship under
`/usr/share/doc/git/contrib/`).

### Added — anytone-cps

Builds `github.com/xbenkozx/anytone-cps` in the chroot with a desktop launcher.
This fills a real gap: **CHIRP does not support AnyTone DMR radios at all**, so
there was previously no Linux path to program the D578UVIII or D890UV. Alpha
upstream (D878UVII tested, D890UV listed but untested), so a build failure here
warns and continues rather than failing the ISO.

### Changed — build sequence and logging

`main()` now drives customizations from a single `"label|mode|function"` table
with derived step numbers, and each step is marked `fatal` or `best-effort`.
The hand-written numbering had drifted into "Step 15/14", two different
"Step 15"s, and a "Step 22/22" that was a no-op log line. Optional failures are
collected and reported together at the end.

Per the project's own rule against `tee` in sudo'd build commands, the new
installers append to the log directly.

### Added — CLAUDE.md, and curated Claude Code settings

`CLAUDE.md` documents the one-implementation rule, the hardware specifics, and
the traps above. `.claude/settings.json` is now committed with curated
permissions, including `deny` rules for `dd`, `mkfs`, `parted`, `wipefs` and
friends — this project must never write to a block device.
`.claude/settings.local.json` is gitignored.

### Fixed — et-os-addons was never actually installing anything

`lib/customize-addons.sh` copied files out of the repo's `overlay/` directory
and **never touched `scripts/`**. That was built on a wrong assumption, written
into its own comments: that et-os-addons ships launchers. It ships **nine real
installers** plus a test suite. Consequences of the mistake:

- The Kiwix entry pointed at ETC's apt `kiwix`, whose webserver is broken.
  `install-kiwix.sh` purges that package and installs the official AppImage —
  and the broken webserver is precisely what stops `et-hotspot` from serving
  offline content. Our `ENABLE_ETOSADDONS_KIWIX="no"` was exactly backwards.
- The `et-launcher` `.desktop` pointed at an AppImage nothing had installed.
  `install-et-launcher.sh` installs it to `/opt/appimages`. The old comment
  claiming ETC "does not install" it described our own omission.
- We hand-rolled four installers that were worse than upstream's:
  GridTracker pinned to `2.250901.0` against upstream's `2.260416.1` (seven
  months stale); WSJT-X Improved missing the
  `apt purge wsjtx wsjtx-doc wsjtx-data` that must precede it, since Improved
  overwrites ETC's binary; QSSTV pulling a stale `qsl.net` tarball instead of
  the ON4QZ repo. All four are deleted in favour of upstream's.

The integration now invokes upstream's individual scripts, each behind an
`ENABLE_ETOSADDONS_*` flag. The shim works because every installer opens with
`[ -z "$ET_ENV_LOADED" ] && . env.sh`, so exporting `ET_ENV_LOADED=1` makes
them skip that file — which matters, because it sources ETC's `env.sh` and
`functions.sh` from the r6 submodule and exports `ET_EXPERT=1` (turning on the
Wikipedia dialog). Verified by grep that the installers need only
`ET_DIST_DIR`, `ET_SRC_DIR`, `ET_HOME`, `ET_OS_ADDONS_BASE`,
`ET_LAUNCHER_APP_DL`, `SKEL` and `et-log`; nothing from `functions.sh`.

`scripts/install.sh` is still **not** run, but for the actual reason rather
than the one previously given: `.gitmodules` pins
`branch = release/r6`, and that script runs ETC's own installer from the
submodule first. Using it would build an **R6** image, losing the Reticulum
stack, `et-wwv`, Mercury, modem73, Pat 1.0.0, VARA 4.4.0/4.9.0, the Nov 2026
data sets and the CVE-2026-31431 mitigation.

The per-file `HOTSPOT` / `VARAC` / `VARA_EXTRAS` / `VR_N76` flags are replaced
by a single `ENABLE_ETOSADDONS_OVERLAY`, matching how upstream copies its
overlay. Splitting it per file is what let our copy drift. `customize-desktop.sh`
is off by default — it installs a glib schema override that competes with
`customize_desktop()`'s dconf database.

One ordering hazard handled explicitly: `install-et-os-addons.sh` copies
`overlay/etc/skel/*` and `overlay/opt/emcomm-tools/*` wholesale, which includes
its own `BACKUP_ITEMS.lst` **and** its own `et-user-backup`. Both are
superseded by the backup step below, so that step is sequenced after this one.
And when `et-launcher` is disabled, the autostart entry the overlay drops in is
removed — otherwise it errors on every login, which is the original complaint.

### Added — manifest-driven et-user-backup

R7's `et-user-backup` and the et-os-addons fork each had something the other
needed. R7 filters its list down to paths that exist and logs the skips, so
`tar` never errors on a missing directory — but the list is hardcoded in a file
the next ETC release overwrites. The fork is manifest-driven
(`tar -T ~/BACKUP_ITEMS.lst`) and covers what an operator actually accumulates
— `.fldigi`, `.nbems`, `YAAC`, `Documents`, `add-ons` — but dropped the
existence filtering, and carries a bug: its summary loop reads `BACKUP_DIRS`,
which it never assigns, so "the following were backed up" prints an **empty
list**.

`lib/customize-backup.sh` takes R7's correctness and the fork's extensibility.
The manifest is generated at build time by **parsing R7's own `BACKUP_DIRS`
array** out of the installed script and unioning it with the extras — so when a
future release adds paths, as R7 did with Reticulum, Partyline, NomadNet and
the JS8Call files, they are inherited rather than silently missed. The summary
bug is fixed by construction: it iterates the same filtered list `tar` was
given.

Measured on a configured machine: 13 paths captured where R7 stock captures 3.

Two things are excluded by default, with `BACKUP_EXTRA_ITEMS` to re-add them:

- `.wine32` (~1.9GB) — ETC backs the Wine prefix up separately via
  `et-wine-backup`, and `restore_user_backup()` depends on that split.
- `.navit/maps` and `my-maps` (~633MB) — the ISO seeds both into `/etc/skel`,
  so including them roughly doubles every backup to re-store bytes the
  installer just wrote.

### Removed — the commode=0 "PTT only" D578UVIII profile

Two profiles were written; now there is one, `anytone-d578uv.json`, with
`commode=1`. The PTT-only variant duplicated stock ETC's
`digirig-mobile-no-cat` profile, which keys the radio over the DigiRig's serial
RTS line using Hamlib model **6** (`RIG_MODEL_DUMMY_NOVFO`) and never talks to
the radio at all. Both gave you nothing but PTT — except the commode=0 version
*also* required the custom Hamlib build to do it.

For PTT with the radio's front panel left usable, select **"DigiRig Mobile (No
CAT)"** in `et-radio`. `ANYTONE_DEFAULT_MODE` is gone.

### Added — battery-percentage power action, via UPower

`POWER_BATTERY_ACTION_PERCENT` (default 10) and `POWER_BATTERY_ACTION`
(default `Suspend`) are written to `/etc/UPower/UPower.conf`.

This is a separate mechanism on purpose. `sleep-inactive-battery-type` is a
GNOME **enum** driven by an idle timer, so a percentage put into it would be
silently discarded — the exact failure mode this release exists to remove.
`customize_upower()` also sets `UsePercentageForPolicy=true` explicitly, lifts
`PercentageLow`/`PercentageCritical` above the action point so UPower's required
ordering stays valid, and greps the file afterward to confirm the edits landed
rather than trusting `sed`'s exit status.

### Changed — `secrets.env` holds only real decisions

Removed as derived, computed, or build-tooling detail, and hardcoded instead:

| Removed | Now |
| --- | --- |
| `APRS_PASSCODE`, `APRS_LAT`, `APRS_LON` | computed from `CALLSIGN` / `GRID_SQUARE` |
| `ANYTONE_D890_MAC` | discovered by `et-anytone-d890 pair` |
| `ADDITIONAL_PACKAGES` | `nodejs npm` hardcoded — they are build deps |
| `SQUASHFS_COMPRESSION` | `zstd` hardcoded |
| all `DESKTOP_*` / `DIM_SCREEN` / `SCREEN_BLANK*` / `DISABLE_ACCESSIBILITY` / `AUTOMATIC_SCREEN_BRIGHTNESS` | hardcoded to match R7 |
| `POWER_MODE` | not a dconf key at all; never worked |
| `ET_EXPERT`, `WIKIPEDIA_*`, `PAT_EMCOMM_GATEWAY` | commented examples only |

`customize_desktop()` is retained despite now mostly agreeing with R7, because
it creates `/etc/dconf/profile/user` — the database cascade that
`customize_power()`'s keyfile depends on. Deleting it would quietly break the
power settings.

`secrets.env.template` was rewritten: the stale notes about Edge, pipx-installed
CHIRP, and `ENABLE_ETOSADDONS_WSJTX` are gone, and every `ENABLE_ETOSADDONS_*`
flag now states why it is on or off.

### Note on `secrets.env`

`secrets.env` is gitignored and has always been. `embed_cache_files()` copies it
into the ISO at `/opt/emcomm-customizer-cache/secrets.env`, so it reappears on a
system **installed from a custom ISO** — it does not survive on a stock ETC
install, and it is not in `et-user-backup`. Verification now warns once per
build that a non-minimal ISO contains your WiFi PSK and Winlink password, so
don't share it; use `-m` for one you can.

## v2.0.0 — Remove install automation, share one implementation

Breaking release. The headline change is that **this project no longer automates
the Ubuntu installer**. A built ISO boots to the standard Ubuntu / EmComm Tools
walkthrough, and you choose the target disk and partition layout yourself.

### Removed — installer automation

The v1 build injected a preseed that drove the installer unattended, including
partitioning:

```
d-i partman-auto/choose_recipe select atomic
d-i partman/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true
```

`choose_recipe select atomic` selects the whole-disk recipe and
`confirm_write_new_label boolean true` pre-answers "yes, destroy the existing
partition table" — aimed at a **disk chosen by auto-detection**. The code's own
comments conceded that "Ubiquity ignores most partman preseeds - these are
best-effort", so the outcome was never predictable. This destroyed a partition
in practice.

Removed entirely:

- `customize_preseed()` (372 lines), `update_grub_for_preseed()` (128 lines)
- `detect_partition_strategy()` (113 lines), `calculate_swap_size()` (30 lines)
- All 161 `d-i` / partman preseed lines
- The `automatic-ubiquity only-ubiquity` GRUB boot parameters
- The Ventoy `auto_install` plugin block and its `preseed.cfg` / `loopback.cfg`.
  **This mattered**: stripping only the ISO's preseed would have left the same
  automated partitioning reachable through Ventoy.
- Config variables `PARTITION_STRATEGY`, `INSTALL_DISK`, `SWAP_SIZE_MB`,
  `EXT4_SIZE_MB`, `CONFIRM_ENTIRE_DISK`

### Removed — the dd USB writer

`--write-to` wrote the ISO to a block device, and used bare (`--write-to` with no
argument) it auto-detected which device to write. It was documented as
"RECOMMENDED". Along with `select_usb_device()` and `write_to_usb()`, it is gone
(176 lines). The flag now exits with an explanation.

Write the ISO yourself with Ventoy, a GUI writer (balenaEtcher, GNOME Disks,
Rufus), or your own `dd`. `--ventoy` remains — it is an ordinary file copy to a
mounted filesystem and never touches a block device.

**No script in this repository writes to a block device any more.**

### Fixed — Anytone D578UV CAT control never worked

The v1 radio profile specified Hamlib `"id": "301"`. **There is no model 301** —
Hamlib 4.5 has nothing in the 290–315 range and no AnyTone backend at all, so
`rigctld -m 301` simply failed.

v2 uses the real backend from
[CowboyPilot/Hamlib](https://github.com/CowboyPilot/Hamlib):
`RIG_MODEL_ATD578UVIII` = **37001** (`RIG_MAKE_MODEL(RIG_ANYTONE=37, 1)`, i.e.
family×1000+n — the same scheme that gives ETC's IC-705 profile its `3085`), at
115200 baud with PTT through the backend.

Install it with `./build-hamlib-anytone.sh`. Two profiles are now written:

| Profile | commode | Capability | Radio display |
|---|---|---|---|
| `anytone-d578uv` | 0 | PTT only | stays usable |
| `anytone-d578uv-com` | 1 | + freq / VFO / clock | locks to EXTERNAL CABLE MODE |

COM mode is expressed as `"conf": "commode=1"`, which ETC's existing
`wrapper-rigctld.sh` already passes through as `--set-conf=` — no wrapper
changes needed.

### Removed — three radio "fixes" that were wrong

- **`99-emcomm-tools-cat.rules`**: redundant *and* harmful. Stock
  `90-et-digirig-mobile.rules` already maps the DigiRig to `/dev/et-cat` and
  starts rigctld. v1's rule added unguarded `SYMLINK+="et-cat"` for generic
  FTDI/PL2303/CH340, letting an unrelated USB serial device — a GPS, say — steal
  `/dev/et-cat`.
- **`/etc/systemd/system/rigctld.service` override**: stock ETC ships this unit
  and starts it from udev when the radio appears. v1's override added
  `Restart=on-failure` *and* enabled it at boot. rigctld exits 1 when no CAT
  device is present, so this restart-loops forever on any boot without the radio
  plugged in.
- **`wrapper-rigctld.sh` patch**: patched `do_full_auto()` to "protect" the
  active radio. `do_full_auto()` is defined but **never called** anywhere in that
  script. The patch guarded nothing and risked corrupting a working wrapper.

### Fixed — APRS beacon had no position

v1's PBEACON rewrite replaced the whole line but emitted no `lat=`/`long=`,
producing a positionless beacon. Worse, if the rewrite was skipped the stock
template beaconed from its upstream placeholder coordinates — `lat=33.5828
long=-112.1499`, Phoenix, Arizona — regardless of where you actually are.

v2 derives the position from `GRID_SQUARE` (subsquare center, ~3 km, so your
exact QTH is not published) or from explicit `APRS_LAT`/`APRS_LON`.

Also fixed:

- **Dire Wolf's config parser is line-oriented** and does not support backslash
  continuations. A multi-line `PBEACON` yields `No = found in, \` plus one
  `Unrecognized command` per continuation line. Every directive is now emitted on
  one line, and this is called out in the generated file.
- **`every=30` means 30 *seconds***, not minutes. The default is now `30:00`
  (30 minutes), which is appropriate for a fixed station.
- `APRS_PASSCODE` now defaults to empty and is **computed** from the callsign.
  The algorithm is public and derivable by anyone who knows your call, so storing
  it in a secrets file was pointless.
- The iGate is explicitly receive-only: no `IGTXVIA` is written, so nothing is
  gated from the internet back onto RF.

### Added — GPS beaconing support

ETC v6 ships Dire Wolf built **without** gpsd (`direwolf` reports only
`hamlib cm108-ptt`), so the `GPSD` directive is a hard config error and direwolf
refuses to start. `APRS_BEACON_MODE="gps"` therefore falls back to a fixed
beacon and says so.

`./build-direwolf-gpsd.sh` rebuilds Dire Wolf with `ENABLE_GPSD` into its own
prefix and switches `/usr/local/bin/direwolf` to it. The original build is left
untouched; `--revert` is instant. It refuses to switch unless the new binary
actually reports gpsd support.

### Fixed — a probe that always returned false

`direwolf_has_gpsd()` and `hamlib_has_anytone()` shell out to commands that exit
non-zero (they print usage). Under `set -o pipefail`, `direwolf | grep -q ...`
reports failure **even when grep matches**. The capability probes would have
always returned false, so GPS beaconing would have stayed disabled even after a
successful rebuild. Both now capture output first and let grep alone decide.

### Fixed - addons silently installed nothing on a first run

`fetch_addons()` returned the overlay path on stdout while `log()` also writes
to stdout, so `ov=$(fetch_addons ...)` captured the "Cloning..." banner into the
path:

```
ov = "[INFO] Cloning https://github.com/clifjones/et-os-addons.git...
      /var/cache/emcomm-tools-customizer/et-os-addons/overlay"
```

Every source lookup then missed and the whole addon step installed nothing while
reporting only per-file warnings. It reproduced **only on a cold cache**, since a
warm one never logs -- which is why it survived initial testing. The path is now
returned via a global, and a malformed overlay fails loudly instead of degrading
into per-file warnings.

### Fixed - the Hamlib revert manifest was empty

`build-hamlib-anytone.sh` recorded ETC's `/usr/local` -> `/opt/hamlib` symlinks
by testing `readlink -f` output against `/opt/hamlib/*`. But **`/opt/hamlib` is
itself a symlink** (`-> /opt/hamlib-4.5` on ETC v6), so `readlink -f`
canonicalises past it and the pattern never matched. Result: a zero-byte
manifest and a `--revert` that restored nothing.

Now canonicalises the reference path, reconstructs entries for links already
replaced by `make install`, refuses to proceed if it records zero entries, and
adds `--rebuild-manifest` to regenerate from `/opt/hamlib` after the fact.
`--revert` now rejects an empty manifest instead of silently succeeding.

Worth recording: the CowboyPilot fork bumps the soname to `libhamlib.so.5`,
while ETC's Hamlib 4.5 is `libhamlib.so.4`. Installing to `/usr/local` therefore
left `libhamlib.so.4` untouched -- `direwolf`, `fldigi`, `js8call` and `wsjtx`
keep loading ETC's original library, and only `rigctld` picks up the fork. The
apps reach the radio over NET rigctl anyway, so this is the desired split.

### Fixed - post-install.sh verification was broken in four ways

`post-install.sh` is the **user-level** companion to the root-level
`apply-to-live-system.sh`; it must not run under sudo or it would restore
archives into `/root`. It now refuses to. Its checks were badly broken:

- **`direwolf -v` is not a valid flag.** It reported
  `direwolf: invalid option -- 'v'` as the version string.
- **The iGate check could never pass.** It grepped lowercase `igate`; the
  template contains `IGSERVER`, `IGLOGIN` and `iGate`. With no `else` branch it
  failed silently.
- **The WiFi check read the wrong file in the wrong format** --
  `conf.d/30-emcomm-tools.conf` rather than the `.nmconnection` files in
  `system-connections/` -- and `grep -c ... || echo "0"` produced `$'0\n0'`,
  because `grep -c` prints `0` *and* exits 1, making the numeric test throw
  "integer expression expected".
- **The backup search path resolved outside the repository**
  (`$SCRIPT_DIR/../cache`), so `--restore` never found anything. It now searches
  `$HOME` first, where `et-user-backup` actually writes.

Verification moved to `lib/verify.sh`, shared by `post-install.sh --verify` and
the new `apply-to-live-system.sh --verify`. It now also checks the things v2
introduced: Hamlib model 37001, the AnyTone backend, profile JSON validity, a
dangling `active-radio.json`, gpsd support, that the beacon actually carries a
position, that ETC's `{{ET_*}}` placeholders survived, that no backslash
continuations crept in -- and it runs the template through `direwolf` to confirm
it genuinely parses. A final section flags leftovers from v1 that should be
removed.

### Fixed - EOL apt sources produced a useless error

ETC v6 is Ubuntu 22.10 "kinetic", which reached end of life in July 2023. Its
packages moved to old-releases.ubuntu.com, so a stock `sources.list` yields
"does not have a Release file" and then "Unable to locate package libgps-dev" --
and `build-direwolf-gpsd.sh` reported only a generic "Failed to install build
dependencies".

`lib/common.sh` gains `check_eol_apt_sources()`, used by both build scripts. It
detects an EOL codename still pointing at the live mirrors and prints the exact
`sed` command to repoint them. `build-direwolf-gpsd.sh` additionally checks for
`gps.h` up front, skips the install when headers are already present, verifies
`libgps-dev` is actually obtainable before attempting it, and warns if
`libgps-dev` and the runtime `libgps28` versions disagree.

### Fixed - the post-build GPSD gate rejected good builds

Two more instances of the pipefail trap, in `build-direwolf-gpsd.sh`. The second
was serious: after a fully successful compile,

```bash
if "$NEW" 2>&1 </dev/null | grep -qi 'optional support for.*gpsd'; then
```

always evaluated false -- direwolf exits non-zero after printing its banner, so
under `set -o pipefail` the pipeline fails even when grep matches. The script
would build correctly and then refuse to install, claiming the new binary lacked
GPSD support. Both sites now use a shared `binary_has_gpsd()` helper.

### Corrected - the Hamlib soname claim

Earlier notes said the fork keeps the `.so.4` soname and would therefore be
picked up by every hamlib app. Verified on a real install: the fork is
`libhamlib.so.5` and ETC's is `libhamlib.so.4`, so `direwolf`, `fldigi`,
`js8call` and `wsjtx` keep loading ETC's original library and only `rigctld`
uses the fork. Since those apps talk to the radio over NET rigctl, that is the
split you want.

### Fixed - an intermittent false "No AnyTone backend" warning

A second, distinct pipe hazard, and the subtler of the two. Having learned to
capture command output before grepping it, the probes then wrote that capture
back into a pipe:

```bash
out=$(rigctl -l 2>/dev/null || true)
printf '%s' "$out" | grep -qi anytone      # WRONG
```

`grep -q` exits the instant it matches. On a large stream the writer may still
be mid-write, so it dies on SIGPIPE, and `pipefail` turns that into a false
negative. `rigctl -l` emits 322 lines and this failed roughly **5% of runs**
(measured: 190 TRUE / 10 FALSE over 200 calls), producing an intermittent
"No AnyTone backend in Hamlib" warning on a system that plainly had one. The
direwolf probe never showed it because its banner fits in the pipe buffer.

All early-exiting greps (`-q`, `-m1`) now read from a **herestring**, which is a
redirection rather than a pipeline: `pipefail` cannot apply and there is no
writer process to signal.

```bash
grep -qi anytone <<< "$out"                # correct
```

Verified: 300/300 consistent afterwards, and 15 consecutive full verification
runs produce byte-identical summaries.

### Fixed - Dire Wolf could not build after installing the Hamlib fork

Building Dire Wolf failed with:

```
src/ptt.c:1000:35: error: storage size of 'hport' isn't known
    hamlib_port_t hport;
```

`src/ptt.c` declares a `hamlib_port_t` on the stack. Hamlib 4.x defines that as
a complete struct; **Hamlib 5 made it opaque** (`typedef struct hamlib_port
hamlib_port_t;` with no body). Checked upstream: Dire Wolf 1.7, 1.8, `dev` and
`master` all still declare it this way, so there is no newer Dire Wolf that
fixes it. The only option is to compile against Hamlib 4.x headers.

This is collateral damage from `build-hamlib-anytone.sh`, and the script's own
comments were wrong about it. They claimed `/opt/hamlib` was "left untouched".
In fact `/usr/local/include/hamlib` is a **symlink into `/opt/hamlib`**, so
`make install --prefix=/usr/local` wrote *through* it and replaced ETC's Hamlib
4.5 headers and `lib/pkgconfig/hamlib.pc` in place. The 4.0.5 runtime libraries
survived (the fork uses a different soname), so everything kept *running* --
only *compiling* against Hamlib broke, which is why it went unnoticed until a
build was attempted.

`build-direwolf-gpsd.sh` now compile-probes the system headers with the exact
failing construct, and when they are Hamlib 5 it stages a private copy of the
Hamlib 4.5 headers and passes `HAMLIB_INCLUDE_DIR` / `HAMLIB_LIBRARY` directly
to CMake -- bypassing `Findhamlib.cmake`'s search. It links ETC's original
`libhamlib.so.4`, not the fork's `.so.5`, so the rebuilt Dire Wolf sits on the
same library stack as the one it replaces. Nothing installed on the system is
modified to achieve this. After building it reports which `libhamlib` and
`libgps` the new binary actually links.

### Changed — one implementation, two paths

Customizations moved into `lib/`, operating on `$ET_ROOT`:

| Module | Purpose |
|---|---|
| `lib/common.sh` | logging, backups, `etpath`, APRS passcode, grid→lat/lon, capability probes |
| `lib/customize-aprs.sh` | Dire Wolf APRS template |
| `lib/customize-radio.sh` | D578UVIII profiles |
| `lib/customize-addons.sh` | et-os-addons features |

`build-etc-iso.sh` sets `ET_ROOT=$SQUASHFS_DIR`; `apply-to-live-system.sh` sets
`ET_ROOT=/`. Both run the same code. Divergence between the two copies is how v1
shipped a nonexistent model number in one place and a positionless beacon in the
other.

Also fixed: the `active-radio.json` symlink was absolute, which in an ISO build
embedded the build machine's squashfs path and dangled on the installed system.
It is now relative.

### Added — `apply-to-live-system.sh`

Applies every customization to an already-installed ETC system. No Cubic, no ISO
rebuild, no disk operations — file writes only, and it backs up everything it
touches.

```
sudo ./apply-to-live-system.sh --dry-run     # preview
sudo ./apply-to-live-system.sh               # apply
sudo ./apply-to-live-system.sh --uninstall   # restore
```

This is the supported upgrade path. See [UPGRADING.md](UPGRADING.md).

### Changed — et-os-addons reflects reality

v1 installed every addon and reported success, leaving launchers that error on
click. Features are now grouped by whether they work on a stock v6 system, and
each label states its dependency.

- `ENABLE_ETOSADDONS_WSJTX` **removed** — dead code. There is no `et-wsjtx` in
  the addons repo, and ETC v6 already ships `/opt/emcomm-tools/bin/et-wsjtx`.
  Setting it never did anything.
- `ENABLE_ETOSADDONS_USERBACKUP` now defaults to **no** — it replaces the
  `et-user-backup` ETC already ships, silently changing what gets backed up.
- Added `ENABLE_ETOSADDONS_VARAC`, `ENABLE_ETOSADDONS_VARA_EXTRAS`,
  `ENABLE_ETOSADDONS_COMMSTATONE` for addons v1 never installed.
- `vgc-vrn76.bt.json` is no longer copied — already in stock `radios.d`.

### Housekeeping

- `build-etc-iso.sh`: 5363 → ~3850 lines
- Removed stale artifacts: `test_grub_before.cfg`, `test_grub_after.cfg`,
  `test_grub_fixed.cfg`, `wget-log`
- `usage()` no longer documents a `-a` flag that was never parsed

---

## v1.0 — First working build

Automated ISO customization via xorriso/squashfs without Cubic. Preseed-based
unattended installation, dd USB writer, APRS/radio/addons customization.
