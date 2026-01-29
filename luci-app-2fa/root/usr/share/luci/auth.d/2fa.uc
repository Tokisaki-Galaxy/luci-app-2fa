// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2024 LuCI 2FA Plugin Contributors
//
// LuCI Authentication Plugin: Two-Factor Authentication (2FA/OTP)
//
// This plugin implements TOTP/HOTP verification as an additional
// authentication factor for LuCI login.

import { cursor } from 'uci';
import { popen } from 'fs';

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
	if (!match(username, /^[a-zA-Z0-9_\-\.]+$/))
		return null;
	return username;
}

// Check if 2FA is enabled for a user
function is_2fa_enabled(username) {
	let ctx = cursor();
	
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
	if (!otp || otp == '')
		return false;

	let safe_username = sanitize_username(username);
	if (!safe_username)
		return false;

	// Trim and normalize input
	otp = trim(otp);

	let fd = popen('/usr/libexec/generate_otp.uc ' + safe_username);
	if (!fd)
		return false;

	let verify_otp = fd.read('all');
	fd.close();

	// Trim generated OTP
	verify_otp = trim(verify_otp);

	// Use constant-time comparison to prevent timing attacks
	return constant_time_compare(verify_otp, otp);
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
