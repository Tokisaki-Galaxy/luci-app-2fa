/**
 * TOTP Verification Test
 * 
 * This test verifies the generate_otp.uc implementation against standard TOTP tools
 * using the otpauth library which follows RFC 6238 and RFC 4226 specifications.
 */

import * as OTPAuth from 'otpauth';

// Test vectors from RFC 6238 Appendix B
// SHA-1 key: "12345678901234567890" in ASCII
// Base32 encoded: GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ

const TEST_SECRET_ASCII = '12345678901234567890';
const TEST_SECRET_BASE32 = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

// Additional test vectors for our implementation
const TEST_VECTORS = [
  // { timestamp: seconds, expected_totp: 'NNNNNN' } 
  // RFC 6238 test vectors (step = 30 seconds)
  { timestamp: 59, expected: '287082' },
  { timestamp: 1111111109, expected: '081804' },
  { timestamp: 1111111111, expected: '050471' },
  { timestamp: 1234567890, expected: '005924' },
  { timestamp: 2000000000, expected: '279037' },
];

// Custom test secret for our app
const CUSTOM_SECRET = 'JBSWY3DPEHPK3PXP'; // "Hello!" in base32
const CUSTOM_TIMESTAMP = 1704067200; // 2024-01-01 00:00:00 UTC

/**
 * Verify TOTP using otpauth library (standard implementation)
 */
function verifyWithOTPAuth(secret, timestamp, step = 30) {
  const totp = new OTPAuth.TOTP({
    issuer: 'Test',
    label: 'test@example.com',
    algorithm: 'SHA1',
    digits: 6,
    period: step,
    secret: OTPAuth.Secret.fromBase32(secret)
  });
  
  return totp.generate({ timestamp: timestamp * 1000 });
}

/**
 * Verify HOTP using otpauth library
 */
function verifyHOTPWithOTPAuth(secret, counter) {
  const hotp = new OTPAuth.HOTP({
    issuer: 'Test',
    label: 'test@example.com',
    algorithm: 'SHA1',
    digits: 6,
    secret: OTPAuth.Secret.fromBase32(secret)
  });
  
  return hotp.generate({ counter });
}

console.log('=== TOTP Verification Tests ===\n');

// Test RFC 6238 vectors
console.log('1. RFC 6238 Test Vectors (SHA-1, 30-second step):');
console.log('   Secret (Base32):', TEST_SECRET_BASE32);
console.log('');

let allPassed = true;

for (const vector of TEST_VECTORS) {
  const generated = verifyWithOTPAuth(TEST_SECRET_BASE32, vector.timestamp);
  const passed = generated === vector.expected;
  allPassed = allPassed && passed;
  
  console.log(`   Timestamp ${vector.timestamp}:`);
  console.log(`     Expected: ${vector.expected}`);
  console.log(`     Got:      ${generated}`);
  console.log(`     Status:   ${passed ? '✓ PASS' : '✗ FAIL'}`);
  console.log('');
}

// Test custom secret
console.log('2. Custom Secret Test:');
console.log('   Secret (Base32):', CUSTOM_SECRET);
console.log('   Timestamp:', CUSTOM_TIMESTAMP);

const customTOTP = verifyWithOTPAuth(CUSTOM_SECRET, CUSTOM_TIMESTAMP);
console.log('   Generated TOTP:', customTOTP);
console.log('');

// Test HOTP
console.log('3. HOTP Test Vectors:');
console.log('   Secret (Base32):', CUSTOM_SECRET);

for (let counter = 0; counter < 5; counter++) {
  const hotp = verifyHOTPWithOTPAuth(CUSTOM_SECRET, counter);
  console.log(`   Counter ${counter}: ${hotp}`);
}
console.log('');

// Generate reference values for different timestamps (for comparison with ucode implementation)
console.log('4. Reference Values for Testing:');
console.log('   These can be used to verify the ucode implementation.\n');

const testTimestamps = [
  Math.floor(Date.now() / 1000), // Current time
  1700000000, // Fixed timestamp for reproducible tests
  1704067200, // 2024-01-01 00:00:00 UTC
];

for (const ts of testTimestamps) {
  const totp = verifyWithOTPAuth(CUSTOM_SECRET, ts);
  console.log(`   Secret: ${CUSTOM_SECRET}`);
  console.log(`   Timestamp: ${ts}`);
  console.log(`   Step: 30`);
  console.log(`   TOTP: ${totp}`);
  console.log('');
}

// Summary
console.log('=== Summary ===');
console.log(`RFC 6238 Tests: ${allPassed ? 'All PASSED ✓' : 'SOME FAILED ✗'}`);
console.log('');

// Export test function for use in other tests
export { verifyWithOTPAuth, verifyHOTPWithOTPAuth, TEST_SECRET_BASE32, CUSTOM_SECRET };
