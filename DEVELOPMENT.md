# Future Development Tracking (v2.0+)

This document tracks all work planned for future releases. All items are tracked as GitHub Issues for accountability and progress tracking.

## v2.0 Roadmap (Priority Order)

### 🔴 HIGH PRIORITY - v2.0

#### 1. **Preseed File for Automated Ubuntu Installer**
- **Issue**: #8 (v2.0 PRIORITY)
- **Severity**: HIGH
- **Impact**: Eliminates manual hostname/user entry prompt
- **Target**: v2.0.0
- **Status**: NOT STARTED
- **Acceptance Criteria**:
  - [ ] Preseed file generated from secrets.env variables
  - [ ] ISO boots with zero manual prompts
  - [ ] Hostname set correctly from MACHINE_NAME
  - [ ] User account created with correct username/password
  - [ ] Tested on real hardware
  - [ ] Documentation updated
- **Estimated Effort**: 3-5 days
- **Links**: 
  - v1.0 Known Limitation: Hostname/user account not automated
  - RELEASE_v1.0.0.md

#### 2. **Build Log Preservation & Embedding**
- **Issue**: #7
- **Severity**: MEDIUM
- **Impact**: Better debugging for customization issues
- **Target**: v2.0.0
- **Status**: NOT STARTED
- **Acceptance Criteria**:
  - [ ] Build logs copied to ISO cache directory
  - [ ] Logs accessible post-install at `~/.emcomm-customizer/logs/`
  - [ ] Log manifest/summary generated
  - [ ] Old logs cleaned up to prevent bloat
  - [ ] Build log review documented in README
- **Estimated Effort**: 2-3 days
- **Links**:
  - v1.0 Known Issue: Logs not carried forward
  - User verified: WiFi worked but needed diagnostic logs

#### 3. **WiFi Network Connection Validation & Troubleshooting**
- **Issue**: #3
- **Severity**: MEDIUM
- **Impact**: Help diagnose WiFi connection failures
- **Target**: v2.0.0 or v2.1
- **Status**: NOT STARTED
- **Acceptance Criteria**:
  - [ ] WiFi credential validation in build
  - [ ] Enhanced logging for each network
  - [ ] Post-install diagnostic script
  - [ ] WiFi connection test utility
  - [ ] Troubleshooting guide in README
  - [ ] Test with various WiFi network types
- **Estimated Effort**: 2-4 days
- **Links**:
  - v1.0 Issue: One WiFi network failed (possibly password issue)
  - Related: Build log preservation

#### 4. **Post-Install Script for First-Boot Customizations**
- **Issue**: #2
- **Severity**: MEDIUM
- **Impact**: Automate anything that can't be done during ISO build
- **Target**: v2.0.0
- **Status**: NOT STARTED
- **Acceptance Criteria**:
  - [ ] Post-install script created (`post-install/setup-after-installer.sh`)
  - [ ] Reads secrets.env from `/opt/emcomm-customizer-cache/`
  - [ ] Applies all deferred customizations
  - [ ] Generates verification report
  - [ ] Documented in README with step-by-step instructions
  - [ ] Tested on real hardware
- **Estimated Effort**: 2-3 days
- **Links**:
  - Complements: Preseed file automation

---

### 🟡 MEDIUM PRIORITY - v2.1+

#### 5. **Anytone D578UV CAT Control Integration**
- **Issue**: #6
- **Severity**: MEDIUM
- **Impact**: Automatic radio control setup for D578UV
- **Target**: v2.1
- **Status**: NOT STARTED
- **Acceptance Criteria**:
  - [ ] D578UV VID/PID documented
  - [ ] udev rule created and tested
  - [ ] rigctld configuration auto-generated
  - [ ] systemd service implemented
  - [ ] Tested with actual D578UV hardware
  - [ ] Documentation with troubleshooting guide
- **Estimated Effort**: 3-5 days
- **Prerequisites**: D578UV hardware available for testing
- **Links**:
  - Part of: Radio integration improvements
  - Related: #4 (USB radio auto-detection)

