#!/bin/bash
# Backend Tests for luci-app-2fa
# 
# This script tests the ucode backend functionality inside an OpenWrt Docker container.
# It validates TOTP/HOTP generation, RPC methods, and authentication plugin.

set -e

CONTAINER_NAME="${1:-openwrt-luci-test}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass_count=0
fail_count=0

log_pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    ((pass_count++)) || true
}

log_fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    ((fail_count++)) || true
}

log_info() {
    echo -e "${YELLOW}INFO${NC}: $1"
}

# Check if container is running
check_container() {
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "Container $CONTAINER_NAME is not running."
        echo "Please start it with the LuCI environment first."
        exit 1
    fi
}

# Deploy files to container
deploy_files() {
    log_info "Deploying luci-app-2fa files to container..."
    
    # Deploy generate_otp.uc
    docker cp "$REPO_ROOT/luci-app-2fa/root/usr/libexec/generate_otp.uc" \
        "$CONTAINER_NAME:/usr/libexec/generate_otp.uc"
    docker exec "$CONTAINER_NAME" chmod +x /usr/libexec/generate_otp.uc
    
    # Deploy 2fa.uc RPC handler
    docker exec "$CONTAINER_NAME" mkdir -p /usr/share/rpcd/ucode
    docker cp "$REPO_ROOT/luci-app-2fa/root/usr/share/rpcd/ucode/2fa.uc" \
        "$CONTAINER_NAME:/usr/share/rpcd/ucode/2fa.uc"
    
    # Deploy ACL
    docker exec "$CONTAINER_NAME" mkdir -p /usr/share/rpcd/acl.d
    docker cp "$REPO_ROOT/luci-app-2fa/root/usr/share/rpcd/acl.d/luci-app-2fa.json" \
        "$CONTAINER_NAME:/usr/share/rpcd/acl.d/luci-app-2fa.json"
    
    # Deploy auth plugin
    docker exec "$CONTAINER_NAME" mkdir -p /usr/share/luci/auth.d
    docker cp "$REPO_ROOT/luci-app-2fa/root/usr/share/luci/auth.d/2fa.uc" \
        "$CONTAINER_NAME:/usr/share/luci/auth.d/2fa.uc"
    
    # Deploy menu
    docker exec "$CONTAINER_NAME" mkdir -p /usr/share/luci/menu.d
    docker cp "$REPO_ROOT/luci-app-2fa/root/usr/share/luci/menu.d/luci-app-2fa.json" \
        "$CONTAINER_NAME:/usr/share/luci/menu.d/luci-app-2fa.json"
    
    # Deploy default config
    docker cp "$REPO_ROOT/luci-app-2fa/root/etc/config/2fa" \
        "$CONTAINER_NAME:/etc/config/2fa"
    
    # Restart rpcd to pick up new handlers
    docker exec "$CONTAINER_NAME" sh -c 'kill $(pgrep rpcd) 2>/dev/null || true; sleep 1; /sbin/rpcd &'
    sleep 2
    
    log_info "Files deployed successfully"
}

# Test 1: Test TOTP generation with known values
test_totp_generation() {
    log_info "Test 1: TOTP Generation"
    
    # Set up test config with known secret
    # Using JBSWY3DPEHPK3PXP which is "Hello!" in base32
    docker exec "$CONTAINER_NAME" sh -c '
        uci set 2fa.settings=settings
        uci set 2fa.settings.enabled=1
        uci set 2fa.root=login
        uci set 2fa.root.key=JBSWY3DPEHPK3PXP
        uci set 2fa.root.type=totp
        uci set 2fa.root.step=30
        uci commit 2fa
    '
    
    # Generate OTP
    local result=$(docker exec "$CONTAINER_NAME" /usr/libexec/generate_otp.uc root 2>&1)
    
    # OTP should be exactly 6 digits
    if echo "$result" | grep -qE '^[0-9]{6}$'; then
        log_pass "TOTP generation returns 6-digit code: $result"
    else
        log_fail "TOTP generation failed or returned invalid format: $result"
    fi
}

# Test 2: Test HOTP generation
test_hotp_generation() {
    log_info "Test 2: HOTP Generation"
    
    # Set up HOTP config
    docker exec "$CONTAINER_NAME" sh -c '
        uci set 2fa.root.type=hotp
        uci set 2fa.root.counter=0
        uci commit 2fa
    '
    
    # Generate first HOTP
    local result1=$(docker exec "$CONTAINER_NAME" /usr/libexec/generate_otp.uc root 2>&1)
    
    # Counter should have incremented - generate second HOTP
    local result2=$(docker exec "$CONTAINER_NAME" /usr/libexec/generate_otp.uc root 2>&1)
    
    if echo "$result1" | grep -qE '^[0-9]{6}$' && echo "$result2" | grep -qE '^[0-9]{6}$'; then
        if [ "$result1" != "$result2" ]; then
            log_pass "HOTP generation: First=$result1, Second=$result2 (different as expected)"
        else
            log_fail "HOTP codes should be different (counter should increment)"
        fi
    else
        log_fail "HOTP generation failed: result1=$result1, result2=$result2"
    fi
    
    # Reset to TOTP
    docker exec "$CONTAINER_NAME" sh -c '
        uci set 2fa.root.type=totp
        uci commit 2fa
    '
}

