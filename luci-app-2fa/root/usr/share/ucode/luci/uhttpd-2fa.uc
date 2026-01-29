{%
// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2024 LuCI-App-2FA Contributors
//
// This file provides a wrapper around the LuCI dispatcher that intercepts
// login requests and injects 2FA verification when enabled.
// It does NOT modify any system files - it's loaded via uhttpd configuration.

import dispatch from 'luci.dispatcher';
import request from 'luci.http';
import { connect } from 'ubus';
import { cursor } from 'uci';
import { popen } from 'fs';
import { openlog, syslog, closelog, LOG_INFO, LOG_WARNING, LOG_AUTHPRIV } from 'log';

let ubus = connect();

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
	if (!match(username, /^[a-zA-Z0-9_\-\.]+$/))
		return null;
	return username;
}

// Check if 2FA is enabled for a user
function is_2fa_enabled(username) {
	if (!username)
		return false;

	let safe_username = sanitize_username(username);
	if (!safe_username)
		return false;

	let ctx = cursor();
	let enabled = ctx.get('2fa', 'settings', 'enabled');
	if (enabled != '1')
		return false;

	let key = ctx.get('2fa', safe_username, 'key');
	if (!key || key == '')
		return false;

	return true;
}

// Verify 2FA OTP for a user
function verify_2fa_otp(username, otp) {
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

// Check if this is a login request with credentials
function is_login_request(req) {
	let user = req.formvalue('luci_username');
	let pass = req.formvalue('luci_password');
	return (user != null && pass != null);
}

// Check if session exists and is valid
function check_session(req) {
	let cookie_name = 'sysauth_http';
	let sid = req.getcookie(cookie_name);
	
	if (!sid) {
		cookie_name = 'sysauth_https';
		sid = req.getcookie(cookie_name);
	}
	
	if (!sid)
		return null;
	
	let sdat = ubus.call("session", "get", { ubus_rpc_session: sid });
	if (type(sdat?.values?.token) == 'string')
		return { sid: sid, data: sdat.values };
	
	return null;
}

// Destroy a session
function destroy_session(sid) {
	if (sid)
		ubus.call("session", "destroy", { ubus_rpc_session: sid });
}

// Render 2FA login page
function render_2fa_page(req, username, otp_error) {
	req.status(403, 'Forbidden');
	req.header('Content-Type', 'text/html; charset=UTF-8');
	req.header('X-LuCI-Login-Required', 'yes');
	req.header('X-LuCI-2FA-Required', 'yes');
	
	let error_msg = '';
	if (otp_error) {
		error_msg = `
		<div class="alert-message warning" style="background-color: #fff3cd; border: 1px solid #ffc107; color: #856404; padding: 15px; margin-bottom: 20px; border-radius: 4px;">
			<p style="margin: 0;">Invalid one-time password! Please try again.</p>
		</div>`;
	}
	
	let html = `<!DOCTYPE html>
<html lang="en">
<head>
	<meta charset="utf-8">
	<meta name="viewport" content="width=device-width, initial-scale=1">
	<title>Two-Factor Authentication - LuCI</title>
	<style>
		body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; background: #f5f5f5; margin: 0; padding: 20px; display: flex; justify-content: center; align-items: center; min-height: 100vh; }
		.login-container { background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); max-width: 400px; width: 100%; }
		h2 { margin: 0 0 20px 0; color: #333; text-align: center; }
		.form-group { margin-bottom: 15px; }
		label { display: block; margin-bottom: 5px; font-weight: 500; color: #555; }
		input[type="password"], input[type="text"] { width: 100%; padding: 10px; border: 1px solid #ddd; border-radius: 4px; box-sizing: border-box; font-size: 16px; }
		input:focus { border-color: #007bff; outline: none; box-shadow: 0 0 0 2px rgba(0,123,255,0.25); }
		button { width: 100%; padding: 12px; background: #007bff; color: white; border: none; border-radius: 4px; font-size: 16px; cursor: pointer; }
		button:hover { background: #0056b3; }
		.help-text { font-size: 12px; color: #666; margin-top: 5px; }
		.user-info { background: #e9ecef; padding: 10px; border-radius: 4px; margin-bottom: 20px; text-align: center; }
	</style>
</head>
<body>
	<div class="login-container">
		<h2>Two-Factor Authentication</h2>
		${error_msg}
		<div class="user-info">
			Logging in as: <strong>${username}</strong>
		</div>
		<form method="post">
			<input type="hidden" name="luci_username" value="${username}">
			<div class="form-group">
				<label for="luci_password">Password</label>
				<input type="password" id="luci_password" name="luci_password" required autofocus>
			</div>
			<div class="form-group">
				<label for="luci_otp">One-Time Password</label>
				<input type="text" id="luci_otp" name="luci_otp" inputmode="numeric" pattern="[0-9]*" maxlength="6" autocomplete="one-time-code" placeholder="123456" required>
				<div class="help-text">Enter the 6-digit code from your authenticator app</div>
			</div>
			<button type="submit">Verify &amp; Login</button>
		</form>
	</div>
</body>
</html>`;
	
	req.write(html);
}

// Wrapper dispatch function that injects 2FA verification
function dispatch_with_2fa(req) {
	// Check if 2FA is globally enabled
	let ctx = cursor();
	let tfa_enabled = ctx.get('2fa', 'settings', 'enabled');
	
	// If 2FA is not enabled, just use normal dispatch
	if (tfa_enabled != '1') {
		dispatch(req);
		return;
	}
	
	// Check if this is a login attempt
	if (!is_login_request(req)) {
		// Not a login request, proceed normally
		dispatch(req);
		return;
	}
	
	let username = req.formvalue('luci_username');
	let password = req.formvalue('luci_password');
	let otp = req.formvalue('luci_otp');
	
	// Check if 2FA is enabled for this user
	if (!is_2fa_enabled(username)) {
		// 2FA not enabled for this user, proceed normally
		dispatch(req);
		return;
	}
	
	// 2FA is required - check if OTP was provided
	if (!otp || otp == '') {
		// No OTP provided, show 2FA form
		openlog('uhttpd-2fa.uc');
		syslog(LOG_INFO|LOG_AUTHPRIV, sprintf("luci: 2FA required for %s from %s",
			username || "?", req.getenv("REMOTE_ADDR") || "?"));
		closelog();
		
		render_2fa_page(req, username, false);
		req.close();
		return;
	}
	
	// Verify the OTP first (before letting the password check happen)
	if (!verify_2fa_otp(username, otp)) {
		// OTP invalid
		openlog('uhttpd-2fa.uc');
		syslog(LOG_WARNING|LOG_AUTHPRIV, sprintf("luci: failed 2FA verification for %s from %s",
			username || "?", req.getenv("REMOTE_ADDR") || "?"));
		closelog();
		
		render_2fa_page(req, username, true);
		req.close();
		return;
	}
	
	// OTP verified successfully, let the normal dispatcher handle password verification
	openlog('uhttpd-2fa.uc');
	syslog(LOG_INFO|LOG_AUTHPRIV, sprintf("luci: 2FA verified for %s from %s",
		username || "?", req.getenv("REMOTE_ADDR") || "?"));
	closelog();
	
	dispatch(req);
}

global.handle_request = function(env) {
	let req = request(env, uhttpd.recv, uhttpd.send);

	try {
		dispatch_with_2fa(req);
	}
	catch (ex) {
		// If anything fails in our 2FA wrapper, fall back to normal dispatch
		// This ensures users are never locked out due to our code errors
		warn(`2FA wrapper error: ${ex}, falling back to normal dispatch\n`);
		try {
			dispatch(req);
		}
		catch (ex2) {
			warn(`Dispatch error: ${ex2}\n`);
		}
	}

	req.close();
};
