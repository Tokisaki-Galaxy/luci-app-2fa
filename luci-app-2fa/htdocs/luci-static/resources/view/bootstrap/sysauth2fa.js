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

		// Determine if we're in 2FA mode based on whether OTP field is visible
		var requires2FA = otpInput && otpInput.parentElement.parentElement.style.display !== 'none';

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
			// Basic validation
			if (!requires2FA) {
				// Normal login mode
				var username = usernameInput ? usernameInput.value : '';
				var password = passwordInput ? passwordInput.value : '';

				if (!username) {
					if (usernameInput) usernameInput.focus();
					return;
				}
				if (!password) {
					if (passwordInput) passwordInput.focus();
					return;
				}

				// Store password for 2FA step
				try {
					sessionStorage.setItem('luci_2fa_pending_pw', password);
				} catch(e) {}
			} else {
				// 2FA mode
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
		if (requires2FA && otpInput) {
			otpInput.focus();
		} else if (passwordInput && passwordInput.type !== 'hidden') {
			passwordInput.focus();
		} else if (usernameInput) {
			usernameInput.focus();
		}

		return '';
	},

	addFooter: function() {}
});
