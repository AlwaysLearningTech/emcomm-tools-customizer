# Quick Start Guide

Two paths. Pick the one that matches what you have.

---

## A. Already running ETC — no rebuild needed

Fastest way to get APRS, the D578UVIII radio profile and the backup manifest
onto a machine you're already using. No Cubic, no ISO, no disk operations.

```bash
git clone https://github.com/AlwaysLearningTech/emcomm-tools-customizer.git
cd emcomm-tools-customizer

sudo ./apply-to-live-system.sh --dry-run   # preview
sudo ./apply-to-live-system.sh             # apply
sudo ./apply-to-live-system.sh --uninstall # undo
```

The et-os-addons installers are **opt-in** here, via `--addons`. They apt-purge
and replace system packages (stock WSJT-X, kiwix), which `--uninstall` cannot
reverse — everything else this script does is file-only and fully reversible.

`secrets.env` is optional here — `CALLSIGN` and `GRID_SQUARE` are read from
`~/.config/emcomm-tools/user.json` if ETC is already configured.

Then the user-level half, **without sudo** (it writes to your home directory and
will refuse to run as root). On a system installed from one of these ISOs the
scripts are already at `/opt/emcomm-tools-customizer/` -- no clone needed:

```bash
./post-install.sh --verify         # check everything
./post-install.sh --restore        # restore etc-user-backup into $HOME
./post-install.sh --restore-wine   # also the Wine/VARA prefix
./post-install.sh --chirp          # install CHIRP (skipped if the ISO has it)
./post-install.sh --everything     # all of the above, Wine included
./post-install.sh                  # interactive menu
```

### First: make apt work again

ETC (through R7) is Ubuntu 22.10 "kinetic", EOL since July 2023. Its packages moved to
`old-releases.ubuntu.com`, so until you repoint apt, every install fails with
"Unable to locate package". This blocks CHIRP, `build-direwolf-gpsd.sh`, and
anything else.

```bash
./fix-apt-sources.sh --check     # is it broken? (no root needed)
sudo ./fix-apt-sources.sh        # back up, repoint, apt-get update
```

### One-time, for full radio support

Stock Hamlib 4.5 has **no AnyTone backend**, so the D578UV can't be driven by
`rigctld` until you install one:

```bash
sudo ./build-hamlib-anytone.sh      # adds Hamlib model 37001
```

For the **AnyTone AT-D890UV**, packet runs over its Bluetooth KISS TNC rather
than serial CAT. Pair once, then connect whenever you need it:

```bash
et-anytone-d890 pair       # discovers and records the radio's MAC
et-anytone-d890 connect    # then pick axcall / QtTermTCP / Winlink / YAAC
```

Firmware 1.05 (May 2026) or newer is strongly recommended — earlier firmware
has known Bluetooth KISS TNC and APRS beacon defects.

### Programming your radios

**CHIRP does not support AnyTone DMR radios.** Use `anytone-cps` for the
D578UVIII and D890UV, and CHIRP for everything else.

```bash
./post-install.sh --chirp   # builds CHIRP from the official git repo
anytone-cps                 # baked into the ISO; alpha upstream
```

Then pick a profile with `et-radio` and **verify PTT before trusting it on air**:

```bash
systemctl status rigctld
rigctl -m 2 -r localhost:4532 T 1   # key
rigctl -m 2 -r localhost:4532 T 0   # unkey
```

For GPS-tracked beaconing (ETC ships Dire Wolf without gpsd):

```bash
sudo ./build-direwolf-gpsd.sh
```

---

## B. Building a fresh ISO

```bash
# Fix apt sources for EOL Ubuntu 22.10 (kinetic)
sudo ./fix-apt-sources.sh

# Install dependencies
sudo apt install -y xorriso squashfs-tools wget curl jq git

# Clone and configure
git clone https://github.com/AlwaysLearningTech/emcomm-tools-customizer.git
cd emcomm-tools-customizer
cp secrets.env.template secrets.env
nano secrets.env

# List available releases, betas included
./build-etc-iso.sh -l

# Build
sudo ./build-etc-iso.sh -r stable
```

### Put build inputs in `cache/`

Files the build installs go in `cache/`; `secrets.env` holds no file paths.
`cache/` is embedded in the ISO, so after a reinstall everything is already
there.

```bash
mkdir -p cache
cp ~/Downloads/ubuntu-22.10-desktop-amd64.iso cache/   # optional: skips a 3.6GB download
cp ~/Downloads/GridTracker2-*-amd64.deb cache/        # required for ENABLE_GRIDTRACKER=yes
cp ~/etc-*-backup-*.tar.gz cache/                     # optional: your ETC backups
```

VS Code needs nothing: the build downloads the current version and keeps a
copy in `cache/` as an offline fallback. After install, VS Code's own apt repo
keeps it updated.

### Getting the ISO onto USB, and installing

Nothing in this repo writes to a block device. Use Ventoy (a plain file copy),
a GUI writer that shows you the drive by name, or your own `dd`:

```bash
cp output/*.iso /media/$USER/Ventoy/ && sync    # Ventoy

lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINT       # or dd, checking twice
sudo dd if=output/<iso> of=/dev/sdX bs=4M status=progress conv=fsync
```

Boot it and run the **normal Ubuntu / ETC installer**. You choose the disk and
partition layout — there is no preseed and no automated partitioning. After first
boot, run `/opt/emcomm-tools-customizer/post-install.sh` (no sudo) to restore
your home directory and verify. The ISO already has every customization in it.

---

### Rebuilding on a system installed from one of these ISOs

Clone the repo and build. Nothing else to set up:

```bash
git clone https://github.com/AlwaysLearningTech/emcomm-tools-customizer.git ~/Github/emcomm-tools-customizer
cd ~/Github/emcomm-tools-customizer
sudo ./build-etc-iso.sh -r stable
```

The build links the ISO's embedded files (`/opt/emcomm-customizer-cache`) into
`cache/`, and if there is no `secrets.env` it copies the embedded one into the
repo as yours (mode 600) -- edit it there before building if anything changed.

---

## Essential Configuration

Minimum `secrets.env`:

```bash
CALLSIGN="N0CALL"
GRID_SQUARE="CN87uo"      # used for the APRS beacon position
USER_USERNAME="emcomm"    # match the account you'll create in the installer
WIFI_SSID_HOME="network"
WIFI_PASSWORD_HOME="password"
```

Leave `APRS_PASSCODE` empty — it's computed from your callsign.

`secrets.env` is gitignored, so it is never pushed and does not come with a
`git clone`. It travels with the ISO instead: the build embeds it (root-only)
at `/opt/emcomm-customizer-cache/secrets.env`, and the next build on the
installed system copies it back into the repo as your own file. That also
means a non-minimal ISO contains your WiFi PSK and Winlink password. Keep a
copy off-machine, and build with `-m` if you intend to share the ISO.

## Release Modes

| Mode | Command | Description |
| --- | --- | --- |
| Stable | `-r stable` | Latest GitHub Release (recommended) |
| Latest | `-r latest` | Most recent git tag — betas included |
| Specific | `-r tag -t <name>` | Exact tag by name |

## Debug Mode

```bash
sudo ./build-etc-iso.sh -r stable -d       # debug logging
sudo ./build-etc-iso.sh -r stable -d -v    # + bash tracing
```

## More

- [UPGRADING.md](UPGRADING.md) — upgrade paths, beta tracking, v1 migration
- [CHANGELOG.md](CHANGELOG.md) — what changed in each release and why
