'use strict';
'require view';
'require form';
'require ui';
'require uci';
'require rpc';
'require uqr';

var callGetConfig = rpc.declare({
	object: '2fa',
	method: 'getConfig',
	expect: { }
});

var callSetConfig = rpc.declare({
	object: '2fa',
	method: 'setConfig',
	params: [
		'enabled', 'type', 'key', 'step', 'counter',
		'ip_whitelist_enabled', 'ip_whitelist',
		'rate_limit_enabled', 'rate_limit_max_attempts',
		'rate_limit_window', 'rate_limit_lockout'
	]
});

var callGenerateKey = rpc.declare({
	object: '2fa',
	method: 'generateKey',
	params: [ 'length' ],
	expect: { key: '' }
});

var callGetRateLimitStatus = rpc.declare({
	object: '2fa',
	method: 'getRateLimitStatus',
	expect: { entries: [] }
});

var callClearRateLimit = rpc.declare({
	object: '2fa',
	method: 'clearRateLimit',
	params: [ 'ip' ]
});

var callClearAllRateLimits = rpc.declare({
	object: '2fa',
	method: 'clearAllRateLimits'
});

var CBIGenerateOTPKey = form.Value.extend({
	renderWidget: function(section_id, option_id, cfgvalue) {
		var inputEl = E('input', {
			'id': this.cbid(section_id),
			'type': 'text',
			'class': 'cbi-input-text',
			'value': cfgvalue || '',
			'readonly': true
		});

		return E('div', { 'class': 'cbi-value-field' }, [
			inputEl,
			E('br'),
			E('span', { 'class': 'control-group' }, [
				E('button', {
					'class': 'cbi-button cbi-button-action',
					'click': ui.createHandlerFn(this, function() {
						return callGenerateKey(16).then(function(res) {
							inputEl.value = res.key || res;
							// Trigger change event
							var event = document.createEvent('Event');
							event.initEvent('change', true, true);
							inputEl.dispatchEvent(event);
						});
					})
				}, _('Generate Key'))
			])
		]);
	},

	formvalue: function(section_id) {
		var inputEl = document.getElementById(this.cbid(section_id));
		return inputEl ? inputEl.value : null;
	}
});

var CBIQRCode = form.DummyValue.extend({
	renderWidget: function(section_id, option_id, cfgvalue) {
		var type = uci.get('2fa', 'root', 'type') || 'totp';
		var key = uci.get('2fa', 'root', 'key') || '';
		var issuer = 'OpenWrt';
		var label = 'root';
		var qrDiv = E('div', { 'id': 'qr-code-container' });

		if (!key) {
			qrDiv.appendChild(E('em', {}, _('Generate a key first to see QR code')));
			return qrDiv;
		}

		var option;
		if (type == 'hotp') {
			var counter = uci.get('2fa', 'root', 'counter') || '0';
			option = 'counter=' + counter;
		} else {
			var step = uci.get('2fa', 'root', 'step') || '30';
			option = 'period=' + step;
		}

		var otpauth_str = 'otpauth://' + type + '/' + encodeURIComponent(issuer) + ':' + encodeURIComponent(label) + '?secret=' + key + '&issuer=' + encodeURIComponent(issuer) + '&' + option;

		var svgContent = uqr.renderSVG(otpauth_str, { pixelSize: 4 });
		qrDiv.innerHTML = svgContent;
		
		return E('div', {}, [
			qrDiv,
			E('br'),
			E('em', {}, _('Scan this QR code with your authenticator app')),
			E('br'),
			E('code', { 'style': 'word-break: break-all; font-size: 10px;' }, otpauth_str)
		]);
	}
});

var CBIIPWhitelist = form.DynamicList.extend({
	datatype: 'or(ip4addr,ip6addr,cidr4,cidr6)'
});

