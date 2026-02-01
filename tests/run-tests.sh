#!/bin/bash
# Setup and run E2E tests for luci-app-2fa
#
# This script:
# 1. Starts an OpenWrt Docker container with LuCI
# 2. Deploys the luci-app-2fa plugin
# 3. Runs Playwright E2E tests
# 4. Collects screenshots

set -e

CONTAINER_NAME="openwrt-luci-e2e"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCREENSHOTS_DIR="$REPO_ROOT/screenshots"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up..."
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
}

# Start OpenWrt container with LuCI
start_container() {
    log_info "Starting OpenWrt container with LuCI..."
    
    # Remove existing container if exists
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
    
    # Start container with LuCI environment
    docker run -d --name "$CONTAINER_NAME" -p 8080:80 openwrt/rootfs:x86-64-24.10.4 /bin/ash -c '
        mkdir -p /var/lock /var/run
        opkg update && opkg install luci luci-base luci-compat luci-mod-admin-full luci-mod-system luci-theme-bootstrap
        
        # Start services in correct order
        /sbin/ubusd &
        sleep 1
        /sbin/procd &
        sleep 2
        /sbin/rpcd &
        sleep 1
        /usr/sbin/uhttpd -f -h /www -r OpenWrt -x /cgi-bin -u /ubus -t 60 -T 30 -A 1 -n 3 -N 100 -R -p 0.0.0.0:80 &
        
        # Set password
        echo -e "password\npassword" | passwd root
        
        # Configure theme
        uci set luci.themes.Bootstrap=/luci-static/bootstrap
        uci commit luci
        
        tail -f /dev/null
    '
    
    log_info "Waiting for LuCI to be ready..."
    
    # Wait for LuCI to be available
    MAX_RETRIES=60
    COUNT=0
    while [ $COUNT -lt $MAX_RETRIES ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/cgi-bin/luci/ 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "403" ]; then
            log_success "LuCI is ready (HTTP $HTTP_CODE)"
            break
        fi
        echo "  Waiting... ($((COUNT+1))/$MAX_RETRIES) [HTTP: $HTTP_CODE]"
        sleep 5
        COUNT=$((COUNT+1))
    done
    
    if [ $COUNT -eq $MAX_RETRIES ]; then
        log_error "Timeout waiting for LuCI"
        docker logs "$CONTAINER_NAME"
        exit 1
    fi
}

