'use strict';
'require view';
'require dom';
'require ui';
'require uci';
'require rpc';

var callListAuthPlugins = rpc.declare({
	object: '2fa',
	method: 'listAuthPlugins',
	expect: { }
});

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('luci'),
			callListAuthPlugins()
		]);
	},

	render: function(data) {
		var pluginsData = data[1] || { external_auth: '0', plugins: [] };
		var externalAuth = pluginsData.external_auth == '1';
		var plugins = pluginsData.plugins || [];

		var body = E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('Authentication Settings')),
			E('div', { 'class': 'cbi-map-descr' },
				_('Configure global authentication settings and manage individual authentication plugins.'))
		]);

		// Global settings section
		var globalSection = E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Global Settings')),
			E('div', { 'class': 'cbi-section-descr' },
				_('Enable or disable external authentication system-wide. When disabled, only password authentication is used.'))
		]);

		var globalTable = E('table', { 'class': 'table cbi-section-table' });
		var globalRow = E('tr', { 'class': 'tr cbi-section-table-row' });

		var globalCheckbox = E('input', {
			'type': 'checkbox',
			'id': 'external_auth',
			'checked': externalAuth ? '' : null
		});

		globalRow.appendChild(E('td', { 'class': 'td cbi-value-field', 'style': 'width: 30px;' }, globalCheckbox));
		globalRow.appendChild(E('td', { 'class': 'td' }, [
			E('label', { 'for': 'external_auth', 'style': 'font-weight: bold;' }, _('Enable External Authentication')),
			E('br'),
			E('span', { 'class': 'cbi-value-description' },
				_('When enabled, authentication plugins in /usr/share/luci/auth.d/ will be loaded and used for additional verification during login.'))
		]));

		globalTable.appendChild(globalRow);
		globalSection.appendChild(globalTable);
		body.appendChild(globalSection);

		// Plugin settings section
		var pluginSection = E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Authentication Plugins')),
			E('div', { 'class': 'cbi-section-descr' },
				_('Enable or disable individual authentication plugins. Disabled plugins will be skipped during login.'))
		]);

		if (plugins.length === 0) {
			pluginSection.appendChild(E('p', { 'class': 'cbi-section-note' },
				_('No authentication plugins found in /usr/share/luci/auth.d/')
			));
		} else {
			var pluginTable = E('table', { 'class': 'table cbi-section-table' }, [
				E('tr', { 'class': 'tr table-titles' }, [
					E('th', { 'class': 'th cbi-section-table-cell', 'style': 'width: 50px;' }, _('Enabled')),
					E('th', { 'class': 'th cbi-section-table-cell' }, _('Plugin Name')),
					E('th', { 'class': 'th cbi-section-table-cell' }, _('Filename'))
				])
			]);

			for (var i = 0; i < plugins.length; i++) {
				var plugin = plugins[i];
				var pluginRow = E('tr', { 'class': 'tr cbi-section-table-row' });

				var pluginCheckbox = E('input', {
					'type': 'checkbox',
					'id': 'plugin_' + plugin.name,
					'data-plugin': plugin.name,
					'checked': plugin.enabled ? '' : null
				});

				pluginRow.appendChild(E('td', { 'class': 'td cbi-value-field', 'style': 'text-align: center;' }, pluginCheckbox));
				pluginRow.appendChild(E('td', { 'class': 'td' }, plugin.name));
				pluginRow.appendChild(E('td', { 'class': 'td' }, plugin.filename));

				pluginTable.appendChild(pluginRow);
			}

			pluginSection.appendChild(pluginTable);
		}

		body.appendChild(pluginSection);

		return body;
	},

	handleSave: function() {
		var externalAuthCheckbox = document.getElementById('external_auth');
		var externalAuthValue = externalAuthCheckbox && externalAuthCheckbox.checked ? '1' : '0';

		// Save global external_auth setting
		uci.set('luci', 'main', 'external_auth', externalAuthValue);

		// Save individual plugin settings
		var pluginCheckboxes = document.querySelectorAll('input[data-plugin]');
		pluginCheckboxes.forEach(function(checkbox) {
			var pluginName = checkbox.getAttribute('data-plugin');
			var isDisabled = !checkbox.checked ? '1' : '0';
			
			// Ensure sauth section exists (type: internal)
			if (!uci.get('luci', 'sauth')) {
				uci.add('luci', 'internal', 'sauth');
			}
			
			uci.set('luci', 'sauth', pluginName + '_disabled', isDisabled);
		});

		return uci.save().then(function() {
			return uci.apply();
		}).then(function() {
			ui.addNotification(null, E('p', _('Authentication settings have been saved.')), 'info');
		}).catch(function(err) {
			ui.addNotification(null, E('p', _('Failed to save authentication settings: ') + err.message), 'danger');
		});
	},

	handleSaveApply: null,
	handleReset: null
});
