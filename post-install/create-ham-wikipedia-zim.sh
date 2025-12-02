#!/bin/bash
#
# Script Name: create-ham-wikipedia-zim.sh
# Description: Download specific Wikipedia articles and create a custom .zim file
#              for offline viewing with Kiwix
# Author: KD7DGF
# Date: 2025-01-xx
#
# Usage: ./create-ham-wikipedia-zim.sh [--articles "Article1|Article2|..."]
#
# Requirements:
#   - zimwriterfs (installed by ETC's install-wikipedia.sh)
#   - wget, curl, python3 with html5lib or beautifulsoup4
#
# This script:
#   1. Downloads Wikipedia articles as HTML
#   2. Creates a proper directory structure for zimwriterfs
#   3. Packages them into a .zim file
#   4. Places the .zim in ~/wikipedia/ for Kiwix to find
#

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${HOME}/wikipedia"
WORK_DIR="/tmp/ham-wikipedia-zim-$$"

# Default ham radio articles - pipe-separated list
DEFAULT_ARTICLES="2-meter_band|70-centimeter_band|General_Mobile_Radio_Service|Family_Radio_Service|Amateur_radio|Amateur_radio_emergency_communications|Automatic_Packet_Reporting_System|Winlink|Digital_mobile_radio|D-STAR|System_Fusion|Shortwave_radio|High_frequency|Very_high_frequency|Ultra_high_frequency|Radio_propagation|Antenna_(radio)|Repeater|Simplex_communication|Duplex_(telecommunications)|Citizens_band_radio|Multi-Use_Radio_Service"

# ZIM metadata
ZIM_TITLE="Ham Radio Wikipedia"
ZIM_DESCRIPTION="Offline Wikipedia articles for amateur radio operators"
ZIM_CREATOR="EmComm Tools Customizer"
ZIM_PUBLISHER="KD7DGF"
ZIM_LANGUAGE="eng"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# Functions
# ============================================================================

log() {
    local level="$1"
    local message="$2"
    case "$level" in
        ERROR)   echo -e "${RED}[ERROR]${NC} $message" >&2 ;;
        WARN)    echo -e "${YELLOW}[WARN]${NC} $message" ;;
        SUCCESS) echo -e "${GREEN}[OK]${NC} $message" ;;
        INFO)    echo -e "${BLUE}[INFO]${NC} $message" ;;
        *)       echo "$message" ;;
    esac
}

cleanup() {
    if [ -d "$WORK_DIR" ]; then
        log INFO "Cleaning up work directory..."
        rm -rf "$WORK_DIR"
    fi
}

trap cleanup EXIT

check_dependencies() {
    local missing=()
    
    # Check for zimwriterfs
    if ! command -v zimwriterfs &>/dev/null; then
        missing+=("zimwriterfs (install with: sudo apt install zim-tools)")
    fi
    
    # Check for wget or curl
    if ! command -v wget &>/dev/null && ! command -v curl &>/dev/null; then
        missing+=("wget or curl")
    fi
    
    # Check for python3
    if ! command -v python3 &>/dev/null; then
        missing+=("python3")
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        log ERROR "Missing dependencies:"
        for dep in "${missing[@]}"; do
            echo "  - $dep"
        done
        echo ""
        echo "On ETC, run install-wikipedia.sh first to get zimwriterfs."
        exit 1
    fi
}

download_article() {
    local article="$1"
    local output_file="$2"
    
    # Use Wikipedia's REST API for clean HTML
    local api_url="https://en.wikipedia.org/api/rest_v1/page/html/${article}"
    
    log INFO "Downloading: $article"
    
    if command -v wget &>/dev/null; then
        wget -q -O "$output_file" "$api_url" 2>/dev/null || return 1
    else
        curl -sL -o "$output_file" "$api_url" || return 1
    fi
    
    # Check if we got a valid HTML file
    if [ ! -s "$output_file" ]; then
        log WARN "Empty response for $article"
        return 1
    fi
    
    # Check for error response
    if grep -q '"httpCode"' "$output_file" 2>/dev/null; then
        log WARN "Article not found: $article"
        rm -f "$output_file"
        return 1
    fi
    
    return 0
}

