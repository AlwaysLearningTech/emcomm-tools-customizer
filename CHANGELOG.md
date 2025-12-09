# Changelog

All notable changes to this project will be documented in this file.

## [v1.0.0] - 2025-12-09

### First Working Build Release ✨

This is the first release with a fully functional ISO build process. Users can now create customized ETC ISOs with their WiFi, APRS, desktop, and system settings pre-configured.

### Added

- **Core build script** (`build-etc-iso.sh`): Fully automated ETC ISO customization using xorriso/squashfs
- **WiFi configuration**: Pre-configured WiFi networks with auto-connect support
- **APRS customization**: Modified direwolf templates for iGate and beaconing
- **Desktop preferences**: Dark mode, scaling, accessibility, display management
- **Power management**: Sleep behavior, power profiles, idle timeouts
- **System timezone**: User-configurable timezone
- **Git configuration**: Pre-populated user name/email for commits
- **VARA license support**: `.reg` files and import scripts for post-install setup
- **Additional packages**: git, nodejs, npm, uv installable via configuration
- **Release modes**: Support for stable, latest, and specific tag builds
- **Cache system**: Persistent caching of downloaded ISOs for faster rebuilds
- **Build logging**: Detailed logs in `./logs/` for debugging
- **Minimal build option** (`-m`): Smaller ISOs without embedded cache files

### Known Limitations

- **Hostname & user account not automated** ⚠️
  - Ubuntu installer prompts override pre-configured values
  - Users must manually enter hostname and username during first boot
  - All other customizations (WiFi, APRS, desktop, etc.) apply automatically
  - **v2.0 priority**: Preseed file to fully automate Ubuntu installer

### Configuration

- Template-based configuration via `secrets.env`
- Support for multiple WiFi networks with auto-connect
- APRS symbol and comment customization
- VARA FM/HF license pre-staging
- Pat Winlink alias setup
- Comprehensive documentation with examples

### Testing

- Successfully builds custom ETC ISOs on Ubuntu 22.10
- Verified WiFi configuration, APRS templates, desktop settings in installed system
- ETC tools (direwolf, pat, fldigi, js8call) function correctly

## [v2.0.0] - Future

### Planned

- **Preseed file support** (HIGH PRIORITY)
  - Fully automated Ubuntu installer
  - Pre-configured hostname and user account
  - Zero-prompt build-to-boot workflow
- **D578 CAT Control**: Anytone D578UV radio integration
- **GPS Auto-Detection**: Automatic grid square calculation
- **Radio Auto-Detection**: USB device detection for CAT control

---

**Note**: v1.0 is production-ready for users who are comfortable with a one-time Ubuntu installer prompt.
The v2.0 preseed feature will eliminate this step entirely for future releases.
