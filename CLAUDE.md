# CLAUDE.md

Guidance for Claude Code working in this repository.

## What this project is

Scripts that build a customized **EmComm Tools Community (ETC)** ISO without
Cubic's manual copy-paste, plus the same customizations applied to an already
running ETC system.

ETC is built on **Ubuntu 22.10 "kinetic"**, which is end-of-life. This single
fact causes more bugs here than anything else — see "Kinetic is EOL" below.

**There is no autoinstall, no preseed, and no automated partitioning.** That
was removed deliberately in v2.0.0: it was buggy and it overwrote a dual-boot
Windows partition. The ISO boots the normal Ubuntu/ETC installer and the user
chooses their own disk layout. Do not reintroduce automated partitioning,
and nothing in this repo may write to a block device.

## Versioning

This project tracks ETC rather than numbering itself independently. The version
is `<ETC semver we target>-<our revision>`, set in
`lib/common.sh`:

```bash
ETC_TARGET_VERSION="7.0.2"    # the ETC release these customizations are tested against
CUSTOMIZER_REVISION="2"       # our iteration on top of it
# CUSTOMIZER_VERSION => "7.0.2-2"
```

Currency is then obvious: if ETC's latest release is 7.0.2 and this says
`7.0.2-1`, we are current. `check_etc_target_drift()` compares the release
actually being built against `ETC_TARGET_VERSION` and warns, in either
direction, during the build.

**When moving to a new ETC release:** read its notes first for settings that
became redundant, new `et-os-addons` installers, and changes to
`et-user-backup`'s path list — then set `ETC_TARGET_VERSION` and reset
`CUSTOMIZER_REVISION=1`. Bump only the revision for changes of ours.

Releases before this scheme used plain semver (`v2.0.0`); those references in
the changelog are historical and stay as they are.

## Architecture

Every customization lives in exactly **one** place, under `lib/`, and operates
on `$ET_ROOT`:

| Caller | `ET_ROOT` |
| --- | --- |
| `build-etc-iso.sh` | the unpacked squashfs |
| `apply-to-live-system.sh` | `/` |

This is the core design rule. v1 had two implementations that drifted, and
shipped a Hamlib model number (301) that does not exist plus an APRS beacon
with no position in it. **When adding a customization, put it in `lib/` and
call it from both paths — never inline it into one.**

- `lib/common.sh` — shared helpers (`etpath`, `write_file`, `backup`,
  `dconf_bool`, `dconf_double`, `aprs_passcode`, `grid_to_latlon`,
  `hamlib_has_anytone`, `check_eol_apt_sources`). Source it first.
- `lib/customize-radio.sh` — AnyTone D578UVIII CAT profiles
- `lib/customize-anytone-dmr.sh` — D890UV Bluetooth KISS TNC, anytone-cps launcher
- `lib/customize-aprs.sh` — Dire Wolf APRS config
- `lib/customize-addons.sh` — runs et-os-addons' own installers
- `lib/customize-backup.sh` — manifest-driven `et-user-backup`
- `lib/verify.sh` — shared verification

`build-etc-iso.sh` runs its customizations from a single step table in
`main()` (`"label|mode|function"`). `mode` is `fatal` or `best-effort`. Add new
steps there rather than inlining calls, and pick `fatal` only when shipping
without the step would mean a broken radio.

## Hardware this targets

- **AnyTone AT-D578UVIII** — CAT control over a DigiRig cable. Hamlib model
  **37001** (`RIG_MODEL_ATD578UVIII`). **Stock Hamlib 4.5 has no AnyTone
  backend at all**, so `build-hamlib-anytone.sh` must run (it builds
  CowboyPilot/Hamlib) or `rigctld` rejects 37001 and there is no CAT and no
  PTT. The ISO build calls it inside the chroot; don't write 37001 profiles
  without ensuring the backend is present.
- **AnyTone AT-D890UV** — DMR handheld. Packet is over its **Bluetooth KISS
  TNC**, not serial CAT, so it uses ETC's `*.bt.json` + `et-<model>` pattern
  (see `et-uv-pro`), not `radios.d` CAT profiles.
- **CHIRP does not support AnyTone DMR radios.** `anytone-cps` is what
  programs the D578/D890. Don't claim CHIRP covers them.

## Traps that have actually bitten this project

**Kinetic is EOL.** Packages moved to `old-releases.ubuntu.com`. Repoint apt
*before* any apt operation, including inside the chroot. Otherwise every
install fails with "Unable to locate package".

**dconf does not report bad values.** `dconf update` compiles a keyfile
containing an invalid value or a nonexistent key and silently drops it — a
typo is indistinguishable from success. Verify keys with
`gsettings list-keys <schema>` on a real system before writing them. Keys that
were being written here for months and never existed: `power-profile-daemon`,
`enable-battery-saver`, `auto-save-session-timeout`. Booleans must be
`true`/`false` (use `dconf_bool`); doubles need a decimal point
(`dconf_double`); integer keys must not be quoted.

