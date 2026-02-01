// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2024 LuCI 2FA Plugin Contributors
//
// LuCI Authentication Plugin: Two-Factor Authentication (2FA/OTP)
//
// This plugin implements TOTP/HOTP verification as an additional
// authentication factor for LuCI login.

// Constant-time string comparison to prevent timing attacks
function constant_time_compare(a, b) {
	if (length(a) != length(b))
		return false;

	let result = 0;
	for (let i = 0; i < length(a); i++) {
		result = result | (ord(a, i) ^ ord(b, i));
	}
	return result == 0;
}

// Sanitize username to prevent command injection
function sanitize_username(username) {
	if (!match(username, /^[a-zA-Z0-9_.+-]+$/))
		return null;
	return username;
}

// Check if 2FA is enabled for a user
function is_2fa_enabled(username) {
	let uci = require('uci');
	let ctx = uci.cursor();
	
	// Check if 2FA is globally enabled
	let enabled = ctx.get('2fa', 'settings', 'enabled');
	if (enabled != '1')
		return false;

	// Sanitize username
	let safe_username = sanitize_username(username);
	if (!safe_username)
		return false;

	// Check if user has a key configured
	let key = ctx.get('2fa', safe_username, 'key');
	if (!key || key == '')
		return false;

	return true;
}

// Verify OTP for user
function verify_otp(username, otp) {
	let fs = require('fs');
	let uci = require('uci');
	let ctx = uci.cursor();
	
	if (!otp || otp == '')
		return false;

	let safe_username = sanitize_username(username);
	if (!safe_username)
		return false;

	// Trim and normalize input
	otp = trim(otp);
	
	// Validate OTP format: must be exactly 6 digits
	if (!match(otp, /^[0-9]{6}$/))
		return false;

	// Get OTP type to determine verification strategy
	let otp_type = ctx.get('2fa', safe_username, 'type') || 'totp';

	// SECURITY: We use string form of popen() because the array form doesn't
	// work in current ucode versions on OpenWrt. Shell injection is prevented by:
	// 1. sanitize_username() above returns null for any input not matching [a-zA-Z0-9_.+-]
	// 2. We only proceed if safe_username is not null (sanitization passed)
	// 3. The character set [a-zA-Z0-9_.+-] cannot form shell metacharacters

	if (otp_type == 'hotp') {
		// HOTP verification: use --no-increment to not consume the counter during verification
		let fd = fs.popen('/usr/libexec/generate_otp.uc ' + safe_username + ' --no-increment', 'r');
		if (!fd)
			return false;

		let expected_otp = fd.read('all');
		fd.close();
		expected_otp = trim(expected_otp);
		
		if (!match(expected_otp, /^[0-9]{6}$/))
			return false;

		if (constant_time_compare(expected_otp, otp)) {
			// OTP matches, now increment the counter for HOTP
			let counter = int(ctx.get('2fa', safe_username, 'counter') || '0');
			ctx.set('2fa', safe_username, 'counter', '' + (counter + 1));
			ctx.commit('2fa');
			return true;
		}
		return false;
	} else {
		// TOTP verification: check current window and adjacent windows (±1) for time drift tolerance
		let step = int(ctx.get('2fa', safe_username, 'step') || '30');
		let current_time = time();
		
		// Check window offsets: current (0), previous (-1), next (+1)
		for (let offset in [0, -1, 1]) {
			let check_time = current_time + (offset * step);
			let fd = fs.popen('/usr/libexec/generate_otp.uc ' + safe_username + ' --no-increment --time=' + check_time, 'r');
			if (!fd)
				continue;

			let expected_otp = fd.read('all');
			fd.close();
			expected_otp = trim(expected_otp);
			
			if (!match(expected_otp, /^[0-9]{6}$/))
				continue;

			if (constant_time_compare(expected_otp, otp)) {
				return true;
			}
		}
		return false;
	}
}

return {
	// Plugin identifier
	name: '2fa',
	
	// Priority (lower = executed first)
	priority: 10,

	/**
	 * Check if this plugin requires additional authentication
	 * 
	 * @param http - HTTP request object
	 * @param user - Username being authenticated
	 * @returns Object with:
	 *   - required: bool - true if 2FA verification is needed
	 *   - fields: array - Form fields to add to sysauth template
	 *   - message: string - Message to display
	 */
	check: function(http, user) {
		if (!is_2fa_enabled(user)) {
			return { required: false };
		}

		return {
			required: true,
			fields: [
				{
					name: 'luci_otp',
					type: 'text',
					label: 'One-Time Password',
					placeholder: '123456',
					inputmode: 'numeric',
					pattern: '[0-9]*',
					maxlength: 6,
					autocomplete: 'one-time-code',
					required: true
				}
			],
			message: 'Please enter your one-time password from your authenticator app.'
		};
	},

	/**
	 * Verify the additional authentication
	 * 
	 * @param http - HTTP request object
	 * @param user - Username being authenticated
	 * @returns Object with:
	 *   - success: bool - true if verification succeeded
	 *   - message: string - Error message if failed
	 */
	verify: function(http, user) {
		let otp = http.formvalue('luci_otp');
		
		// Trim input immediately for consistent validation
		if (otp)
			otp = trim(otp);
		
		if (!otp || otp == '') {
			return {
				success: false,
				message: 'Please enter your one-time password.'
			};
		}

		if (!verify_otp(user, otp)) {
			return {
				success: false,
				message: 'Invalid one-time password. Please try again.'
			};
		}

		return { success: true };
	}
};
