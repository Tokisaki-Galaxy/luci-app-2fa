#!/bin/bash
# Backend Tests for luci-app-2fa (plugin architecture)
set -e

CONTAINER_NAME="${1:-openwrt-luci-test}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PLUGIN_UUID="bb4ea47fcffb44ec9bb3d3673c9b4ed2"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass_count=0
fail_count=0

log_pass() { echo -e "${GREEN}✓ PASS${NC}: $1"; ((pass_count++)) || true; }
log_fail() { echo -e "${RED}✗ FAIL${NC}: $1"; ((fail_count++)) || true; }
log_info() { echo -e "${YELLOW}INFO${NC}: $1"; }

check_container() {
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "Container $CONTAINER_NAME is not running."
        exit 1
    fi
}

deploy_files() {
    log_info "Deploying luci-app-2fa files to container..."

    docker exec "$CONTAINER_NAME" mkdir -p \
        /usr/libexec \
        /usr/share/ucode/luci/plugins/auth/login \
        /www/luci-static/resources/view/plugins \
        /etc/uci-defaults

    docker cp "$REPO_ROOT/luci-app-2fa/root/usr/libexec/generate_otp.uc" \
        "$CONTAINER_NAME:/usr/libexec/generate_otp.uc"
    docker exec "$CONTAINER_NAME" chmod +x /usr/libexec/generate_otp.uc

    docker cp "$REPO_ROOT/luci-app-2fa/root/usr/share/ucode/luci/plugins/auth/login/${PLUGIN_UUID}.uc" \
        "$CONTAINER_NAME:/usr/share/ucode/luci/plugins/auth/login/${PLUGIN_UUID}.uc"

    docker cp "$REPO_ROOT/luci-app-2fa/root/www/luci-static/resources/view/plugins/${PLUGIN_UUID}.js" \
        "$CONTAINER_NAME:/www/luci-static/resources/view/plugins/${PLUGIN_UUID}.js"

    docker cp "$REPO_ROOT/luci-app-2fa/root/etc/uci-defaults/luci-app-2fa" \
        "$CONTAINER_NAME:/etc/uci-defaults/luci-app-2fa"

    docker exec "$CONTAINER_NAME" sh -c 'chmod +x /etc/uci-defaults/luci-app-2fa && /etc/uci-defaults/luci-app-2fa'

    docker exec "$CONTAINER_NAME" sh -c '
        uci set luci_plugins.global=global
        uci set luci_plugins.global.enabled=1
        uci set luci_plugins.global.auth_login_enabled=1
        uci set luci_plugins.'$PLUGIN_UUID'=auth_login
        uci set luci_plugins.'$PLUGIN_UUID'.enabled=1
        uci set luci_plugins.'$PLUGIN_UUID'.name="Two-Factor Authentication"
        uci set luci_plugins.'$PLUGIN_UUID'.key_root=JBSWY3DPEHPK3PXP
        uci set luci_plugins.'$PLUGIN_UUID'.type_root=totp
        uci set luci_plugins.'$PLUGIN_UUID'.step_root=30
        uci commit luci_plugins
    '

    docker exec "$CONTAINER_NAME" sh -c 'kill $(pgrep rpcd) 2>/dev/null || true; sleep 1; /sbin/rpcd &'
    sleep 2

    log_info "Files deployed successfully"
}

test_totp_generation() {
    log_info "Test 1: TOTP Generation"
    local result=$(docker exec "$CONTAINER_NAME" /usr/libexec/generate_otp.uc root --plugin=$PLUGIN_UUID 2>&1)
    if echo "$result" | grep -qE '^[0-9]{6}$'; then
        log_pass "TOTP generation returns 6-digit code: $result"
    else
        log_fail "TOTP generation failed: $result"
    fi
}

test_hotp_generation() {
    log_info "Test 2: HOTP Generation"
    docker exec "$CONTAINER_NAME" sh -c '
        uci set luci_plugins.'$PLUGIN_UUID'.type_root=hotp
        uci set luci_plugins.'$PLUGIN_UUID'.counter_root=0
        uci commit luci_plugins
    '

    local result1=$(docker exec "$CONTAINER_NAME" /usr/libexec/generate_otp.uc root --plugin=$PLUGIN_UUID 2>&1)
    local result2=$(docker exec "$CONTAINER_NAME" /usr/libexec/generate_otp.uc root --plugin=$PLUGIN_UUID 2>&1)

    if echo "$result1" | grep -qE '^[0-9]{6}$' && echo "$result2" | grep -qE '^[0-9]{6}$' && [ "$result1" != "$result2" ]; then
        log_pass "HOTP counter increments ($result1 -> $result2)"
    else
        log_fail "HOTP generation failed: $result1 / $result2"
    fi

    docker exec "$CONTAINER_NAME" sh -c '
        uci set luci_plugins.'$PLUGIN_UUID'.type_root=totp
        uci commit luci_plugins
    '
}

test_plugin_registration() {
    log_info "Test 3: Plugin registration"
    local section_type=$(docker exec "$CONTAINER_NAME" uci -q get luci_plugins.$PLUGIN_UUID 2>&1)
    local plugin_name=$(docker exec "$CONTAINER_NAME" uci -q get luci_plugins.$PLUGIN_UUID.name 2>&1)
    if [ "$section_type" = "auth_login" ] && [ "$plugin_name" = "Two-Factor Authentication" ]; then
        log_pass "2FA plugin registered in luci_plugins"
    else
        log_fail "Unexpected plugin registration: type=$section_type name=$plugin_name"
    fi
}

test_login_page_has_otp() {
    log_info "Test 4: Login page contains OTP field"
    local body=$(curl -s http://localhost:8080/cgi-bin/luci/)
    if echo "$body" | grep -q 'name="luci_otp"'; then
        log_pass "OTP field rendered on login page"
    else
        log_fail "OTP field not rendered"
    fi
}

main() {
    echo "========================================"
    echo "  luci-app-2fa Backend Tests"
    echo "========================================"

    check_container
    deploy_files

    test_totp_generation
    test_hotp_generation
    test_plugin_registration
    test_login_page_has_otp

    echo "========================================"
    echo -e "  ${GREEN}Passed: $pass_count${NC}"
    echo -e "  ${RED}Failed: $fail_count${NC}"
    echo "========================================"

    if [ $fail_count -gt 0 ]; then
        exit 1
    fi
}

main "$@"