**`pip install chirp` is the wrong package.** PyPI's `chirp` is an unrelated
2013 bioacoustics library. `archive.chirpmyradio.com` serves 403 to
non-browsers. Install CHIRP from `git+https://github.com/kk7ds/chirp.git` into
a venv with `--system-site-packages` (the distro `python3-wxgtk4.0` must be
visible).

**`apt-get install code` can never work on a fresh image.** Ubuntu 22.10
has no `code` package, so the first install is a downloaded `.deb`; its
postinst adds Microsoft's VS Code repo, which handles updates afterwards. The
build removes only the *Edge* repos.

**No `tee` in build commands run under sudo.** It has hung this build. Append
to `$LOG_FILE` with `>>` instead.

**Don't swallow failures.** The pattern `... || true` / `|| log WARN` was used
almost everywhere and hid the fact that VS Code, CHIRP, Edge, the timezone and
all the power settings were never applied. Build-time installs return non-zero
on real failure; `verify_customizations` aborts the build *before* the 20–40
minute squashfs step rather than shipping a known-broken ISO.

**Read a third-party repo's `scripts/`, not just its data directories.**
`lib/customize-addons.sh` spent a release copying et-os-addons' `overlay/`
files while ignoring its nine installer scripts — then its own comments
asserted the repo was "launcher only," and that wrong claim was reused as fact
for months. It cost us a backwards `ENABLE_ETOSADDONS_KIWIX="no"` (the apt
`kiwix` package has a broken webserver, which is what breaks `et-hotspot`;
upstream purges and replaces it) and four hand-rolled installers that went
stale. **A comment in this repo is not evidence. Go read the upstream source.**

**Check what a vendored dependency pins.** et-os-addons' `.gitmodules` pins
`branch = release/r6`, and its `scripts/install.sh` runs ETC's installer from
that submodule — so running it would silently downgrade an R7 build to R6.
Its `scripts/env.sh` also exports `ET_EXPERT=1`, which turns on ETC's Wikipedia
dialog and would block an automated build.

**Check ETC's release notes before adding anything.** ETC ships more every
release, and our customizations can start *fighting* it. R7 enables dark mode
and disables screen dimming natively; our `DIM_SCREEN` default of `true` was
re-enabling the dimming R7 had just turned off. Kiwix has been native since
R4. Release notes:
`https://api.github.com/repos/thetechprepper/emcomm-tools-os-community/releases`

**R7 ships no release assets.** The offline map tilesets live on the **R5**
release only, so the R5 tag hardcoded in the generated `download-et-maps.sh`
is correct — don't "fix" it to R7.

## Working practices

- **Commit, push and open PRs without being asked, at the natural points.**
  Commit when a coherent fix is done and checked (`bash -n`, and a targeted
  test where one is possible); push right after; open a **draft** PR into
  `main` when a branch has work `main` lacks and no PR exists. Every commit
  message and PR description carries notes: what was broken, why, how it was
  fixed, and what was and was not tested. Never merge -- that is the user's
  call -- and never commit `secrets.env`. If a push is refused, say so at once
  with the error rather than leaving work only on the local machine.

- **Read the actual file before changing or diagnosing it.** Most bugs here
  were found by reading the config the code generates, not by reasoning about
  it.
- **Verify in code before suggesting a rebuild.** A full build is 90–120
  minutes; squashfs compression dominates. Never say "it should work."
- **`secrets.env` is gitignored and must never be committed.** It holds a
  Winlink password and WiFi PSKs. `embed_cache_files()` copies it into the
  ISO on purpose, root-only (600), and `seed_cache_from_embedded()` copies it
  back into the repo as the user's own 600 file on the next build -- that is
  how it survives reinstalls. So **a non-minimal ISO is not shareable**. Use
  `-m` for one that is.
- **No file paths in `secrets.env`.** Build inputs (Ubuntu ISO, installer
  .debs, backup archives) go in `cache/`, which is embedded in the ISO and
  linked back automatically. A path into `~/Downloads` does not survive a
  reinstall; that is how the VS Code and GridTracker .debs were lost.
- **Never delete ISOs, build artifacts or user files without asking.**
- **Stop and tell the user when a command needs a sudo password** — they often
  miss the terminal prompt.
- **No summary files.** Report in chat. Update existing docs in place.
- **Don't reinstall what ETC already provides** (Python, ham tools, Wine).
  ETC's Wine prefix is `~/.wine32`, 32-bit, not `~/.wine`.
- Modify ETC's own templates in `/opt/emcomm-tools/conf/template.d/` and keep
  their `{{ET_*}}` placeholders, rather than building a parallel config system.

`.github/copilot-instructions.md` holds the longer-form history behind these
rules, including the USB-writing and troubleshooting-priority notes.

## Validating a change

```bash
bash -n build-etc-iso.sh && bash -n lib/*.sh    # syntax
shellcheck -S warning build-etc-iso.sh lib/*.sh # if installed
./build-etc-iso.sh -l                            # list ETC releases, no root
sudo ./build-etc-iso.sh -r stable -d             # build with debug logging
```

Logs land in `logs/`. The unpacked squashfs is kept at `.work/` after a
failure for inspection.
