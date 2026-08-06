# Upgrading

Two ways to move an EmComm Tools machine forward. Pick based on what you're
actually trying to do.

## Which script does what

| Script | Runs as | Scope |
| --- | --- | --- |
| `apply-to-live-system.sh` | **root** (`sudo`) | System paths: APRS template, radio profiles, addon launchers |
| `post-install.sh` | **your user** (never sudo) | Your home directory: backup restore, CHIRP, python tooling |

They do not overlap. `post-install.sh` refuses to run under sudo — under it,
`$HOME` is `/root` and your restored archives would land there owned by root.
Verification is shared: both offer `--verify`, backed by `lib/verify.sh`.

```bash
sudo ./apply-to-live-system.sh --verify   # or
./post-install.sh --verify
```

### Restoring your backups

`post-install.sh` searches `$HOME` first, then the repo's `cache/`:

```bash
./post-install.sh --restore        # user config only
./post-install.sh --restore-wine   # also the Wine/VARA prefix (asks first)
```

---

| | **Apply to a live system** | **Build a new ISO** |
| --- | --- | --- |
| Command | `sudo ./apply-to-live-system.sh` | `sudo ./build-etc-iso.sh` |
| Time | seconds | ~30–60 min |
| Keeps your data | yes | no — it's a fresh install |
| Touches disks | never | never (writes an `.iso` file) |
| Good for | config changes, trying a beta feature, fixing drift | new hardware, a clean rebuild, ETC version jumps |

Both run the same code from `lib/`, so they produce identical configuration.

---

## Everyday upgrades: the live path

This is what you want most of the time. It rewrites the APRS template, the radio
profiles and the addon launchers in place. It does not touch partitions, the
bootloader, or your home directory.

```bash
cd ~/github/emcomm-tools-customizer
git pull

sudo ./apply-to-live-system.sh --dry-run     # see what would change
sudo ./apply-to-live-system.sh               # apply it
```

Everything it overwrites is copied to `/opt/emcomm-tools/.customizer-backup/<timestamp>/`
first.

```bash
sudo ./apply-to-live-system.sh --list-backups
sudo ./apply-to-live-system.sh --uninstall   # restore the newest backup
```

Work on one area at a time with `--no-aprs`, `--no-radio`, `--no-addons`.

### Settings

`secrets.env` is optional. Without it you get working defaults, and `CALLSIGN` /
`GRID_SQUARE` are read from `~/.config/emcomm-tools/user.json` if ETC is already
set up. To customize:

```bash
cp secrets.env.template secrets.env
$EDITOR secrets.env
```

`secrets.env` is gitignored. Note that `APRS_PASSCODE` should be left empty — it
is computed from your callsign, and the algorithm is public, so it was never a
secret worth storing.

---

## One-time setup for full radio support

Two capabilities need a compile. Both install alongside the stock build rather
than replacing it, and both have a one-command revert.

### AnyTone D578UVIII CAT control

Stock Hamlib 4.5 has **no AnyTone backend at all**, so the D578UV cannot be
driven by `rigctld` out of the box. v1 of this repo claimed Hamlib model `301`,
which does not exist.

```bash
sudo ./build-hamlib-anytone.sh          # builds CowboyPilot/Hamlib, model 37001
sudo ./build-hamlib-anytone.sh --verify
sudo ./build-hamlib-anytone.sh --revert # back to ETC's Hamlib
```

Note that ETC installs Hamlib into `/opt/hamlib` (itself a symlink to
`/opt/hamlib-4.5`) and symlinks entries into `/usr/local`. The fork's README
build (`--prefix=/usr/local`) replaces those with real files, so the script
records a manifest first and `--revert` restores it. If the manifest is ever
empty, rebuild it from `/opt/hamlib`:

```bash
sudo ./build-hamlib-anytone.sh --rebuild-manifest
```

**The fork bumps the soname to `libhamlib.so.5`**, while ETC's Hamlib 4.5 is
`libhamlib.so.4`. That matters more than it sounds: installing to `/usr/local`
leaves `libhamlib.so.4` untouched, so `direwolf`, `fldigi`, `js8call` and
`wsjtx` keep loading ETC's original library, and only `rigctld` picks up the
fork. Since those apps reach the radio over NET rigctl (`localhost:4532`) rather
than driving it directly, that is exactly the split you want — the AnyTone
backend only has to exist in `rigctld`.

Confirm it on your own machine:

```bash
ldd "$(command -v direwolf)" | grep hamlib   # expect libhamlib.so.4
ldd /usr/local/bin/rigctld   | grep hamlib   # expect libhamlib.so.5
```

Then pick a profile with `et-radio`:

