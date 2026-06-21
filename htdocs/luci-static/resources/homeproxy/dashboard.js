/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * HomeProxy 面板入口 helper。
 */

'use strict';
'require baseclass';

const DEFAULT_DASHBOARD_URL = 'https://metacubexd.pages.dev/#/overview';
const DEFAULT_CONTROLLER = '127.0.0.1:9090';
const DEFAULT_PROXY_LISTEN = '127.0.0.1:9091';

return baseclass.extend({
	parseController(value) {
		let result = {
			hostname: '',
			port: '',
			https: false
		};

		if (!value)
			return result;

		try {
			let url = new URL(value.match(/^https?:\/\//) ? value : 'http://' + value);
			result.hostname = url.hostname;
			result.port = url.port;
			result.https = url.protocol === 'https:';
		} catch(e) { }

		return result;
	},

	deriveProxyController(value) {
		let controller = this.parseController(value || DEFAULT_CONTROLLER);

		if (!controller.hostname)
			return DEFAULT_PROXY_LISTEN;

		let hostname = controller.hostname.replace(/^\[(.*)\]$/, '$1');

		return String.format('%s:9091', hostname.includes(':') ? '[' + hostname + ']' : hostname);
	},

	configuredUrl(uci, config) {
		return uci.get(config, 'config', 'metacubexd_url') || DEFAULT_DASHBOARD_URL;
	},

	baseUrl(uci, config) {
		let dashboard = this.configuredUrl(uci, config),
		    hash = dashboard.indexOf('#');

		if (hash >= 0)
			dashboard = dashboard.slice(0, hash);

		return dashboard.replace(/\/+$/, '');
	},

	setupUrl(uci, config) {
		let enabled = uci.get(config, 'config', 'clash_api_enabled') === '1',
		    target = uci.get(config, 'config', 'clash_api_external_controller') || DEFAULT_CONTROLLER,
		    proxy = uci.get(config, 'config', 'clash_api_proxy_external_controller') || this.deriveProxyController(target),
		    controller = this.parseController(proxy),
		    secret = uci.get(config, 'config', 'clash_api_secret') || '';

		if (!enabled || !controller.hostname)
			return null;

		let dashboard = this.configuredUrl(uci, config),
		    base = this.baseUrl(uci, config);

		if (dashboard.includes('yacd.metacubex.one'))
			return dashboard;

		let params = new URLSearchParams();
		params.set('hostname', controller.hostname);
		if (controller.port)
			params.set('port', controller.port);
		params.set(controller.https ? 'https' : 'http', '1');
		if (secret)
			params.set('secret', secret);

		return base + '/#/setup?' + params.toString();
	},

	renderButton(uci, config) {
		let url = this.setupUrl(uci, config);

		if (!url)
			return null;

		return E('span', { 'class': 'homeproxy-dashboard-action' }, [
			E('a', {
				'class': 'btn cbi-button cbi-button-action',
				'href': url,
				'target': '_blank',
				'rel': 'noreferrer noopener'
			}, [ _('MetaCubeXD 面板') ]),
			E('span', {
				'style': 'display:block;margin-top:.35em;color:var(--text-color-medium,#666);font-size:90%;'
			}, _('使用远程 MetaCubeXD 面板时，Clash API secret 会提供给该网页。安全要求较高时请使用自建面板或本地面板。'))
		]);
	}
});
