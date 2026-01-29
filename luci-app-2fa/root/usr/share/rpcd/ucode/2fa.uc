// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2024 Christian Marangi <ansuelsmth@gmail.com>

'use strict';

import { popen, open } from 'fs';
import { cursor } from 'uci';

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
	verifyOTP: {
		args: { otp: '' },
		call: function(request) {
			let otp = request.args.otp;
			let ctx = cursor();

			// Check if 2FA is enabled
			let enabled = ctx.get('2fa', 'settings', 'enabled');
			if (enabled != '1') {
				// 2FA not enabled, allow login without OTP
				return { result: true };
			}

			if (!otp || otp == '')
				return { result: false };
			
			// Trim and normalize input
			otp = trim(otp);
			
			let fd = popen('/usr/libexec/generate_otp.uc');
			if (!fd)
				return { result: false };

			let verify_otp = fd.read('all');
			fd.close();
			
			// Trim generated OTP
			verify_otp = trim(verify_otp);

			return { result: verify_otp == otp };
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
