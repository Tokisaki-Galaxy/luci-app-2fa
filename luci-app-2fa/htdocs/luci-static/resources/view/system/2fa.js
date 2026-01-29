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
	params: [ 'enabled', 'type', 'key', 'step', 'counter' ]
});

var callGenerateKey = rpc.declare({
	object: '2fa',
	method: 'generateKey',
	params: [ 'length' ],
	expect: { key: '' }
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

		s = m.section(form.NamedSection, 'settings', 'settings', _('Settings'));
		s.anonymous = true;

		o = s.option(form.Flag, 'enabled', _('Enable 2FA'),
			_('Enable two-factor authentication for LuCI login'));
		o.rmempty = false;

		s = m.section(form.NamedSection, 'root', 'login', _('Authentication Settings'),
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

		return m.render();
	}
});
