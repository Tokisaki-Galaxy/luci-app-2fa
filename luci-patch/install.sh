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

# Global variable for auto-confirm mode
AUTO_CONFIRM=0

# GitHub repository info
REPO_OWNER="Tokisaki-Galaxy"
REPO_NAME="luci-app-2fa"
BRANCH="master"
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
    printf "${BLUE}========================================${NC}\n"
    printf "${BLUE}   LuCI-App-2FA Patch Installer${NC}\n"
    printf "${BLUE}========================================${NC}\n"
    printf "\n"
}

print_success() {
    printf "${GREEN}✓${NC} %s\n" "$1"
}

print_error() {
    printf "${RED}✗${NC} %s\n" "$1"
}

print_warning() {
    printf "${YELLOW}⚠${NC} %s\n" "$1"
}

print_info() {
    printf "${BLUE}ℹ${NC} %s\n" "$1"
}

show_usage() {
    printf "Usage: %s [OPTIONS]\n" "$0"
    printf "\n"
    printf "Options:\n"
    printf "  -y, --yes          Auto-confirm installation (skip confirmation prompt)\n"
    printf "  -h, --help         Show this help message\n"
    printf "\n"
    printf "Examples:\n"
    printf "  # Interactive mode (with confirmation)\n"
    printf "  sh install.sh\n"
    printf "\n"
    printf "  # Auto-confirm mode (skip confirmation)\n"
    printf "  sh install.sh -y\n"
    printf "\n"
    printf "  # Via curl pipe (interactive)\n"
    printf "  curl -fsSL https://url/install.sh | sh\n"
    printf "\n"
    printf "  # Via curl pipe (auto-confirm)\n"
    printf "  curl -fsSL https://url/install.sh | sh -s -- -y\n"
    printf "\n"
}

check_openwrt_version() {
    print_info "Checking OpenWrt version..."
    
    if [ ! -f /etc/openwrt_release ]; then
        print_error "This script must be run on OpenWrt system"
        exit 1
    fi
    
    . /etc/openwrt_release
    
    local version="${DISTRIB_RELEASE}"
    # Extract version number before any non-numeric suffix (like -SNAPSHOT, -rc1, etc.)
    local clean_version=$(echo "$version" | sed 's/[^0-9.].*//')
    local major_version=$(echo "$clean_version" | cut -d'.' -f1)
    local minor_version=$(echo "$clean_version" | cut -d'.' -f2)
    
    # Remove leading zeros to avoid octal interpretation
    major_version=$(echo "$major_version" | sed 's/^0*//')
    minor_version=$(echo "$minor_version" | sed 's/^0*//')
    
    # Default to 0 if empty
    major_version=${major_version:-0}
    minor_version=${minor_version:-0}
    
    print_info "Detected OpenWrt version: ${version}"
    
    # Validate that we got numeric versions
    case "$major_version" in
        ''|*[!0-9]*) 
            print_error "Cannot parse OpenWrt version: ${version}"
            exit 1
            ;;
    esac
    
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
    printf "\n"
    print_info "The following patch files will be installed:"
    printf "\n"
    
    local index=1
    echo "$PATCH_FILES" | while IFS='|' read -r file target; do
        [ -z "$file" ] && continue
        printf "  ${YELLOW}%2d.${NC} %-30s => %s\n" "$index" "$file" "$target"
        index=$((index + 1))
    done
    
    printf "\n"
}

ask_confirmation() {
    # 如果启用了自动确认模式，直接跳过
    if [ "$AUTO_CONFIRM" -eq 1 ]; then
        print_info "Auto-confirm mode enabled, skipping confirmation..."
        return 0
    fi
    
    printf "\n"
    print_warning "This script will modify system files in /usr/share and /www directories."
    print_warning "It is recommended to backup your system before proceeding."
    printf "\n"
    
    # 重定向 stdin 从 /dev/tty 读取，这样即使脚本通过管道执行也能读取用户输入
    printf "${YELLOW}Do you want to continue? [y/N]:${NC} "
    if [ -t 0 ]; then
        # stdin is a terminal
        read -r response
    else
        # stdin is redirected (e.g., from a pipe), read from /dev/tty
        read -r response < /dev/tty
    fi
    
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
        # Use PID to ensure unique backup names
        local backup_path="${file}.backup.$(date +%Y%m%d_%H%M%S).$$"
        cp "$file" "$backup_path"
        print_info "Backed up: $file -> $backup_path"
    fi
}

