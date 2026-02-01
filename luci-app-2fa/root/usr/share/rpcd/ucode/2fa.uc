// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2024 Christian Marangi <ansuelsmth@gmail.com>

'use strict';

import { popen, open, glob, lsdir } from 'fs';
import { cursor } from 'uci';

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
	// Only allow alphanumeric characters, underscore, dash, and dot
	if (!match(username, /^[a-zA-Z0-9_.-]+$/))
		return null;
	return username;
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
		args: { username: '' },
		call: function(request) {
			let ctx = cursor();
			let username = request.args.username || 'root';

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

			return { enabled: true };
		}
	},

	verifyOTP: {
		args: { otp: '', username: '' },
		call: function(request) {
			let otp = request.args.otp;
			let username = request.args.username || 'root';
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

			if (!otp || otp == '')
				return { result: false };
			
			// Trim and normalize input
			otp = trim(otp);
			
			// Get OTP type to determine verification strategy
			let otp_type = ctx.get('2fa', safe_username, 'type') || 'totp';
			
			if (otp_type == 'hotp') {
				// HOTP verification: use --no-increment to not consume the counter during verification
				let fd = popen('/usr/libexec/generate_otp.uc ' + safe_username + ' --no-increment');
				if (!fd)
					return { result: false };

				let verify_otp = fd.read('all');
				fd.close();
				verify_otp = trim(verify_otp);

				if (constant_time_compare(verify_otp, otp)) {
					// OTP matches, now increment the counter for HOTP
					let counter = int(ctx.get('2fa', safe_username, 'counter') || '0');
					ctx.set('2fa', safe_username, 'counter', '' + (counter + 1));
					ctx.commit('2fa');
					return { result: true };
				}
				return { result: false };
			} else {
				// TOTP verification: check current window and adjacent windows (±1) for time drift tolerance
				// This handles cases where OTP was generated at the edge of a time window
				let step = int(ctx.get('2fa', safe_username, 'step') || '30');
				let current_time = time();
				
				// Check window offsets: current (0), previous (-1), next (+1)
				for (let offset in [0, -1, 1]) {
					let check_time = current_time + (offset * step);
					let fd = popen('/usr/libexec/generate_otp.uc ' + safe_username + ' --no-increment --time=' + check_time);
					if (!fd)
						continue;

					let verify_otp = fd.read('all');
					fd.close();
					verify_otp = trim(verify_otp);

					if (constant_time_compare(verify_otp, otp)) {
						return { result: true };
					}
				}
				return { result: false };
			}
		}
	},

	getConfig: {
		args: {},
		call: function(request) {
			let ctx = cursor();
			
			return {
				enabled: ctx.get('2fa', 'settings', 'enabled') || '0',
				type: ctx.get('2fa', 'root', 'type') || 'totp',
				key: ctx.get('2fa', 'root', 'key') || '',
				step: ctx.get('2fa', 'root', 'step') || '30',
				counter: ctx.get('2fa', 'root', 'counter') || '0'
			};
		}
	},

	setConfig: {
		args: { enabled: '', type: '', key: '', step: '', counter: '' },
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
	}
};

return { '2fa': methods };
