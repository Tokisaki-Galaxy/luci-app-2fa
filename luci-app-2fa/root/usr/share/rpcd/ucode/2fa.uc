// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2024 Christian Marangi <ansuelsmth@gmail.com>

'use strict';

import { popen, open, glob, lsdir, writefile, readfile, stat, unlink } from 'fs';
import { cursor } from 'uci';

// Rate limit state file
const RATE_LIMIT_FILE = '/tmp/2fa_rate_limit.json';

// Default minimum valid time (2026-01-01 00:00:00 UTC)
// TOTP depends on accurate system time. If system clock is not calibrated
// (e.g., after power loss on devices without RTC battery), TOTP codes will
// be incorrect and users will be locked out. This threshold disables TOTP
// when system time appears uncalibrated.
const DEFAULT_MIN_VALID_TIME = 1767225600;

// Constant-time string comparison to prevent timing attacks
// NOTE: This function must be defined before verify_backup_code which uses it
function constant_time_compare(a, b) {
	if (length(a) != length(b))
		return false;

	let result = 0;
	for (let i = 0; i < length(a); i++) {
		result = result | (ord(a, i) ^ ord(b, i));
	}
	return result == 0;
}

// Check if system time is calibrated (not earlier than minimum valid time)
// Returns: { calibrated: bool, current_time: int, min_valid_time: int }
function check_time_calibration() {
	let ctx = cursor();
	let config_time = ctx.get('2fa', 'settings', 'min_valid_time');
	let min_valid_time = config_time ? int(config_time) : DEFAULT_MIN_VALID_TIME;
	let current_time = time();
	
	return {
		calibrated: current_time >= min_valid_time,
		current_time: current_time,
		min_valid_time: min_valid_time
	};
}

// Improved hash function for backup codes using multiple rounds and mixing
// While not SHA-256, this provides better collision resistance than a simple hash
// The backup code format (XXXX-XXXX, ~40 bits of entropy) limits attack surface
// Combined with rate limiting, this provides reasonable security for this use case
function backup_code_hash(str) {
	// FNV-1a inspired hash with multiple rounds for better avalanche effect
	let h1 = 0x811c9dc5;  // FNV offset basis
	let h2 = 0x01000193;  // FNV prime
	
	// First round - FNV-1a style
	for (let i = 0; i < length(str); i++) {
		let c = ord(str, i);
		h1 = h1 ^ c;
		h1 = (h1 * 0x01000193) & 0xFFFFFFFF;
	}
	
	// Second round - mix with position-dependent values
	for (let i = 0; i < length(str); i++) {
		let c = ord(str, i);
		h2 = h2 ^ ((c << (i % 24)) | (c >> (32 - (i % 24))));
		h2 = ((h2 << 5) + h2 + c) & 0xFFFFFFFF;
	}
	
	// Mix the two hashes together
	let final = (h1 ^ (h2 >> 16) ^ (h2 << 16)) & 0xFFFFFFFF;
	final = final ^ (h1 >> 8);
	
	// Return 16-character hex string (64 bits) for better collision resistance
	return sprintf('%08x%08x', h1 & 0xFFFFFFFF, (final ^ h2) & 0xFFFFFFFF);
}

// Generate backup security codes
// Returns array of { code: 'plaintext', hash: 'hashed' }
function generate_backup_codes(count) {
	if (!count || count < 1) count = 5;
	if (count > 10) count = 10;
	
	let codes = [];
	let chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';  // Exclude confusing chars: 0,O,I,1
	
	// Read random bytes from /dev/urandom
	let fd = open('/dev/urandom', 'r');
	if (fd) {
		let data = fd.read(count * 16);
		fd.close();
		
		for (let i = 0; i < count; i++) {
			let code = '';
			// Generate 8-character code in format XXXX-XXXX
			for (let j = 0; j < 8; j++) {
				let idx = i * 16 + j;
				if (idx < length(data)) {
					let num = ord(data, idx);
					code = code + substr(chars, num % 32, 1);
				}
			}
			// Format as XXXX-XXXX for readability
			code = substr(code, 0, 4) + '-' + substr(code, 4, 4);
			push(codes, {
				code: code,
				hash: backup_code_hash(code)
			});
		}
	}
	
	// Fallback if /dev/urandom fails
	let fallbackSeed = time();
	while (length(codes) < count) {
		let code = '';
		for (let j = 0; j < 8; j++) {
			fallbackSeed = (fallbackSeed * 1103515245 + 12345) % 2147483648;
			code = code + substr(chars, fallbackSeed % 32, 1);
		}
		code = substr(code, 0, 4) + '-' + substr(code, 4, 4);
		push(codes, {
			code: code,
			hash: backup_code_hash(code)
		});
	}
	
	return codes;
}