#### 6. **USB Radio Auto-Detection for CAT Control Setup**
- **Issue**: #4
- **Severity**: MEDIUM
- **Impact**: Generic framework for multiple radio types
- **Target**: v2.1+
- **Status**: NOT STARTED
- **Acceptance Criteria**:
  - [ ] Radio VID/PID database created and documented
  - [ ] Auto-detection logic implemented and tested
  - [ ] Rigctld config generation for multiple models
  - [ ] udev rules for common radios
  - [ ] Tested with 3+ radio models
  - [ ] Documentation with supported radios list
- **Estimated Effort**: 5-8 days
- **Prerequisites**: 
  - Multiple radio models available for testing
  - Research on radio VID/PID values
- **Supported Radios (TODO)**:
  - [ ] Anytone D578UV (D-Star capable)
  - [ ] Yaesu FT-991A, FT-891, FT-450D
  - [ ] Icom IC-7100, IC-705
  - [ ] Others: Kenwood, Elecraft, etc.
- **Links**:
  - Depends on: #6 (D578UV as first implementation)

#### 7. **GPS Auto-Detection for Grid Square Calculation**
- **Issue**: #5
- **Severity**: LOW-MEDIUM
- **Impact**: Automatic location updates for APRS beaconing
- **Target**: v2.1+
- **Status**: NOT STARTED
- **Acceptance Criteria**:
  - [ ] GPS device auto-detection implemented
  - [ ] Maidenhead grid calculation tested and accurate
  - [ ] gpsd integration working
  - [ ] Systemd service for continuous updates
  - [ ] Tested with multiple GPS devices
  - [ ] Documentation with GPS hardware recommendations
- **Estimated Effort**: 3-4 days
- **Prerequisites**: GPS hardware for testing
- **Links**:
  - Complements: APRS configuration

---

## Known Issues Requiring Documentation Updates

These are current gaps discovered in v1.0 that should be documented:

1. **Build Log Preservation**
   - Currently: NOT implemented (discovered Dec 9, 2025)
   - Workaround: Keep logs locally for review
   - Fix: Issue #7

2. **WiFi Network Connection Failures**
   - Symptoms: One network may fail to connect (password issue suspected)
   - Diagnosis: No build logs embedded for troubleshooting
   - Fix: Issue #7 + Issue #3

3. **Hostname/User Account Automation**
   - Current: Manual Ubuntu installer entry required
   - Workaround: Users set values manually during first boot
   - Fix: Issue #8 (Preseed file)

---

## v1.0 Status Summary

### ✅ Working Features
- Build process automation via xorriso/squashfs
- WiFi pre-configuration (verified working, one network had issues)
- APRS direwolf templates
- Desktop settings (dark mode, scaling, accessibility, power, timezone)
- Git configuration
- VARA license setup
- Development packages (git, nodejs, npm, uv)
- Cache system for faster rebuilds

### ⚠️ Known Limitations
- Hostname & user account require manual Ubuntu installer entry
- Build logs not preserved/embedded
- No WiFi troubleshooting/validation tools
- No post-install verification script

---

## Release Timeline (Estimated)

- **v1.0.0** (Released Dec 9, 2025): First working build
- **v2.0.0** (Target: Q1 2026): Preseed automation + log preservation + WiFi validation + post-install script
- **v2.1.0** (Target: Q2 2026): Radio CAT control + GPS integration
- **v3.0.0** (Target: Q3 2026+): Additional radio models, advanced features

---

## How to Track Progress

1. **View all issues**: https://github.com/AlwaysLearningTech/emcomm-tools-customizer/issues
2. **Filter by label**: `v2.0`, `v2.1`, `high-priority`, etc.
3. **Use GitHub Projects** (optional): Create board for sprint planning
4. **Update issues** as work progresses

Each issue has:
- Clear description of what needs to be done
- Acceptance criteria for completion
- Estimated effort
- Related issues/dependencies
- Prerequisites if applicable

---

**Last Updated**: December 9, 2025  
**v1.0.0 Release**: Complete  
**v2.0.0 Development**: Ready to begin
