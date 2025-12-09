# v1.0.0 Release - December 9, 2025

## 🎉 Release Summary

**emcomm-tools-customizer v1.0.0** is the first production release with a fully working build process for customized ETC ISO images.

### Build Status

| Component | Status | Details |
|-----------|--------|---------|
| ISO Build Process | ✅ Working | Fully automated via xorriso/squashfs |
| WiFi Configuration | ✅ Working | Networks pre-configured, auto-connect enabled |
| APRS Setup | ✅ Working | direwolf templates customized for iGate/beacon |
| Desktop Settings | ✅ Working | Dark mode, scaling, accessibility, power, timezone |
| Git Config | ✅ Working | User name/email pre-populated |
| VARA License | ✅ Working | .reg files and import script created |
| Dev Packages | ✅ Working | git, nodejs, npm, uv installable |
| **Hostname/User Account** | ⚠️ Manual | Ubuntu installer prompts override pre-config |

### What You Get

When you build an ISO with v1.0.0:

1. **Automatic on first boot:**
   - WiFi networks connect automatically
   - APRS direwolf ready with iGate/beacon
   - Desktop dark mode, scaling, power management applied
   - VARA license files ready in ~/add-ons/wine/
   - Git configured with your name/email
   - Additional dev tools (git, nodejs, npm, uv) installed

2. **Manual during Ubuntu installer:**
   - Set hostname (prompted by Ubuntu)
   - Create user account (prompted by Ubuntu)
   - Everything else is automated

### Known Limitation

The Ubuntu 22.10 installer runs after ISO boot and **overwrites** our pre-configured hostname and user account settings. This is a fundamental limitation of how the Ubuntu installer works—it re-initializes these values during first-run setup.

**Workaround:** Users must manually enter hostname and username one time during the Ubuntu installer. All other customizations apply automatically afterward.

### Version 2.0 Priority

The #1 priority for v2.0 is **preseed file integration**, which will:
- Fully automate the Ubuntu installer with pre-configured values
- Eliminate all manual prompts
- Create a true zero-interaction build-to-boot workflow

### Testing

This release was tested on live hardware and verified:
- ✅ Custom ISO builds successfully
- ✅ WiFi networks auto-connect on first boot
- ✅ APRS direwolf templates ready for use
- ✅ Desktop settings applied correctly
- ✅ ETC tools (direwolf, pat, fldigi, js8call) functional
- ✅ Callsign, grid, Winlink password pre-populated

### Installation

```bash
# Quick start
git clone https://github.com/AlwaysLearningTech/emcomm-tools-customizer.git
cd emcomm-tools-customizer
cp secrets.env.template secrets.env
# Edit secrets.env with your callsign, WiFi, APRS settings...
sudo ./build-etc-iso.sh -r stable

# Output: output/<release>-custom.iso
```

See [README.md](README.md) for complete documentation.

### Commits in This Release

- `e5349eb` - v1.0.0: First working build release
- `f3f3f20` - Move uv to ADDITIONAL_PACKAGES as standard code dependency
- `f76dfaa` - Add uv package manager installation support
- `b7cd152` - Remove VS Code from default packages (unavailable in EOL Ubuntu 22.10)
- `bf20fe6` - Embed secrets.env in ISO and add size estimation report

### What's Next

v2.0 development will focus on:
1. **Preseed file** - Fully automated Ubuntu installer (HIGH PRIORITY)
2. GPS auto-detection for grid square
3. D578 CAT control integration
4. Radio auto-detection for USB devices

---

**Release Date:** December 9, 2025  
**Tested On:** Ubuntu 22.10 (ETC)  
**Build Hardware:** Standard x86-64 system with 15GB+ free space  
**Build Time:** ~30-45 minutes (depending on internet speed and hardware)

**73 de KD7DGF** 📻
