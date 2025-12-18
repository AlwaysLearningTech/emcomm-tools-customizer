#!/bin/bash
#
# Post-Install Customization Verification Script
# Run this after the Ubuntu installer completes and system boots
# Verifies all customizations from the build were applied correctly
#
# Usage: ./01-verify-customizations.sh
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

echo -e "${BLUE}=== EmComm Tools Post-Install Verification ===${NC}"
echo ""

# Helper functions
check_pass() {
    echo -e "${GREEN}✓${NC} $1"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    CHECKS_WARNING=$((CHECKS_WARNING + 1))
}

# ============================================================================
# System Checks
# ============================================================================

echo -e "${BLUE}1. System Configuration${NC}"

# Check hostname
if [ -f /etc/hostname ]; then
    HOSTNAME=$(cat /etc/hostname)
    if [[ "$HOSTNAME" == "ETC-"* ]] || [[ "$HOSTNAME" == "localhost" ]]; then
        check_pass "Hostname: $HOSTNAME"
    else
        check_warn "Hostname set to: $HOSTNAME (may not match expected pattern)"
    fi
else
    check_fail "Hostname file not found"
fi

# Check timezone
if timedatectl | grep -q "Time zone"; then
    TZ=$(timedatectl | grep "Time zone" | awk '{print $3}')
    check_pass "Timezone: $TZ"
else
    check_fail "Unable to determine timezone"
fi

# Check locale
if locale | grep -q "LANG="; then
    LOCALE=$(locale | grep "LANG=" | cut -d= -f2)
    check_pass "Locale: $LOCALE"
else
    check_warn "Unable to determine locale"
fi

# ============================================================================
# ETC Installation Checks
# ============================================================================

echo ""
echo -e "${BLUE}2. EmComm Tools Installation${NC}"

# Check if ETC is installed
if [ -d /opt/emcomm-tools ]; then
    check_pass "EmComm Tools directory exists"
else
    check_fail "EmComm Tools not found at /opt/emcomm-tools"
fi

# Check for key ETC tools
for tool in direwolf pat fldigi; do
    if command -v $tool &>/dev/null; then
        check_pass "Found $tool"
    else
        check_warn "Tool not found: $tool"
    fi
done

# Check ETC user config
if [ -f ~/.config/emcomm-tools/user.json ]; then
    check_pass "User configuration file exists"
    if grep -q "callsign" ~/.config/emcomm-tools/user.json; then
        CALLSIGN=$(jq -r '.callsign' ~/.config/emcomm-tools/user.json)
        check_pass "Callsign configured: $CALLSIGN"
    else
        check_warn "Callsign not set in user.json"
    fi
else
    check_warn "User configuration not found (will be created on first run)"
fi

# ============================================================================
# WiFi Configuration Checks
# ============================================================================

echo ""
echo -e "${BLUE}3. WiFi Configuration${NC}"

if [ -d /etc/NetworkManager/system-connections ]; then
    WIFI_COUNT=$(find /etc/NetworkManager/system-connections -name "*.nmconnection" -type f 2>/dev/null | wc -l)
    if [ $WIFI_COUNT -gt 0 ]; then
        check_pass "Found $WIFI_COUNT WiFi network(s) configured"
        find /etc/NetworkManager/system-connections -name "*.nmconnection" -type f -exec basename {} \; | sed 's/\.nmconnection$//' | while read -r net; do
            echo "   - $net"
        done
    else
        check_warn "No WiFi networks configured"
    fi
else
    check_fail "NetworkManager connections directory not found"
fi

# Check NetworkManager status
if systemctl is-active --quiet NetworkManager; then
    check_pass "NetworkManager is running"
else
    check_warn "NetworkManager is not running - attempting to start..."
    sudo systemctl start NetworkManager 2>/dev/null && check_pass "NetworkManager started" || check_fail "Could not start NetworkManager"
fi

# ============================================================================
# APRS Configuration Checks
# ============================================================================

echo ""
echo -e "${BLUE}4. APRS Configuration${NC}"

DIREWOLF_TEMPLATE="/opt/emcomm-tools/conf/template.d/packet/direwolf.aprs-digipeater.conf"
if [ -f "$DIREWOLF_TEMPLATE" ]; then
    check_pass "Direwolf APRS template exists"
    
    if grep -q "MYCALL.*=" "$DIREWOLF_TEMPLATE"; then
        check_pass "Direwolf template configured"
    else
        check_warn "Direwolf template may not be customized"
    fi
else
    check_fail "Direwolf template not found"
fi

