'use strict';
'require ui';
'require view';

return view.extend({
	render: function() {
		var form = document.querySelector('form');
		var btn = document.querySelector('button');
		var otpInput = document.getElementById('luci_otp');
		var passwordInput = document.getElementById('luci_password');
		var usernameInput = document.getElementById('luci_username');

		// Determine if we're in 2FA mode based on whether OTP field exists
		var requires2FA = otpInput !== null;

		var dlg = ui.showModal(
			requires2FA ? _('Two-Factor Authentication') : _('Authorization Required'),
			Array.from(document.querySelectorAll('section > *')),
			'login'
		);

		function showSpinner(message) {
			dlg.querySelectorAll('*').forEach(function(node) {
				node.style.display = 'none';
			});
			var spinner = E('div', { class: 'spinning' }, message);
			dlg.appendChild(spinner);
		}

		function handleSubmit() {
			var password = passwordInput ? passwordInput.value : '';
			
			if (!password) {
				if (passwordInput) passwordInput.focus();
				return;
			}

			if (!requires2FA) {
				// Normal login mode
				var username = usernameInput ? usernameInput.value : '';

				if (!username) {
					if (usernameInput) usernameInput.focus();
					return;
				}
			} else {
				// 2FA mode - also need OTP
				var otp = otpInput ? otpInput.value : '';

				if (!otp || otp.length < 6) {
					if (otpInput) otpInput.focus();
					return;
				}
			}

			showSpinner(requires2FA ? _('Verifying…') : _('Logging in…'));
			form.submit();
		}

		form.addEventListener('keypress', function(ev) {
			if (ev.key === 'Enter') {
				ev.preventDefault();
				btn.click();
			}
		});

		btn.addEventListener('click', function() {
			handleSubmit();
		});

		// Focus appropriate input
		if (passwordInput) {
			passwordInput.focus();
		} else if (usernameInput) {
			usernameInput.focus();
		}

		return '';
	},

	addFooter: function() {}
});
