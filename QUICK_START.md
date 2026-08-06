# Quick Start Guide

Two paths. Pick the one that matches what you have.

---

## A. Already running ETC — no rebuild needed

Fastest way to get APRS, the D578UVIII radio profiles and the addon launchers
onto a machine you're already using. No Cubic, no ISO, no disk operations.

```bash
git clone https://github.com/AlwaysLearningTech/emcomm-tools-customizer.git
cd emcomm-tools-customizer

sudo ./apply-to-live-system.sh --dry-run   # preview
sudo ./apply-to-live-system.sh             # apply
sudo ./apply-to-live-system.sh --uninstall # undo
```

`secrets.env` is optional here — `CALLSIGN` and `GRID_SQUARE` are read from
`~/.config/emcomm-tools/user.json` if ETC is already configured.

Then the user-level half, **without sudo** (it writes to your home directory and
will refuse to run as root):

```bash
./post-install.sh --verify         # check everything
./post-install.sh --restore        # restore etc-user-backup into $HOME
./post-install.sh --restore-wine   # also the Wine/VARA prefix
./post-install.sh --chirp          # install CHIRP
./post-install.sh                  # interactive menu
```

### One-time, for full radio support

Stock Hamlib 4.5 has **no AnyTone backend**, so the D578UV can't be driven by
`rigctld` until you install one:

```bash
sudo ./build-hamlib-anytone.sh      # adds Hamlib model 37001
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
# Fix apt sources for EOL Ubuntu 22.10
sudo sed -i 's/archive.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list
sudo sed -i 's/security.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list
sudo apt update

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

### Skip the 3.6GB Ubuntu download

```bash
mkdir -p cache
cp ~/Downloads/ubuntu-22.10-desktop-amd64.iso cache/
```

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
boot, run `sudo ./apply-to-live-system.sh`.

---

## Essential Configuration

Minimum `secrets.env`:

```bash
CALLSIGN="N0CALL"
GRID_SQUARE="CN87uo"      # used for the APRS beacon position
USER_USERNAME="emcomm"
WIFI_SSID_HOME="network"
WIFI_PASSWORD_HOME="password"
```

Leave `APRS_PASSCODE` empty — it's computed from your callsign.

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
- [CHANGELOG.md](CHANGELOG.md) — what changed in v2.0.0 and why