# Check for APRS iGate setting
if grep -q "IGSERVER" "$DIREWOLF_TEMPLATE" 2>/dev/null; then
    check_pass "APRS iGate configured"
else
    check_warn "APRS iGate not explicitly configured"
fi

# ============================================================================
# Desktop Configuration Checks
# ============================================================================

echo ""
echo -e "${BLUE}5. Desktop Configuration${NC}"

if dconf read /org/gnome/desktop/interface/gtk-theme &>/dev/null; then
    THEME=$(dconf read /org/gnome/desktop/interface/gtk-theme)
    if [[ "$THEME" == *"dark"* ]]; then
        check_pass "Dark mode enabled: $THEME"
    else
        check_warn "Theme: $THEME (not dark)"
    fi
else
    check_warn "Unable to read GNOME theme setting"
fi

# Check scaling
if dconf read /org/gnome/desktop/interface/scaling-factor &>/dev/null; then
    SCALE=$(dconf read /org/gnome/desktop/interface/scaling-factor)
    check_pass "Desktop scaling: $SCALE"
else
    check_warn "Unable to read scaling factor"
fi

# ============================================================================
# Additional Packages
# ============================================================================

echo ""
echo -e "${BLUE}6. Development Packages${NC}"

for pkg in git nodejs npm uv chirp; do
    if command -v $pkg &>/dev/null; then
        check_pass "Package installed: $pkg"
    else
        check_warn "Package not found: $pkg"
    fi
done

# ============================================================================
# Build Logs & Documentation
# ============================================================================

echo ""
echo -e "${BLUE}7. Build Logs & Documentation${NC}"

if [ -d /opt/emcomm-customizer-cache/logs ]; then
    LOG_COUNT=$(find /opt/emcomm-customizer-cache/logs -name "*.log" -type f 2>/dev/null | wc -l)
    check_pass "Build logs found: $LOG_COUNT file(s)"
    
    if [ -f /opt/emcomm-customizer-cache/logs/BUILD_MANIFEST.txt ]; then
        check_pass "Build manifest available"
    else
        check_warn "Build manifest not found"
    fi
else
    check_warn "Build logs not found (embed was skipped)"
fi

# ============================================================================
# Post-Install Tools
# ============================================================================

echo ""
echo -e "${BLUE}8. Post-Install Tools${NC}"

for script in wifi-diagnostics.sh validate-wifi-config.sh; do
    if [ -f ~/add-ons/network/$script ]; then
        check_pass "Found: $script"
    else
        check_warn "Missing: $script"
    fi
done

for script in download-resources.sh create-ham-wikipedia-zim.sh; do
    if [ -f ~/add-ons/wikipedia/$script ]; then
        check_pass "Found: $script"
    else
        check_warn "Missing: $script"
    fi
done

# ============================================================================
# Summary & Recommendations
# ============================================================================

echo ""
echo -e "${BLUE}=== Verification Summary ===${NC}"
echo "Passed:  ${GREEN}$CHECKS_PASSED${NC}"
echo "Failed:  ${RED}$CHECKS_FAILED${NC}"
echo "Warning: ${YELLOW}$CHECKS_WARNING${NC}"
echo ""

if [ $CHECKS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All critical checks passed!${NC}"
else
    echo -e "${RED}✗ Some checks failed. Review above and troubleshoot as needed.${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}=== Next Steps ===${NC}"
echo ""
echo "1. Check build logs for configuration details:"
echo "   mkdir -p ~/.emcomm-customizer/logs"
echo "   cp /opt/emcomm-customizer-cache/logs/* ~/.emcomm-customizer/logs/"
echo "   less ~/.emcomm-customizer/logs/BUILD_MANIFEST.txt"
echo ""
echo "2. Verify WiFi connectivity:"
echo "   ~/add-ons/network/wifi-diagnostics.sh"
echo ""
echo "3. Test APRS configuration:"
echo "   direwolf -c /opt/emcomm-tools/conf/template.d/packet/direwolf.aprs-digipeater.conf"
echo ""
echo "4. Download offline resources (optional, ~500MB):"
echo "   ~/add-ons/wikipedia/download-resources.sh"
echo ""
echo "5. For VARA HF/FM installation:"
echo "   ~/add-ons/wine/01-install-wine-deps.sh"
echo "   ~/add-ons/wine/02-install-vara-hf.sh"
echo "   ~/add-ons/wine/03-install-vara-fm.sh"
echo "   ~/add-ons/wine/99-import-vara-licenses.sh"
echo ""
echo "Documentation: https://github.com/AlwaysLearningTech/emcomm-tools-customizer"
echo ""
