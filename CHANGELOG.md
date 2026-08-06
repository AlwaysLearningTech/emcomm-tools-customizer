# Changelog

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
