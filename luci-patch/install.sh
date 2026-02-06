#!/bin/sh
# LuCI-App-2FA Authentication Plugin Mechanism Installation Script
# This script downloads and applies patches from GitHub via jsdelivr CDN
# Repository: https://github.com/Tokisaki-Galaxy/luci-app-2fa
# Author: Tokisaki-Galaxy
# License: Apache 2.0

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# GitHub repository info
REPO_OWNER="Tokisaki-Galaxy"
REPO_NAME="luci-app-2fa"
BRANCH="main"
BASE_URL="https://cdn.jsdelivr.net/gh/${REPO_OWNER}/${REPO_NAME}@${BRANCH}/luci-patch/patch"

# Patch file list (source_file|target_path pairs)
PATCH_FILES="
dispatcher.uc|/usr/share/ucode/luci/dispatcher.uc
sysauth.ut|/usr/share/ucode/luci/template/sysauth.ut
bootstrap-sysauth.ut|/usr/share/ucode/luci/template/themes/bootstrap/sysauth.ut
luci-mod-system.json|/usr/share/luci/menu.d/luci-mod-system.json
luci|/usr/share/rpcd/ucode/luci
luci-base.json|/usr/share/rpcd/acl.d/luci-base.json
view/system/exauth.js|/www/luci-static/resources/view/system/exauth.js
"

print_header() {
    echo "${BLUE}========================================${NC}"
    echo "${BLUE}   LuCI-App-2FA Patch Installer${NC}"
    echo "${BLUE}========================================${NC}"
    echo ""
}

print_success() {
    echo "${GREEN}✓${NC} $1"
}

print_error() {
    echo "${RED}✗${NC} $1"
}

print_warning() {
    echo "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo "${BLUE}ℹ${NC} $1"
}

check_openwrt_version() {
    print_info "Checking OpenWrt version..."
    
    if [ ! -f /etc/openwrt_release ]; then
        print_error "This script must be run on OpenWrt system"
        exit 1
    fi
    
    . /etc/openwrt_release
    
    local version="${DISTRIB_RELEASE}"
    local major_version=$(echo "$version" | cut -d'.' -f1)
    local minor_version=$(echo "$version" | cut -d'.' -f2)
    
    print_info "Detected OpenWrt version: ${version}"
    
    # Check if version >= 23.05
    if [ "$major_version" -lt 23 ]; then
        print_error "OpenWrt version must be 23.05 or higher"
        print_error "Current version: ${version}"
        exit 1
    elif [ "$major_version" -eq 23 ] && [ "$minor_version" -lt 5 ]; then
        print_error "OpenWrt version must be 23.05 or higher"
        print_error "Current version: ${version}"
        exit 1
    fi
    
    print_success "OpenWrt version check passed (${version})"
}

check_dependencies() {
    print_info "Checking dependencies..."
    
    local missing_deps=""
    
    for cmd in curl opkg; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps="${missing_deps} ${cmd}"
        fi
    done
    
    if [ -n "$missing_deps" ]; then
        print_error "Missing required commands:${missing_deps}"
        exit 1
    fi
    
    print_success "All dependencies found"
}

list_patch_files() {
    echo ""
    print_info "The following patch files will be installed:"
    echo ""
    
    local index=1
    echo "$PATCH_FILES" | while IFS='|' read -r file target; do
        [ -z "$file" ] && continue
        printf "  ${YELLOW}%2d.${NC} %-30s => %s\n" "$index" "$file" "$target"
        index=$((index + 1))
    done
    
    echo ""
}

ask_confirmation() {
    echo ""
    print_warning "This script will modify system files in /usr/share and /www directories."
    print_warning "It is recommended to backup your system before proceeding."
    echo ""
    
    printf "${YELLOW}Do you want to continue? [y/N]:${NC} "
    read -r response
    
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            print_info "Installation cancelled by user"
            exit 0
            ;;
    esac
}

backup_file() {
    local file="$1"
    
    if [ -f "$file" ]; then
        local backup_file="${file}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$file" "$backup_file"
        print_info "Backed up: $file -> $backup_file"
    fi
}

download_and_install_patches() {
    print_info "Downloading and installing patch files..."
    echo ""
    
    local temp_dir="/tmp/luci-app-2fa-patches"
    mkdir -p "$temp_dir"
    
    echo "$PATCH_FILES" | while IFS='|' read -r file target; do
        [ -z "$file" ] && continue
        
        local url="${BASE_URL}/${file}"
        local temp_file="${temp_dir}/$(basename "$file")"
        
        print_info "Processing: $file"
        
        # Create target directory if it doesn't exist
        local target_dir=$(dirname "$target")
        mkdir -p "$target_dir"
        
        # Backup existing file
        backup_file "$target"
        
        # Download file
        if curl -fsSL "$url" -o "$temp_file"; then
            # Install file
            cp "$temp_file" "$target"
            chmod 644 "$target"
            print_success "Installed: $target"
        else
            print_error "Failed to download: $url"
            print_error "Installation incomplete. Please check your internet connection."
            exit 1
        fi
    done
    
    # Cleanup
    rm -rf "$temp_dir"
    
    echo ""
    print_success "All patch files installed successfully"
}

restart_services() {
    print_info "Restarting services..."
    
    # Clear LuCI cache
    rm -f /tmp/luci-indexcache* 2>/dev/null || true
    print_success "Cleared LuCI cache"
    
    # Restart rpcd
    /etc/init.d/rpcd restart >/dev/null 2>&1
    print_success "Restarted rpcd service"
    
    # Restart uhttpd (optional, may not always be necessary)
    if [ -f /etc/init.d/uhttpd ]; then
        /etc/init.d/uhttpd restart >/dev/null 2>&1
        print_success "Restarted uhttpd service"
    fi
}

print_post_install_info() {
    echo ""
    print_header
    print_success "Installation completed successfully!"
    echo ""
    print_info "What's next:"
    echo ""
    echo "  1. Install luci-app-2fa package:"
    echo "     ${GREEN}wget https://tokisaki-galaxy.github.io/luci-app-2fa/all/key-build.pub -O /tmp/key-build.pub${NC}"
    echo "     ${GREEN}opkg-key add /tmp/key-build.pub${NC}"
    echo "     ${GREEN}echo 'src/gz luci-app-2fa https://tokisaki-galaxy.github.io/luci-app-2fa/all' >> /etc/opkg/customfeeds.conf${NC}"
    echo "     ${GREEN}opkg update${NC}"
    echo "     ${GREEN}opkg install luci-app-2fa${NC}"
    echo ""
    echo "  2. Access LuCI and navigate to:"
    echo "     ${BLUE}System → Administration → Authentication${NC}"
    echo ""
    echo "  3. Configure 2FA at:"
    echo "     ${BLUE}System → 2-Factor Auth${NC}"
    echo ""
    print_info "For more information, visit:"
    echo "  https://github.com/${REPO_OWNER}/${REPO_NAME}"
    echo ""
}

# Main installation flow
main() {
    print_header
    
    check_openwrt_version
    check_dependencies
    list_patch_files
    ask_confirmation
    
    echo ""
    download_and_install_patches
    restart_services
    print_post_install_info
}

# Run main function
main