// Verify a backup code
// Returns: { valid: bool, consumed: bool }
function verify_backup_code(username, code) {
	let ctx = cursor();
	
	// Normalize the code (remove dashes, uppercase)
	code = replace(uc(code), '-', '');
	// Re-add dash for hashing (stored format is XXXX-XXXX)
	if (length(code) == 8) {
		code = substr(code, 0, 4) + '-' + substr(code, 4, 4);
	}
	
	let code_hash = backup_code_hash(code);
	
	// Get stored backup codes
	let user_config = ctx.get_all('2fa', username);
	if (!user_config || !user_config.backup_codes) {
		return { valid: false, consumed: false };
	}
	
	let stored_codes = user_config.backup_codes;
	if (type(stored_codes) == 'string') {
		stored_codes = [stored_codes];
	}
	
	// Check if the code matches any stored hash
	for (let i = 0; i < length(stored_codes); i++) {
		let stored_hash = stored_codes[i];
		if (stored_hash && stored_hash != '' && constant_time_compare(stored_hash, code_hash)) {
			// Code is valid - remove it (one-time use)
			ctx.delete('2fa', username, 'backup_codes');
			for (let j = 0; j < length(stored_codes); j++) {
				if (j != i && stored_codes[j] && stored_codes[j] != '') {
					ctx.list_append('2fa', username, 'backup_codes', stored_codes[j]);
				}
			}
			ctx.commit('2fa');
			return { valid: true, consumed: true };
		}
	}
	
	return { valid: false, consumed: false };
}

// Sanitize username to prevent command injection
function sanitize_username(username) {
	// Only allow alphanumeric characters, underscore, dash, and dot
	if (!match(username, /^[a-zA-Z0-9_.-]+$/))
		return null;
	return username;
}

// Validate IP address (IPv4 or IPv6)
// Note: IPv6 validation is simplified - it accepts basic IPv6 formats but may allow some invalid addresses.
// For strict validation, consider using a more comprehensive regex or a dedicated library.
function is_valid_ip(ip) {
	if (!ip || ip == '')
		return false;
	// IPv4 pattern - validate each octet is 0-255
	if (match(ip, /^(\d{1,3}\.){3}\d{1,3}$/)) {
		let parts = split(ip, '.');
		for (let i = 0; i < length(parts); i++) {
			if (int(parts[i]) > 255) return false;
		}
		return true;
	}
	// IPv4 CIDR pattern
	if (match(ip, /^(\d{1,3}\.){3}\d{1,3}\/\d{1,2}$/)) {
		let cidr_parts = split(ip, '/');
		let prefix = int(cidr_parts[1]);
		if (prefix < 0 || prefix > 32) return false;
		let ip_parts = split(cidr_parts[0], '.');
		for (let i = 0; i < length(ip_parts); i++) {
			if (int(ip_parts[i]) > 255) return false;
		}
		return true;
	}
	// IPv6 pattern (simplified - basic validation)
	// Accept addresses with colons and hex digits, ensure at least one colon
	if (match(ip, /^[0-9a-fA-F:]+$/) && index(ip, ':') >= 0)
		return true;
	// IPv6 CIDR pattern
	if (match(ip, /^[0-9a-fA-F:]+\/\d{1,3}$/) && index(ip, ':') >= 0) {
		let cidr_parts = split(ip, '/');
		let prefix = int(cidr_parts[1]);
		if (prefix < 0 || prefix > 128) return false;
		return true;
	}
	return false;
}