var CBIRateLimitStatus = form.DummyValue.extend({
	renderWidget: function(section_id, option_id, cfgvalue) {
		var containerDiv = E('div', { 'id': 'rate-limit-status-container' });
		
		var refreshBtn = E('button', {
			'class': 'cbi-button cbi-button-action',
			'style': 'margin-bottom: 10px;',
			'click': ui.createHandlerFn(this, function() {
				return this.refreshStatus(containerDiv);
			})
		}, _('Refresh'));
		
		var clearAllBtn = E('button', {
			'class': 'cbi-button cbi-button-negative',
			'style': 'margin-left: 10px; margin-bottom: 10px;',
			'click': ui.createHandlerFn(this, function() {
				return callClearAllRateLimits().then(function() {
					ui.addNotification(null, E('p', _('All rate limits cleared.')), 'info');
					return this.refreshStatus(containerDiv);
				}.bind(this));
			})
		}, _('Clear All'));
		
		var statusDiv = E('div', { 'id': 'rate-limit-status-list' }, [
			E('em', {}, _('Click "Refresh" to load rate limit status'))
		]);
		
		return E('div', {}, [
			E('div', {}, [refreshBtn, clearAllBtn]),
			statusDiv
		]);
	},
	
	refreshStatus: function(container) {
		var statusDiv = container.querySelector('#rate-limit-status-list') || container;
		statusDiv.innerHTML = '';
		statusDiv.appendChild(E('em', {}, _('Loading...')));
		
		return callGetRateLimitStatus().then(function(result) {
			statusDiv.innerHTML = '';
			
			if (!result.entries || result.entries.length === 0) {
				statusDiv.appendChild(E('em', {}, _('No rate limit entries.')));
				return;
			}
			
			var table = E('table', { 'class': 'table' }, [
				E('tr', { 'class': 'tr table-titles' }, [
					E('th', { 'class': 'th' }, _('IP Address')),
					E('th', { 'class': 'th' }, _('Failed Attempts')),
					E('th', { 'class': 'th' }, _('Status')),
					E('th', { 'class': 'th' }, _('Actions'))
				])
			]);
			
			result.entries.forEach(function(entry) {
				var status = entry.locked ? 
					_('Locked until ') + new Date(entry.locked_until * 1000).toLocaleString() :
					_('Active');
				var statusClass = entry.locked ? 'color: red;' : '';
				
				var clearBtn = E('button', {
					'class': 'cbi-button cbi-button-remove',
					'click': ui.createHandlerFn(this, function() {
						return callClearRateLimit(entry.ip).then(function() {
							ui.addNotification(null, E('p', _('Rate limit cleared for ') + entry.ip), 'info');
							return this.refreshStatus(container);
						}.bind(this));
					}.bind(this))
				}, _('Clear'));
				
				table.appendChild(E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td' }, entry.ip),
					E('td', { 'class': 'td' }, String(entry.attempts)),
					E('td', { 'class': 'td', 'style': statusClass }, status),
					E('td', { 'class': 'td' }, clearBtn)
				]));
			}.bind(this));
			
			statusDiv.appendChild(table);
		}.bind(this)).catch(function(err) {
			statusDiv.innerHTML = '';
			statusDiv.appendChild(E('em', { 'style': 'color: red;' }, _('Error loading status: ') + err.message));
		});
	}
});

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('2fa'),
			callGetConfig()
		]);
	},

	render: function(data) {
		var m, s, o;

		m = new form.Map('2fa', _('2-Factor Authentication'),
			_('Configure two-factor authentication for LuCI login. ' +
			  'When enabled, you will need to enter a one-time password from your authenticator app in addition to your username and password.'));

		// Basic Settings
		s = m.section(form.NamedSection, 'settings', 'settings', _('Basic Settings'));
		s.anonymous = true;

		o = s.option(form.Flag, 'enabled', _('Enable 2FA'),
			_('Enable two-factor authentication for LuCI login'));
		o.rmempty = false;

		// Authentication Settings (OTP)
		s = m.section(form.NamedSection, 'root', 'login', _('OTP Settings'),
			_('Configure OTP settings for root user'));
		s.anonymous = true;

		o = s.option(CBIGenerateOTPKey, 'key', _('Secret Key'),
			_('The secret key used to generate OTP codes. Generate a new key to set up 2FA.'));

		o = s.option(form.ListValue, 'type', _('OTP Type'),
			_('TOTP (Time-based) requires synchronized time. HOTP (Counter-based) works offline.'));
		o.value('totp', _('TOTP (Time-based)'));
		o.value('hotp', _('HOTP (Counter-based)'));
		o.default = 'totp';

		o = s.option(form.Value, 'step', _('Time Step'),
			_('Time step in seconds for TOTP (default: 30)'));
		o.depends('type', 'totp');
		o.default = '30';
		o.datatype = 'uinteger';

		o = s.option(form.Value, 'counter', _('Counter'),
			_('Current counter value for HOTP'));
		o.depends('type', 'hotp');
		o.default = '0';
		o.datatype = 'uinteger';

		o = s.option(CBIQRCode, '_qrcode', _('QR Code'),
			_('Scan with your authenticator app (Google Authenticator, Authy, etc.)'));

		// IP Whitelist Settings
		s = m.section(form.NamedSection, 'settings', 'settings', _('IP Whitelist'),
			_('Allow certain IP addresses or ranges to bypass 2FA authentication. ' +
			  'This is useful for trusted networks like your local LAN.'));
		s.anonymous = true;

		o = s.option(form.Flag, 'ip_whitelist_enabled', _('Enable IP Whitelist'),
			_('When enabled, IP addresses in the whitelist will bypass 2FA'));
		o.rmempty = false;

		o = s.option(CBIIPWhitelist, 'ip_whitelist', _('Whitelisted IPs'),
			_('Enter IP addresses or CIDR ranges that can bypass 2FA. ' +
			  'Examples: 192.168.1.100, 192.168.1.0/24, 10.0.0.0/8'));
		o.depends('ip_whitelist_enabled', '1');
		o.placeholder = '192.168.1.0/24';

		// Rate Limiting / Brute Force Protection
		s = m.section(form.NamedSection, 'settings', 'settings', _('Brute Force Protection'),
			_('Protect against brute force attacks by limiting failed login attempts. ' +
			  'After too many failed attempts, the IP will be temporarily blocked.'));
		s.anonymous = true;

		o = s.option(form.Flag, 'rate_limit_enabled', _('Enable Brute Force Protection'),
			_('When enabled, IPs with too many failed login attempts will be temporarily blocked'));
		o.rmempty = false;

		o = s.option(form.Value, 'rate_limit_max_attempts', _('Max Attempts'),
			_('Maximum number of failed login attempts allowed within the time window'));
		o.depends('rate_limit_enabled', '1');
		o.default = '5';
		o.datatype = 'range(1,100)';
		o.placeholder = '5';

		o = s.option(form.Value, 'rate_limit_window', _('Time Window (seconds)'),
			_('Time window in seconds for counting failed attempts'));
		o.depends('rate_limit_enabled', '1');
		o.default = '60';
		o.datatype = 'range(1,3600)';
		o.placeholder = '60';

		o = s.option(form.Value, 'rate_limit_lockout', _('Lockout Duration (seconds)'),
			_('Duration in seconds to block an IP after exceeding the max attempts'));
		o.depends('rate_limit_enabled', '1');
		o.default = '300';
		o.datatype = 'range(1,86400)';
		o.placeholder = '300';

		o = s.option(CBIRateLimitStatus, '_rate_limit_status', _('Rate Limit Status'),
			_('View and manage currently rate-limited IP addresses'));
		o.depends('rate_limit_enabled', '1');

		return m.render();
	}
});