# Deploy luci-app-2fa files
deploy_plugin() {
    log_info "Deploying luci-app-2fa plugin..."
    
    # Create directories
    docker exec "$CONTAINER_NAME" mkdir -p \
        /usr/share/rpcd/ucode \
        /usr/share/rpcd/acl.d \
        /usr/share/luci/auth.d \
        /usr/share/luci/menu.d \
        /www/luci-static/resources/view/system \
        /usr/libexec
    
    # Deploy ucode files
    docker cp "$REPO_ROOT/luci-app-2fa/root/usr/libexec/generate_otp.uc" \
        "$CONTAINER_NAME:/usr/libexec/generate_otp.uc"
    docker exec "$CONTAINER_NAME" chmod +x /usr/libexec/generate_otp.uc
    
    docker cp "$REPO_ROOT/luci-app-2fa/root/usr/share/rpcd/ucode/2fa.uc" \
        "$CONTAINER_NAME:/usr/share/rpcd/ucode/2fa.uc"
    
    # Deploy ACL
    docker cp "$REPO_ROOT/luci-app-2fa/root/usr/share/rpcd/acl.d/luci-app-2fa.json" \
        "$CONTAINER_NAME:/usr/share/rpcd/acl.d/luci-app-2fa.json"
    
    # Deploy auth plugin
    docker cp "$REPO_ROOT/luci-app-2fa/root/usr/share/luci/auth.d/2fa.uc" \
        "$CONTAINER_NAME:/usr/share/luci/auth.d/2fa.uc"
    
    # Deploy menu
    docker cp "$REPO_ROOT/luci-app-2fa/root/usr/share/luci/menu.d/luci-app-2fa.json" \
        "$CONTAINER_NAME:/usr/share/luci/menu.d/luci-app-2fa.json"
    
    # Deploy JS view
    docker cp "$REPO_ROOT/luci-app-2fa/htdocs/luci-static/resources/view/system/2fa.js" \
        "$CONTAINER_NAME:/www/luci-static/resources/view/system/2fa.js"
    
    # Deploy uqr.js
    docker cp "$REPO_ROOT/luci-app-2fa/htdocs/luci-static/resources/uqr.js" \
        "$CONTAINER_NAME:/www/luci-static/resources/uqr.js"
    
    # Deploy config
    docker cp "$REPO_ROOT/luci-app-2fa/root/etc/config/2fa" \
        "$CONTAINER_NAME:/etc/config/2fa"
    
    # Deploy luci-patch files
    log_info "Deploying luci-patch files..."
    
    # Deploy luci ucode (contains listAuthPlugins)
    docker cp "$REPO_ROOT/luci-patch/patch/luci" \
        "$CONTAINER_NAME:/usr/share/rpcd/ucode/luci"
    
    # Deploy dispatcher.uc (auth plugin integration)
    docker cp "$REPO_ROOT/luci-patch/patch/dispatcher.uc" \
        "$CONTAINER_NAME:/usr/share/ucode/luci/dispatcher.uc"
    
    # Deploy sysauth.ut template
    docker cp "$REPO_ROOT/luci-patch/patch/sysauth.ut" \
        "$CONTAINER_NAME:/usr/share/ucode/luci/template/sysauth.ut"
    
    # Deploy bootstrap sysauth template
    docker exec "$CONTAINER_NAME" mkdir -p /usr/share/ucode/luci/template/themes/bootstrap
    docker cp "$REPO_ROOT/luci-patch/patch/bootstrap-sysauth.ut" \
        "$CONTAINER_NAME:/usr/share/ucode/luci/template/themes/bootstrap/sysauth.ut"
    
    # Deploy authsettings view
    docker cp "$REPO_ROOT/luci-patch/patch/view/system/exauth.js" \
        "$CONTAINER_NAME:/www/luci-static/resources/view/system/exauth.js"
    
    # Deploy ACL patches
    docker cp "$REPO_ROOT/luci-patch/patch/luci-base.json" \
        "$CONTAINER_NAME:/usr/share/rpcd/acl.d/luci-base.json"
    
    # Deploy menu patches
    docker cp "$REPO_ROOT/luci-patch/patch/luci-mod-system.json" \
        "$CONTAINER_NAME:/usr/share/luci/menu.d/luci-mod-system.json"
    
    # Enable external auth
    docker exec "$CONTAINER_NAME" sh -c '
        uci set luci.main=core
        uci set luci.main.external_auth=1
        uci commit luci
    '
    
    # Restart rpcd to pick up new handlers
    docker exec "$CONTAINER_NAME" sh -c 'kill $(pgrep rpcd) 2>/dev/null || true; sleep 1; /sbin/rpcd &'
    sleep 2
    
    # Clear LuCI cache
    docker exec "$CONTAINER_NAME" rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache*
    
    log_success "Plugin deployed successfully"
}

# Verify services
verify_services() {
    log_info "Verifying services..."
    
    # Check ubus services
    docker exec "$CONTAINER_NAME" ubus list | grep -E "^(system|luci|2fa)$" || {
        log_error "Not all ubus services are registered"
        docker exec "$CONTAINER_NAME" ubus list
        exit 1
    }
    
    # Check 2fa RPC endpoint
    docker exec "$CONTAINER_NAME" ubus call 2fa getConfig '{}' || {
        log_error "2fa RPC endpoint not working"
        exit 1
    }
    
    log_success "All services verified"
}

# Run backend tests
run_backend_tests() {
    log_info "Running backend tests..."
    
    chmod +x "$REPO_ROOT/tests/backend/test-backend.sh"
    "$REPO_ROOT/tests/backend/test-backend.sh" "$CONTAINER_NAME"
}

# Run E2E tests
run_e2e_tests() {
    log_info "Running Playwright E2E tests..."
    
    # Create screenshots directory
    mkdir -p "$SCREENSHOTS_DIR"
    
    # Install dependencies if needed
    cd "$REPO_ROOT"
    if [ ! -d "node_modules" ]; then
        npm install
        npx playwright install chromium
    fi
    
    # Run tests
    npx playwright test --reporter=list --output="$SCREENSHOTS_DIR"
    
    log_success "E2E tests completed"
}

# Main
main() {
    echo "========================================"
    echo "  luci-app-2fa E2E Test Runner"
    echo "========================================"
    echo ""
    
    # Set up cleanup trap
    trap cleanup EXIT
    
    start_container
    deploy_plugin
    verify_services
    
    # Run tests based on argument
    case "${1:-all}" in
        backend)
            run_backend_tests
            ;;
        e2e)
            run_e2e_tests
            ;;
        all)
            run_backend_tests
            run_e2e_tests
            ;;
        setup)
            # Just setup, don't run tests (for manual testing)
            log_success "Container setup complete. LuCI is available at http://localhost:8080"
            log_info "Login: root / password"
            log_info "Press Ctrl+C to stop"
            read -r -d '' _ </dev/tty
            ;;
        *)
            echo "Usage: $0 [backend|e2e|all|setup]"
            exit 1
            ;;
    esac
    
    echo ""
    log_success "All tests completed successfully!"
}

main "$@"