- **D578UVIII (DigiRig, PTT only)** — `commode=0`. PTT works; you set the VFO on
  the radio; the display stays usable. Start here.
- **D578UVIII (COM mode)** — `commode=1`. Adds frequency/VFO/clock control, but
  the radio shows EXTERNAL CABLE MODE and locks its front panel. `set_freq` only
  works with Channel A selected and VFO A in VFO mode.

**Verify PTT before trusting it on air:**

```bash
systemctl status rigctld
rigctl -m 2 -r localhost:4532 T 1   # key
rigctl -m 2 -r localhost:4532 T 0   # unkey
```

### GPS-tracked APRS beaconing

ETC v6's Dire Wolf is built without gpsd, so `GPSD`/`TBEACON` are a hard config
error. Check yours:

```bash
direwolf | grep 'optional support'
# stock v6: "hamlib cm108-ptt"  -> no gpsd
```

`APRS_BEACON_MODE="gps"` detects this and falls back to a fixed beacon rather
than writing a config that won't start. To get real GPS tracking:

```bash
sudo ./build-direwolf-gpsd.sh           # rebuild with ENABLE_GPSD
./build-direwolf-gpsd.sh --verify
sudo ./build-direwolf-gpsd.sh --revert  # back to the stock build
```

Then set `APRS_BEACON_MODE="gps"` in `secrets.env` and re-run
`sudo ./apply-to-live-system.sh --no-radio --no-addons`.

---

## Tracking ETC beta releases

```bash
./build-etc-iso.sh -l                          # list tags and releases
sudo ./build-etc-iso.sh -r latest              # newest tag, betas included
sudo ./build-etc-iso.sh -r tag -t v6.1.0-beta2 # a specific tag
sudo ./build-etc-iso.sh -r stable              # newest formal release
```

For a beta you only want to *try*, build the ISO and boot it live before
installing. If the beta only changes ETC configuration rather than the base
system, the live path is faster than a reinstall.

---

## Installing a built ISO

**The ISO no longer installs itself.** v1 shipped a preseed that partitioned the
disk unattended; v2 does not, and neither does the Ventoy path.

1. Put the ISO on a USB stick:
   - **Ventoy** (safest — a file copy onto an already-prepared stick, no device
     path to get wrong): `sudo ./build-etc-iso.sh --ventoy /media/$USER/Ventoy`,
     or just copy the `.iso` across yourself.
   - **A GUI writer** — balenaEtcher, GNOME Disks, Rufus. These show you the
     target drive by name and size before writing.
   - **`dd`**, run by you, after checking the device twice:
     ```bash
     lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINT
     sudo dd if=output/<iso> of=/dev/sdX bs=4M status=progress conv=fsync
     ```
2. Boot it and run the normal Ubuntu / EmComm Tools installer. **You choose the
   disk and the partition layout**, every time.
3. After first boot, apply customizations:
   ```bash
   git clone <this repo> && cd emcomm-tools-customizer
   sudo ./apply-to-live-system.sh
   ```

---

## Migrating from v1

If you have a v1 `secrets.env`, these variables no longer exist and are ignored:

```text
PARTITION_STRATEGY  INSTALL_DISK  SWAP_SIZE_MB  EXT4_SIZE_MB
CONFIRM_ENTIRE_DISK  ENABLE_ETOSADDONS_WSJTX  ENABLE_D578UV_CAT
DIREWOLF_ADEVICE  DIREWOLF_PTT  APRS_BEACON_DIR
```

Worth revisiting:

- `APRS_PASSCODE` — set it to `""` so it's computed from your callsign.
- `APRS_BEACON_INTERVAL` — v1's `300` meant 300 **seconds**. The default is now
  `30:00` (30 minutes). Bare numbers are seconds in Dire Wolf's time format.
- `APRS_SYMBOL` — now a Dire Wolf symbol name (`digi`) or a 2-character code.
- `ENABLE_ETOSADDONS_USERBACKUP` — now defaults to `no`, since it replaces the
  `et-user-backup` ETC already ships.

If a v1 build put any of the following on your system, remove them — see
CHANGELOG.md for why each is wrong:

```bash
sudo rm -f /etc/udev/rules.d/99-emcomm-tools-cat.rules
sudo rm -f /etc/systemd/system/rigctld.service   # keep /lib/systemd/system/rigctld.service
sudo systemctl daemon-reload

# restore the stock rigctld wrapper if v1 patched it
ls /opt/emcomm-tools/sbin/wrapper-rigctld.sh.backup && \
  sudo cp /opt/emcomm-tools/sbin/wrapper-rigctld.sh{.backup,}
```