// Check if an IP is in a CIDR range
// Note: For IPv6, CIDR matching falls back to exact string comparison.
// Full IPv6 CIDR support would require more complex bit manipulation.
function ip_in_cidr(ip, cidr) {
	// Split CIDR into IP and prefix
	let parts = split(cidr, '/');
	let network_ip = parts[0];
	let prefix = (length(parts) > 1) ? int(parts[1]) : 32;
	
	// For IPv6, fall back to simple string prefix comparison (limited support)
	// Full IPv6 CIDR matching requires 128-bit arithmetic which is complex in ucode
	if (!match(ip, /^(\d{1,3}\.){3}\d{1,3}$/))
		return ip == network_ip;  // For IPv6, exact match only
	
	if (!match(network_ip, /^(\d{1,3}\.){3}\d{1,3}$/))
		return false;
	
	let ip_parts = split(ip, '.');
	let net_parts = split(network_ip, '.');
	
	let ip_int = (int(ip_parts[0]) << 24) | (int(ip_parts[1]) << 16) | (int(ip_parts[2]) << 8) | int(ip_parts[3]);
	let net_int = (int(net_parts[0]) << 24) | (int(net_parts[1]) << 16) | (int(net_parts[2]) << 8) | int(net_parts[3]);
	
	// Create network mask
	let mask = 0;
	if (prefix > 0) {
		mask = (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
	}
	
	return ((ip_int & mask) == (net_int & mask));
}

// Check if IP is in whitelist
function is_ip_whitelisted(ip) {
	let ctx = cursor();
	
	// Check if IP whitelist is enabled
	let whitelist_enabled = ctx.get('2fa', 'settings', 'ip_whitelist_enabled');
	if (whitelist_enabled != '1')
		return false;
	
	// Get whitelist
	let whitelist = ctx.get_all('2fa', 'settings');
	if (!whitelist || !whitelist.ip_whitelist)
		return false;
	
	let ips = whitelist.ip_whitelist;
	if (type(ips) == 'string') {
		ips = [ips];
	}
	
	for (let entry in ips) {
		if (!entry || entry == '')
			continue;
		// Check if it's a CIDR range or exact match
		if (index(entry, '/') >= 0) {
			if (ip_in_cidr(ip, entry))
				return true;
		} else {
			if (ip == entry)
				return true;
		}
	}
	
	return false;
}

// Load rate limit state
function load_rate_limit_state() {
	let content = readfile(RATE_LIMIT_FILE);
	if (!content)
		return {};
	
	let state = json(content);
	if (!state)
		return {};
	
	return state;
}

// Save rate limit state
function save_rate_limit_state(state) {
	writefile(RATE_LIMIT_FILE, sprintf('%J', state));
}

// Check rate limit and record attempt
function check_rate_limit(ip) {
	let ctx = cursor();
	
	// Check if rate limiting is enabled
	let rate_limit_enabled = ctx.get('2fa', 'settings', 'rate_limit_enabled');
	if (rate_limit_enabled != '1')
		return { allowed: true, remaining: -1, locked_until: 0 };
	
	let max_attempts = int(ctx.get('2fa', 'settings', 'rate_limit_max_attempts') || '5');
	let window = int(ctx.get('2fa', 'settings', 'rate_limit_window') || '60');
	let lockout = int(ctx.get('2fa', 'settings', 'rate_limit_lockout') || '300');
	
	let now = time();
	let state = load_rate_limit_state();
	
	if (!state[ip]) {
		state[ip] = { attempts: [], locked_until: 0 };
	}
	
	let ip_state = state[ip];
	
	// Check if IP is locked out
	if (ip_state.locked_until > now) {
		return { allowed: false, remaining: 0, locked_until: ip_state.locked_until };
	}
	
	// Clean old attempts outside the window
	let recent_attempts = [];
	for (let attempt in ip_state.attempts) {
		if (attempt > (now - window)) {
			push(recent_attempts, attempt);
		}
	}
	ip_state.attempts = recent_attempts;
	
	// Check if within rate limit
	let remaining = max_attempts - length(ip_state.attempts);
	if (remaining <= 0) {
		// Lock out the IP
		ip_state.locked_until = now + lockout;
		ip_state.attempts = [];  // Reset attempts after lockout
		save_rate_limit_state(state);
		return { allowed: false, remaining: 0, locked_until: ip_state.locked_until };
	}
	
	save_rate_limit_state(state);
	return { allowed: true, remaining: remaining, locked_until: 0 };
}

// Record a failed login attempt
function record_failed_attempt(ip) {
	let ctx = cursor();
	
	// Check if rate limiting is enabled
	let rate_limit_enabled = ctx.get('2fa', 'settings', 'rate_limit_enabled');
	if (rate_limit_enabled != '1')
		return;
	
	let now = time();
	let state = load_rate_limit_state();
	
	if (!state[ip]) {
		state[ip] = { attempts: [], locked_until: 0 };
	}
	
	push(state[ip].attempts, now);
	save_rate_limit_state(state);
}

// Clear rate limit for an IP (on successful login)
function clear_rate_limit(ip) {
	let state = load_rate_limit_state();
	if (state[ip]) {
		delete state[ip];
		save_rate_limit_state(state);
	}
}

function generateBase32Key(keyLength) {
	let chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
	let key = '';
	
	// Read random bytes from /dev/urandom directly
	let fd = open('/dev/urandom', 'r');
	if (fd) {
		let data = fd.read(keyLength * 2);
		fd.close();
		
		// Convert each byte to base32 character
		for (let i = 0; i < length(data) && length(key) < keyLength; i++) {
			let num = ord(data, i);
			if (num != null && num >= 0) {
				key = key + substr(chars, num % 32, 1);
			}
		}
	}
	
	// Fallback - use time-based seed if random generation failed
	let fallbackSeed = time();
	while (length(key) < keyLength) {
		fallbackSeed = (fallbackSeed * 1103515245 + 12345) % 2147483648;
		key = key + substr(chars, fallbackSeed % 32, 1);
	}
	
	return key;
}

const methods = {
	// Check if 2FA is enabled - accessible without authentication for login flow
	isEnabled: {
		args: { username: '', client_ip: '' },
		call: function(request) {
			let ctx = cursor();
			let username = request.args.username || 'root';
			let client_ip = request.args.client_ip || '';

			// Sanitize username
			let safe_username = sanitize_username(username);
			if (!safe_username) {
				return { enabled: false };
			}

			// Check if 2FA is globally enabled
			let enabled = ctx.get('2fa', 'settings', 'enabled');
			if (enabled != '1') {
				return { enabled: false };
			}

			// Check if user has a key configured
			let key = ctx.get('2fa', safe_username, 'key');
			if (!key || key == '') {
				return { enabled: false };
			}

			// Check if IP is whitelisted (bypass 2FA)
			if (client_ip && is_ip_whitelisted(client_ip)) {
				return { enabled: false, whitelisted: true };
			}

			// Check system time calibration for TOTP
			// When time is uncalibrated, completely disable 2FA for safety
			// (users can still log in with just username/password)
			let otp_type = ctx.get('2fa', safe_username, 'type') || 'totp';
			if (otp_type == 'totp') {
				let time_check = check_time_calibration();
				if (!time_check.calibrated) {
					// Time not calibrated - disable 2FA completely to prevent lockout
					// Note: time_not_calibrated flag allows UI to show informative message
					// about why 2FA is disabled (useful for settings page warning)
					return { 
						enabled: false, 
						time_not_calibrated: true,
						current_time: time_check.current_time,
						min_valid_time: time_check.min_valid_time
					};
				}
			}

			return { enabled: true };
		}
	},

	// Check rate limit status
	checkRateLimit: {
		args: { client_ip: '' },
		call: function(request) {
			let client_ip = request.args.client_ip || '';
			if (!client_ip || client_ip == '') {
				return { allowed: true, remaining: -1, locked_until: 0 };
			}
			
			return check_rate_limit(client_ip);
		}
	},

	verifyOTP: {
		args: { otp: '', username: '', client_ip: '', is_backup_code: false },
		call: function(request) {
			let otp = request.args.otp;
			let username = request.args.username || 'root';
			let client_ip = request.args.client_ip || '';
			let is_backup_code = request.args.is_backup_code || false;
			let ctx = cursor();

			// Sanitize username to prevent command injection
			let safe_username = sanitize_username(username);
			if (!safe_username) {
				return { result: false };
			}

			// Check if 2FA is enabled
			let enabled = ctx.get('2fa', 'settings', 'enabled');
			if (enabled != '1') {
				// 2FA not enabled, allow login without OTP
				return { result: true };
			}

			// Check if user has a key configured
			let key = ctx.get('2fa', safe_username, 'key');
			if (!key || key == '') {
				// No key configured for this user, allow login without OTP
				return { result: true };
			}

			// Check if IP is whitelisted (bypass 2FA)
			if (client_ip && is_ip_whitelisted(client_ip)) {
				return { result: true, whitelisted: true };
			}

			// Check rate limit
			if (client_ip) {
				let rate_check = check_rate_limit(client_ip);
				if (!rate_check.allowed) {
					return { result: false, rate_limited: true, locked_until: rate_check.locked_until };
				}
			}

			if (!otp || otp == '') {
				if (client_ip) record_failed_attempt(client_ip);
				return { result: false };
			}
			
			// Trim and normalize input
			otp = trim(otp);
			
			// Check if this is a backup code (format: XXXX-XXXX or XXXXXXXX)
			// Backup codes always work regardless of time calibration
			if (is_backup_code || match(otp, /^[A-Za-z0-9]{4}-?[A-Za-z0-9]{4}$/)) {
				let backup_result = verify_backup_code(safe_username, otp);
				if (backup_result.valid) {
					// Clear rate limit on successful login
					if (client_ip) clear_rate_limit(client_ip);
					return { result: true, backup_code_used: true };
				}
				// If explicitly marked as backup code, don't try OTP
				if (is_backup_code) {
					if (client_ip) record_failed_attempt(client_ip);
					return { result: false, invalid_backup_code: true };
				}
			}
			
			// Get OTP type to determine verification strategy
			let otp_type = ctx.get('2fa', safe_username, 'type') || 'totp';
			
			if (otp_type == 'hotp') {
				// HOTP verification: use --no-increment to not consume the counter during verification
				// SECURITY: safe_username is validated by sanitize_username() to match [a-zA-Z0-9_.-]+
				let fd = popen('/usr/libexec/generate_otp.uc ' + safe_username + ' --no-increment');
				if (!fd) {
					if (client_ip) record_failed_attempt(client_ip);
					return { result: false };
				}

				let verify_otp = fd.read('all');
				fd.close();
				verify_otp = trim(verify_otp);

				if (constant_time_compare(verify_otp, otp)) {
					// OTP matches, now increment the counter for HOTP
					let counter = int(ctx.get('2fa', safe_username, 'counter') || '0');
					ctx.set('2fa', safe_username, 'counter', '' + (counter + 1));
					ctx.commit('2fa');
					// Clear rate limit on successful login
					if (client_ip) clear_rate_limit(client_ip);
					return { result: true };
				}
				if (client_ip) record_failed_attempt(client_ip);
				return { result: false };
			} else {
				// TOTP verification: check current window and adjacent windows (±1) for time drift tolerance
				// This handles cases where OTP was generated at the edge of a time window
				let step = int(ctx.get('2fa', safe_username, 'step') || '30');
				if (step <= 0) step = 30;  // Ensure valid step value
				let current_time = time();
				
				// Check window offsets: current (0), previous (-1), next (+1)
				// SECURITY: check_time is derived from time() (integer) and integer arithmetic only
				// safe_username is already validated by sanitize_username() to match [a-zA-Z0-9_.-]+
				for (let offset in [0, -1, 1]) {
					let check_time = int(current_time + (offset * step));  // Explicit int conversion
					let fd = popen('ucode /usr/libexec/generate_otp.uc ' + safe_username + ' --no-increment --time=' + check_time);
					if (!fd)
						continue;

					let verify_otp = fd.read('all');
					fd.close();
					verify_otp = trim(verify_otp);

					if (constant_time_compare(verify_otp, otp)) {
						// Clear rate limit on successful login
						if (client_ip) clear_rate_limit(client_ip);
						return { result: true };
					}
				}
				if (client_ip) record_failed_attempt(client_ip);
				return { result: false };
			}
		}
	},

	getConfig: {
		args: {},
		call: function(request) {
			let ctx = cursor();
			
			// Get IP whitelist
			let settings = ctx.get_all('2fa', 'settings');
			let ip_whitelist = [];
			if (settings && settings.ip_whitelist) {
				if (type(settings.ip_whitelist) == 'string') {
					if (settings.ip_whitelist != '')
						ip_whitelist = [settings.ip_whitelist];
				} else {
					ip_whitelist = filter(settings.ip_whitelist, (v) => v && v != '');
				}
			}
			
			return {
				enabled: ctx.get('2fa', 'settings', 'enabled') || '0',
				type: ctx.get('2fa', 'root', 'type') || 'totp',
				key: ctx.get('2fa', 'root', 'key') || '',
				step: ctx.get('2fa', 'root', 'step') || '30',
				counter: ctx.get('2fa', 'root', 'counter') || '0',
				ip_whitelist_enabled: ctx.get('2fa', 'settings', 'ip_whitelist_enabled') || '0',
				ip_whitelist: ip_whitelist,
				rate_limit_enabled: ctx.get('2fa', 'settings', 'rate_limit_enabled') || '0',
				rate_limit_max_attempts: ctx.get('2fa', 'settings', 'rate_limit_max_attempts') || '5',
				rate_limit_window: ctx.get('2fa', 'settings', 'rate_limit_window') || '60',
				rate_limit_lockout: ctx.get('2fa', 'settings', 'rate_limit_lockout') || '300'
			};
		}
	},

	setConfig: {
		args: {
			enabled: '',
			type: '',
			key: '',
			step: '',
			counter: '',
			ip_whitelist_enabled: '',
			ip_whitelist: [],
			rate_limit_enabled: '',
			rate_limit_max_attempts: '',
			rate_limit_window: '',
			rate_limit_lockout: ''
		},
		call: function(request) {
			let ctx = cursor();
			let args = request.args;

			// Validate and set enabled (must be '0' or '1')
			if (args.enabled != null && args.enabled != '') {
				if (args.enabled == '1' || args.enabled == '0')
					ctx.set('2fa', 'settings', 'enabled', args.enabled);
			}

			// Validate and set type (must be 'totp' or 'hotp')
			if (args.type != null && args.type != '') {
				if (args.type == 'totp' || args.type == 'hotp')
					ctx.set('2fa', 'root', 'type', args.type);
			}

			// Validate key (should be base32 characters only)
			if (args.key != null && args.key != '') {
				if (match(args.key, /^[A-Z2-7]+$/))
					ctx.set('2fa', 'root', 'key', args.key);
			}

			// Validate step (must be positive integer)
			if (args.step != null && args.step != '') {
				let stepVal = int(args.step);
				if (stepVal > 0)
					ctx.set('2fa', 'root', 'step', '' + stepVal);
			}

			// Validate counter (must be non-negative integer)
			if (args.counter != null && args.counter != '') {
				let counterVal = int(args.counter);
				if (counterVal >= 0)
					ctx.set('2fa', 'root', 'counter', '' + counterVal);
			}

			// IP whitelist enabled
			if (args.ip_whitelist_enabled != null && args.ip_whitelist_enabled != '') {
				if (args.ip_whitelist_enabled == '1' || args.ip_whitelist_enabled == '0')
					ctx.set('2fa', 'settings', 'ip_whitelist_enabled', args.ip_whitelist_enabled);
			}

			// IP whitelist
			if (args.ip_whitelist != null && length(args.ip_whitelist) > 0) {
				// First delete all existing entries
				ctx.delete('2fa', 'settings', 'ip_whitelist');
				
				// Add new entries
				let whitelist = args.ip_whitelist;
				if (type(whitelist) == 'string') {
					whitelist = [whitelist];
				}
				
				for (let ip in whitelist) {
					if (ip && ip != '' && is_valid_ip(ip)) {
						ctx.list_append('2fa', 'settings', 'ip_whitelist', ip);
					}
				}
			}

			// Rate limit settings
			if (args.rate_limit_enabled != null && args.rate_limit_enabled != '') {
				if (args.rate_limit_enabled == '1' || args.rate_limit_enabled == '0')
					ctx.set('2fa', 'settings', 'rate_limit_enabled', args.rate_limit_enabled);
			}

			if (args.rate_limit_max_attempts != null && args.rate_limit_max_attempts != '') {
				let val = int(args.rate_limit_max_attempts);
				if (val > 0 && val <= 100)
					ctx.set('2fa', 'settings', 'rate_limit_max_attempts', '' + val);
			}

			if (args.rate_limit_window != null && args.rate_limit_window != '') {
				let val = int(args.rate_limit_window);
				if (val > 0 && val <= 3600)
					ctx.set('2fa', 'settings', 'rate_limit_window', '' + val);
			}

			if (args.rate_limit_lockout != null && args.rate_limit_lockout != '') {
				let val = int(args.rate_limit_lockout);
				if (val > 0 && val <= 86400)
					ctx.set('2fa', 'settings', 'rate_limit_lockout', '' + val);
			}

			ctx.commit('2fa');

			return { result: true };
		}
	},

	generateKey: {
		args: { length: 0 },
		call: function(request) {
			let keyLength = request.args.length;
			if (!keyLength || keyLength < 1)
				keyLength = 16;
			
			let key = generateBase32Key(keyLength);

			return { key: key };
		}
	},

	// Get rate limit status for all IPs (admin view)
	getRateLimitStatus: {
		args: {},
		call: function(request) {
			let state = load_rate_limit_state();
			let now = time();
			let result = [];
			
			for (let ip in keys(state)) {
				let ip_state = state[ip];
				push(result, {
					ip: ip,
					attempts: length(ip_state.attempts),
					locked: ip_state.locked_until > now,
					locked_until: ip_state.locked_until
				});
			}
			
			return { entries: result };
		}
	},

	// Clear rate limit for specific IP (admin action)
	clearRateLimit: {
		args: { ip: '' },
		call: function(request) {
			let ip = request.args.ip;
			if (!ip || ip == '')
				return { result: false };
			
			clear_rate_limit(ip);
			return { result: true };
		}
	},

	// Clear all rate limits (admin action)
	clearAllRateLimits: {
		args: {},
		call: function(request) {
			unlink(RATE_LIMIT_FILE);
			return { result: true };
		}
	},

	// Get current TOTP code for verification (admin view)
	getCurrentCode: {
		args: { username: '' },
		call: function(request) {
			let username = request.args.username || 'root';
			let ctx = cursor();

			// Sanitize username - only alphanumeric, underscore, dash, dot allowed
			let safe_username = sanitize_username(username);
			if (!safe_username) {
				return { code: '', error: 'Invalid username' };
			}

			// Check if user has a key configured
			let key = ctx.get('2fa', safe_username, 'key');
			if (!key || key == '') {
				return { code: '', error: 'No key configured' };
			}

			// Get OTP type
			let otp_type = ctx.get('2fa', safe_username, 'type') || 'totp';

			if (otp_type == 'hotp') {
				// For HOTP, we show the next code without incrementing
				// safe_username is validated by sanitize_username() to only contain [a-zA-Z0-9_.-]
				let fd = popen("/usr/libexec/generate_otp.uc '" + safe_username + "' --no-increment");
				if (!fd)
					return { code: '', error: 'Failed to generate code' };

				let code = fd.read('all');
				fd.close();
				code = trim(code);

				let counter = ctx.get('2fa', safe_username, 'counter') || '0';
				return { code: code, type: 'hotp', counter: counter };
			} else {
				// For TOTP, check time calibration first
				let time_check = check_time_calibration();
				
				// For TOTP, generate the current code
				let step = int(ctx.get('2fa', safe_username, 'step') || '30');
				if (step <= 0) step = 30;
				let current_time = time();
				
				// safe_username is validated, current_time is an integer from time()
				let fd = popen("ucode /usr/libexec/generate_otp.uc '" + safe_username + "' --no-increment --time=" + current_time);
				if (!fd)
					return { code: '', error: 'Failed to generate code' };

				let code = fd.read('all');
				fd.close();
				code = trim(code);

				// Calculate time remaining in current period
				let time_remaining = step - (current_time % step);

				return { 
					code: code, 
					type: 'totp', 
					step: step, 
					time_remaining: time_remaining,
					time_calibrated: time_check.calibrated,
					current_time: time_check.current_time,
					min_valid_time: time_check.min_valid_time
				};
			}
		}
	},

	// Check system time calibration status
	checkTimeCalibration: {
		args: {},
		call: function(request) {
			return check_time_calibration();
		}
	},

	// Generate new backup codes for a user
	generateBackupCodes: {
		args: { username: '', count: 5 },
		call: function(request) {
			let username = request.args.username || 'root';
			let count = int(request.args.count) || 5;
			let ctx = cursor();

			// Sanitize username
			let safe_username = sanitize_username(username);
			if (!safe_username) {
				return { result: false, error: 'Invalid username' };
			}

			// Generate new backup codes
			let codes = generate_backup_codes(count);
			
			// Store only the hashes
			ctx.delete('2fa', safe_username, 'backup_codes');
			for (let code_obj in codes) {
				ctx.list_append('2fa', safe_username, 'backup_codes', code_obj.hash);
			}
			ctx.commit('2fa');

			// Return plaintext codes to user (only time they will see them)
			let plaintext_codes = [];
			for (let code_obj in codes) {
				push(plaintext_codes, code_obj.code);
			}

			return { 
				result: true, 
				codes: plaintext_codes,
				message: 'Save these backup codes in a safe place. Each code can only be used once.'
			};
		}
	},

	// Get backup codes count (not the codes themselves)
	getBackupCodesCount: {
		args: { username: '' },
		call: function(request) {
			let username = request.args.username || 'root';
			let ctx = cursor();

			// Sanitize username
			let safe_username = sanitize_username(username);
			if (!safe_username) {
				return { count: 0 };
			}

			// Get stored backup codes
			let user_config = ctx.get_all('2fa', safe_username);
			if (!user_config || !user_config.backup_codes) {
				return { count: 0 };
			}

			let stored_codes = user_config.backup_codes;
			if (type(stored_codes) == 'string') {
				return { count: (stored_codes && stored_codes != '') ? 1 : 0 };
			}

			// Filter out empty entries
			let valid_count = 0;
			for (let code in stored_codes) {
				if (code && code != '') valid_count++;
			}

			return { count: valid_count };
		}
	},

	// Clear all backup codes for a user
	clearBackupCodes: {
		args: { username: '' },
		call: function(request) {
			let username = request.args.username || 'root';
			let ctx = cursor();

			// Sanitize username
			let safe_username = sanitize_username(username);
			if (!safe_username) {
				return { result: false, error: 'Invalid username' };
			}

			ctx.delete('2fa', safe_username, 'backup_codes');
			ctx.commit('2fa');

			return { result: true };
		}
	}
};

return { '2fa': methods };