download_and_install_patches() {
    print_info "Downloading and installing patch files..."
    printf "\n"
    
    local temp_dir="/tmp/luci-app-2fa-patches"
    mkdir -p "$temp_dir"
    
    # Save PATCH_FILES to a temp file to avoid subshell issues
    local temp_list="${temp_dir}/file_list"
    echo "$PATCH_FILES" > "$temp_list"
    
    while IFS='|' read -r file target; do
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
            
            # Restore original permissions if a backup exists
            local recent_backup=$(ls -t "${target}.backup."* 2>/dev/null | head -n1)
            if [ -n "$recent_backup" ] && [ -f "$recent_backup" ]; then
                local perms=$(ls -l "$recent_backup" | awk '{
                    perm = $1
                    u = (substr(perm,2,1)=="r"?4:0) + (substr(perm,3,1)=="w"?2:0) + (substr(perm,4,1)=="x"?1:0)
                    g = (substr(perm,5,1)=="r"?4:0) + (substr(perm,6,1)=="w"?2:0) + (substr(perm,7,1)=="x"?1:0)
                    o = (substr(perm,8,1)=="r"?4:0) + (substr(perm,9,1)=="w"?2:0) + (substr(perm,10,1)=="x"?1:0)
                    printf "%d%d%d", u, g, o
                }')
                chmod "$perms" "$target" 2>/dev/null || chmod 644 "$target"
            else
                chmod 644 "$target"
            fi
            print_success "Installed: $target"
        else
            print_error "Failed to download: $url"
            print_error "Installation incomplete. Please check your internet connection."
            rm -rf "$temp_dir"
            exit 1
        fi
    done < "$temp_list"
    
    # Cleanup
    rm -rf "$temp_dir"
    
    printf "\n"
    print_success "All patch files installed successfully"
}

install_required_packages() {
    printf "\n"
    print_info "Installing mandatory package: ucode-mod-log..."
    
    if opkg update; then
        if opkg install ucode-mod-log; then
            print_success "Package ucode-mod-log installed successfully"
        else
            print_error "Failed to install ucode-mod-log. This package is mandatory!"
            exit 1
        fi
    else
        print_error "Failed to run 'opkg update'. Please check your internet connection."
        exit 1
    fi
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
    printf "\n"
    print_header
    print_success "Installation completed successfully!"
    printf "\n"
    print_info "What's next:"
    printf "\n"
    printf "  1. Install luci-app-2fa package:\n"
    printf "     ${GREEN}wget https://tokisaki-galaxy.github.io/${REPO_NAME}/all/key-build.pub -O /tmp/key-build.pub${NC}\n"
    printf "     ${GREEN}opkg-key add /tmp/key-build.pub${NC}\n"
    printf "     ${GREEN}echo 'src/gz ${REPO_NAME} https://tokisaki-galaxy.github.io/${REPO_NAME}/all' >> /etc/opkg/customfeeds.conf${NC}\n"
    printf "     ${GREEN}opkg update${NC}\n"
    printf "     ${GREEN}opkg install ${REPO_NAME}${NC}\n"
    printf "\n"
    printf "  2. Access LuCI and navigate to:\n"
    printf "     ${BLUE}System → Administration → Authentication${NC}\n"
    printf "\n"
    printf "  3. Configure 2FA at:\n"
    printf "     ${BLUE}System → 2-Factor Auth${NC}\n"
    printf "\n"
    print_info "For more information, visit:"
    printf "  https://github.com/${REPO_OWNER}/${REPO_NAME}\n"
    printf "\n"
}

# Main installation flow
main() {
    # Parse command line arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            -y|--yes)
                AUTO_CONFIRM=1
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    print_header
    
    check_openwrt_version
    check_dependencies
    list_patch_files
    ask_confirmation
    
    printf "\n"
    download_and_install_patches
    install_required_packages
    restart_services
    print_post_install_info
}

# Run main function with all arguments
main "$@"