# Test 3: Test RPC isEnabled method
test_rpc_is_enabled() {
    log_info "Test 3: RPC isEnabled Method"
    
    # Test with 2FA enabled
    docker exec "$CONTAINER_NAME" sh -c 'uci set 2fa.settings.enabled=1; uci commit 2fa'
    local result=$(docker exec "$CONTAINER_NAME" ubus call 2fa isEnabled '{"username":"root"}' 2>&1)
    
    if echo "$result" | grep -q '"enabled": true'; then
        log_pass "isEnabled returns true when 2FA is enabled"
    else
        log_fail "isEnabled should return true: $result"
    fi
    
    # Test with 2FA disabled
    docker exec "$CONTAINER_NAME" sh -c 'uci set 2fa.settings.enabled=0; uci commit 2fa'
    result=$(docker exec "$CONTAINER_NAME" ubus call 2fa isEnabled '{"username":"root"}' 2>&1)
    
    if echo "$result" | grep -q '"enabled": false'; then
        log_pass "isEnabled returns false when 2FA is disabled"
    else
        log_fail "isEnabled should return false: $result"
    fi
    
    # Re-enable for further tests
    docker exec "$CONTAINER_NAME" sh -c 'uci set 2fa.settings.enabled=1; uci commit 2fa'
}

# Test 4: Test RPC getConfig method
test_rpc_get_config() {
    log_info "Test 4: RPC getConfig Method"
    
    local result=$(docker exec "$CONTAINER_NAME" ubus call 2fa getConfig '{}' 2>&1)
    
    # Check that all expected fields are present
    if echo "$result" | grep -q '"enabled"' && \
       echo "$result" | grep -q '"type"' && \
       echo "$result" | grep -q '"key"' && \
       echo "$result" | grep -q '"step"'; then
        log_pass "getConfig returns all expected fields"
    else
        log_fail "getConfig missing fields: $result"
    fi
}

# Test 5: Test RPC setConfig method
test_rpc_set_config() {
    log_info "Test 5: RPC setConfig Method"
    
    # Set new config
    local result=$(docker exec "$CONTAINER_NAME" ubus call 2fa setConfig \
        '{"enabled":"1","type":"totp","key":"TESTTESTTESTTEST","step":"60"}' 2>&1)
    
    if echo "$result" | grep -q '"result": true'; then
        log_pass "setConfig returns success"
    else
        log_fail "setConfig failed: $result"
    fi
    
    # Verify config was set
    local verify=$(docker exec "$CONTAINER_NAME" uci get 2fa.root.step 2>&1)
    if [ "$verify" = "60" ]; then
        log_pass "setConfig actually modified UCI config (step=60)"
    else
        log_fail "setConfig did not modify config: step=$verify"
    fi
    
    # Restore original config
    docker exec "$CONTAINER_NAME" sh -c '
        uci set 2fa.root.key=JBSWY3DPEHPK3PXP
        uci set 2fa.root.step=30
        uci commit 2fa
    '
}

# Test 6: Test RPC generateKey method
test_rpc_generate_key() {
    log_info "Test 6: RPC generateKey Method"
    
    local result=$(docker exec "$CONTAINER_NAME" ubus call 2fa generateKey '{"length":16}' 2>&1)
    
    # Check that key is returned and is valid base32
    if echo "$result" | grep -qE '"key":\s*"[A-Z2-7]{16}"'; then
        log_pass "generateKey returns valid 16-char base32 key"
    else
        log_fail "generateKey failed or invalid format: $result"
    fi
    
    # Test default length
    result=$(docker exec "$CONTAINER_NAME" ubus call 2fa generateKey '{}' 2>&1)
    if echo "$result" | grep -qE '"key":\s*"[A-Z2-7]{16}"'; then
        log_pass "generateKey with default length returns 16-char key"
    else
        log_fail "generateKey default length failed: $result"
    fi
}