create_index_html() {
    local html_dir="$1"
    local articles_file="$2"
    
    log INFO "Creating index page..."
    
    cat > "${html_dir}/index.html" <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Ham Radio Wikipedia - Offline Reference</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
            background: #f5f5f5;
            color: #333;
        }
        h1 { color: #1a5f7a; border-bottom: 2px solid #1a5f7a; padding-bottom: 10px; }
        h2 { color: #2c3e50; margin-top: 30px; }
        .article-list { list-style: none; padding: 0; }
        .article-list li { 
            margin: 8px 0; 
            padding: 10px 15px;
            background: white;
            border-radius: 5px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
        }
        .article-list a { 
            text-decoration: none; 
            color: #0366d6;
            font-weight: 500;
        }
        .article-list a:hover { text-decoration: underline; }
        .category { margin-bottom: 20px; }
        .footer {
            margin-top: 40px;
            padding-top: 20px;
            border-top: 1px solid #ddd;
            font-size: 0.9em;
            color: #666;
        }
    </style>
</head>
<body>
    <h1>📻 Ham Radio Wikipedia</h1>
    <p>Offline Wikipedia articles for amateur radio operators and emergency communications.</p>
    
    <h2>Radio Services</h2>
    <ul class="article-list">
EOF

    # Add article links - categorized
    local services=(2-meter_band 70-centimeter_band Amateur_radio General_Mobile_Radio_Service Family_Radio_Service Citizens_band_radio Multi-Use_Radio_Service)
    local digital=(Automatic_Packet_Reporting_System Winlink Digital_mobile_radio D-STAR System_Fusion)
    local technical=(High_frequency Very_high_frequency Ultra_high_frequency Radio_propagation Antenna_\(radio\) Repeater Simplex_communication Duplex_\(telecommunications\) Shortwave_radio)
    local emcomm=(Amateur_radio_emergency_communications)
    
    # List all downloaded articles
    for article in "${html_dir}"/*.html; do
        [ -f "$article" ] || continue
        local basename=$(basename "$article" .html)
        [ "$basename" = "index" ] && continue
        local display_name="${basename//_/ }"
        echo "        <li><a href=\"${basename}.html\">${display_name}</a></li>" >> "${html_dir}/index.html"
    done
    
    cat >> "${html_dir}/index.html" <<'EOF'
    </ul>
    
    <div class="footer">
        <p>Generated by EmComm Tools Customizer for offline use with Kiwix.</p>
        <p>Content from Wikipedia, licensed under CC BY-SA.</p>
    </div>
</body>
</html>
EOF
}

create_metadata() {
    local html_dir="$1"
    
    log INFO "Creating metadata files..."
    
    # Create favicon (simple placeholder)
    # In a real implementation, you'd include a proper favicon
    echo "" > "${html_dir}/favicon.png"
}

build_zim() {
    local html_dir="$1"
    local output_file="$2"
    
    log INFO "Building .zim file with zimwriterfs..."
    
    # zimwriterfs expects a specific structure
    # HTML files should be in the root with an index.html as welcome page
    
    zimwriterfs \
        --welcome "index.html" \
        --favicon "favicon.png" \
        --language "$ZIM_LANGUAGE" \
        --title "$ZIM_TITLE" \
        --description "$ZIM_DESCRIPTION" \
        --creator "$ZIM_CREATOR" \
        --publisher "$ZIM_PUBLISHER" \
        "$html_dir" \
        "$output_file"
    
    return $?
}

# ============================================================================
# Main
# ============================================================================

main() {
    local articles="$DEFAULT_ARTICLES"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --articles)
                articles="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [--articles \"Article1|Article2|...\"]"
                echo ""
                echo "Downloads Wikipedia articles and creates a .zim file for Kiwix."
                echo ""
                echo "Options:"
                echo "  --articles    Pipe-separated list of Wikipedia article names"
                echo "  --help        Show this help message"
                echo ""
                echo "Default articles: ham radio bands, APRS, Winlink, DMR, etc."
                exit 0
                ;;
            *)
                log ERROR "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    log INFO "=== Ham Radio Wikipedia ZIM Creator ==="
    echo ""
    
    # Check dependencies
    check_dependencies
    
    # Create directories
    mkdir -p "$OUTPUT_DIR"
    mkdir -p "$WORK_DIR/html"
    
    # Convert pipe-separated list to array
    IFS='|' read -ra article_array <<< "$articles"
    
    log INFO "Downloading ${#article_array[@]} Wikipedia articles..."
    echo ""
    
    local downloaded=0
    local failed=0
    
    for article in "${article_array[@]}"; do
        # Clean up article name (trim whitespace)
        article="${article#"${article%%[![:space:]]*}"}"
        article="${article%"${article##*[![:space:]]}"}"
        
        if [ -z "$article" ]; then
            continue
        fi
        
        local output_file="${WORK_DIR}/html/${article}.html"
        
        if download_article "$article" "$output_file"; then
            ((downloaded++))
        else
            ((failed++))
        fi
        
        # Be nice to Wikipedia servers
        sleep 0.5
    done
    
    echo ""
    log INFO "Downloaded: $downloaded, Failed: $failed"
    
    if [ $downloaded -eq 0 ]; then
        log ERROR "No articles downloaded successfully!"
        exit 1
    fi
    
    # Create index and metadata
    create_index_html "${WORK_DIR}/html"
    create_metadata "${WORK_DIR}/html"
    
    # Build the .zim file
    local zim_file="${OUTPUT_DIR}/ham-radio-wikipedia_$(date +%Y%m).zim"
    
    if build_zim "${WORK_DIR}/html" "$zim_file"; then
        log SUCCESS "Created: $zim_file"
        log INFO "File size: $(du -h "$zim_file" | cut -f1)"
        echo ""
        echo "To view in Kiwix:"
        echo "  kiwix-serve --port=8080 '$zim_file'"
        echo "  Then open: http://localhost:8080"
    else
        log ERROR "Failed to build .zim file"
        log WARN "zimwriterfs may not be installed. Run ETC's install-wikipedia.sh first."
        
        # Fallback: just keep the HTML files
        log INFO "Keeping HTML files in: ${OUTPUT_DIR}/ham-radio-html/"
        mv "${WORK_DIR}/html" "${OUTPUT_DIR}/ham-radio-html"
        log SUCCESS "HTML articles saved to: ${OUTPUT_DIR}/ham-radio-html/"
        echo ""
        echo "Open ${OUTPUT_DIR}/ham-radio-html/index.html in a browser to view."
    fi
}

main "$@"
