#!/bin/bash
set -e

CONTAINER_NAME="openwrt-luci-e2e"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCREENSHOTS_DIR="$REPO_ROOT/screenshots"
PLUGIN_UUID="bb4ea47fcffb44ec9bb3d3673c9b4ed2"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

cleanup() { docker rm -f "$CONTAINER_NAME" 2>/dev/null || true; }

start_container() {
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
    docker run -d --name "$CONTAINER_NAME" -p 8080:80 openwrt/rootfs:x86-64-24.10.4 /bin/ash -c '
        mkdir -p /var/lock /var/run
        opkg update && opkg install luci luci-base luci-compat luci-mod-admin-full luci-mod-system luci-theme-bootstrap
        /sbin/ubusd &
        sleep 1
        /sbin/procd &
        sleep 2
        /sbin/rpcd &
        sleep 1
        /usr/sbin/uhttpd -f -h /www -r OpenWrt -x /cgi-bin -u /ubus -t 60 -T 30 -A 1 -n 3 -N 100 -R -p 0.0.0.0:80 &
        echo -e "password\npassword" | passwd root
        uci set luci.themes.Bootstrap=/luci-static/bootstrap
        uci commit luci
        tail -f /dev/null
    '

    for i in $(seq 1 60); do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/cgi-bin/luci/ 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "403" ]; then
            log_success "LuCI ready (HTTP $HTTP_CODE)"
            return
        fi
        sleep 2
    done

    log_error "Timeout waiting for LuCI"
    docker logs "$CONTAINER_NAME"
    exit 1
}

deploy_plugin() {
    log_info "Deploying luci-app-2fa plugin files..."

    docker exec "$CONTAINER_NAME" mkdir -p \
        /usr/libexec \
        /usr/share/ucode/luci/plugins/auth/login \
        /www/luci-static/resources/view/plugins \
        /etc/uci-defaults

    docker cp "$REPO_ROOT/luci-app-2fa/root/usr/libexec/generate_otp.uc" "$CONTAINER_NAME:/usr/libexec/generate_otp.uc"
    docker exec "$CONTAINER_NAME" chmod +x /usr/libexec/generate_otp.uc

    docker cp "$REPO_ROOT/luci-app-2fa/root/usr/share/ucode/luci/plugins/auth/login/$PLUGIN_UUID.uc" \
        "$CONTAINER_NAME:/usr/share/ucode/luci/plugins/auth/login/$PLUGIN_UUID.uc"
    docker cp "$REPO_ROOT/luci-app-2fa/root/www/luci-static/resources/view/plugins/$PLUGIN_UUID.js" \
        "$CONTAINER_NAME:/www/luci-static/resources/view/plugins/$PLUGIN_UUID.js"
    docker cp "$REPO_ROOT/luci-app-2fa/root/etc/uci-defaults/luci-app-2fa" "$CONTAINER_NAME:/etc/uci-defaults/luci-app-2fa"

    docker exec "$CONTAINER_NAME" sh -c 'chmod +x /etc/uci-defaults/luci-app-2fa && /etc/uci-defaults/luci-app-2fa'
    docker exec "$CONTAINER_NAME" sh -c '
        uci set luci_plugins.global=global
        uci set luci_plugins.global.enabled=1
        uci set luci_plugins.global.auth_login_enabled=1
        uci set luci_plugins.'$PLUGIN_UUID'=auth_login
        uci set luci_plugins.'$PLUGIN_UUID'.enabled=1
        uci set luci_plugins.'$PLUGIN_UUID'.key_root=JBSWY3DPEHPK3PXP
        uci set luci_plugins.'$PLUGIN_UUID'.type_root=totp
        uci set luci_plugins.'$PLUGIN_UUID'.step_root=30
        uci commit luci_plugins
    '

    docker exec "$CONTAINER_NAME" sh -c 'kill $(pgrep rpcd) 2>/dev/null || true; sleep 1; /sbin/rpcd &'
    docker exec "$CONTAINER_NAME" rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache*
    sleep 2

    log_success "Plugin deployed successfully"
}

verify_services() {
    local body=$(curl -s http://localhost:8080/cgi-bin/luci/)
    echo "$body" | grep -q 'name="luci_otp"' || {
        log_error "OTP field not present in login page"
        exit 1
    }
    log_success "Login form shows OTP field"
}

run_backend_tests() {
    chmod +x "$REPO_ROOT/tests/backend/test-backend.sh"
    "$REPO_ROOT/tests/backend/test-backend.sh" "$CONTAINER_NAME"
}

run_e2e_tests() {
    mkdir -p "$SCREENSHOTS_DIR"
    cd "$REPO_ROOT"
    if [ ! -d "node_modules" ]; then
        npm install
        npx playwright install chromium
    fi
    npx playwright test --reporter=list --output="$SCREENSHOTS_DIR"
}

main() {
    trap cleanup EXIT
    start_container
    deploy_plugin
    verify_services

    case "${1:-all}" in
        backend) run_backend_tests ;;
        e2e) run_e2e_tests ;;
        all) run_backend_tests; run_e2e_tests ;;
        setup) log_success "Ready at http://localhost:8080 (root/password)"; read -r -d '' _ </dev/tty ;;
        *) echo "Usage: $0 [backend|e2e|all|setup]"; exit 1 ;;
    esac

    log_success "Done"
}

main "$@"