# Test 7: Test RPC verifyOTP method
test_rpc_verify_otp() {
    log_info "Test 7: RPC verifyOTP Method"
    
    # Get current OTP
    local current_otp=$(docker exec "$CONTAINER_NAME" /usr/libexec/generate_otp.uc root 2>&1)
    
    # Verify with correct OTP
    local result=$(docker exec "$CONTAINER_NAME" ubus call 2fa verifyOTP \
        "{\"username\":\"root\",\"otp\":\"$current_otp\"}" 2>&1)
    
    if echo "$result" | grep -q '"result": true'; then
        log_pass "verifyOTP accepts valid OTP"
    else
        log_fail "verifyOTP should accept valid OTP: $result"
    fi
    
    # Verify with wrong OTP
    result=$(docker exec "$CONTAINER_NAME" ubus call 2fa verifyOTP \
        '{"username":"root","otp":"000000"}' 2>&1)
    
    if echo "$result" | grep -q '"result": false'; then
        log_pass "verifyOTP rejects invalid OTP"
    else
        log_fail "verifyOTP should reject invalid OTP: $result"
    fi
}

# Test 8: Test input validation (security)
test_input_validation() {
    log_info "Test 8: Input Validation (Security)"
    
    # Test username sanitization - try command injection
    local result=$(docker exec "$CONTAINER_NAME" ubus call 2fa isEnabled \
        '{"username":"root; ls -la"}' 2>&1)
    
    # Should return false (invalid username) or handle safely
    if echo "$result" | grep -q '"enabled": false' || echo "$result" | grep -q 'error'; then
        log_pass "Username with special characters is rejected/handled safely"
    else
        log_fail "Potential command injection vulnerability: $result"
    fi
    
    # Test OTP format validation
    result=$(docker exec "$CONTAINER_NAME" ubus call 2fa verifyOTP \
        '{"username":"root","otp":"abc123"}' 2>&1)
    
    if echo "$result" | grep -q '"result": false'; then
        log_pass "Non-numeric OTP is rejected"
    else
        log_fail "Non-numeric OTP should be rejected: $result"
    fi
}

# Test 9: Test TOTP time window (should accept codes within window)
test_totp_time_window() {
    log_info "Test 9: TOTP Time Consistency"
    
    # Generate two codes close together - they should be the same within 30 seconds
    local otp1=$(docker exec "$CONTAINER_NAME" /usr/libexec/generate_otp.uc root 2>&1)
    sleep 1
    local otp2=$(docker exec "$CONTAINER_NAME" /usr/libexec/generate_otp.uc root 2>&1)
    
    if [ "$otp1" = "$otp2" ]; then
        log_pass "TOTP codes are consistent within time window: $otp1"
    else
        log_fail "TOTP codes changed unexpectedly: $otp1 vs $otp2"
    fi
}

# Test 10: Test auth plugin listAuthPlugins
test_list_auth_plugins() {
    log_info "Test 10: listAuthPlugins (luci-patch integration)"
    
    # First, deploy the luci-patch files
    docker exec "$CONTAINER_NAME" mkdir -p /usr/share/rpcd/ucode
    docker cp "$REPO_ROOT/luci-patch/patch/luci" \
        "$CONTAINER_NAME:/usr/share/rpcd/ucode/luci"
    
    # Enable external auth in UCI
    docker exec "$CONTAINER_NAME" sh -c '
        uci set luci.main=core
        uci set luci.main.external_auth=1
        uci commit luci
    '
    
    # Restart rpcd
    docker exec "$CONTAINER_NAME" sh -c 'kill $(pgrep rpcd) 2>/dev/null || true; sleep 1; /sbin/rpcd &'
    sleep 2
    
    local result=$(docker exec "$CONTAINER_NAME" ubus call luci listAuthPlugins '{}' 2>&1)
    
    if echo "$result" | grep -q '"2fa"' || echo "$result" | grep -q '"plugins"'; then
        log_pass "listAuthPlugins returns plugin information"
    else
        log_fail "listAuthPlugins failed: $result"
    fi
}

# Main execution
main() {
    echo "========================================"
    echo "  luci-app-2fa Backend Tests"
    echo "========================================"
    echo ""
    
    check_container
    deploy_files
    
    echo ""
    echo "Running tests..."
    echo ""
    
    test_totp_generation
    test_hotp_generation
    test_rpc_is_enabled
    test_rpc_get_config
    test_rpc_set_config
    test_rpc_generate_key
    test_rpc_verify_otp
    test_input_validation
    test_totp_time_window
    test_list_auth_plugins
    
    echo ""
    echo "========================================"
    echo "  Test Results"
    echo "========================================"
    echo -e "  ${GREEN}Passed: $pass_count${NC}"
    echo -e "  ${RED}Failed: $fail_count${NC}"
    echo "========================================"
    
    if [ $fail_count -gt 0 ]; then
        exit 1
    fi
    exit 0
}

main "$@"
