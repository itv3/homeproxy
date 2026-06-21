/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * HomeProxy 路由节点前端 helper。
 */

'use strict';
'require baseclass';
'require uci';

return baseclass.extend({
	routingNodeName(res) {
		let type = _('Routing node');
		if (res.node === 'urltest')
			type = _('URLTest');
		else if (res.node === 'selector')
			type = _('Selector');

		return String.format('[%s] %s', type, res.label || res['.name']);
	},

	buildRoutingNodeNames(uci_config) {
		let names = {};

		uci.sections(uci_config, 'routing_node', (res) => {
			names[res['.name']] = this.routingNodeName(res);
		});

		return names;
	},

	addSelectableOutbounds(option, uci_config, proxy_nodes, section_id, include_routing_nodes) {
		for (let i in proxy_nodes)
			option.value(i, proxy_nodes[i]);

		if (!include_routing_nodes)
			return;

		uci.sections(uci_config, 'routing_node', (res) => {
			if (res.enabled === '1' && res['.name'] !== section_id)
				option.value(res['.name'], this.routingNodeName(res));
		});
	},

	nodeDisplayName(node_id, proxy_nodes, routing_node_names) {
		return proxy_nodes[node_id] || routing_node_names[node_id] || node_id;
	},

	selectorHasPath(uci_config, start, target, path_cache, seen) {
		if (!start || !target)
			return false;
		if (start === target)
			return true;

		let key = start + '->' + target;
		if (path_cache[key] !== undefined)
			return path_cache[key];

		if (seen[start])
			return false;

		seen[start] = true;

		let found = false;
		uci.sections(uci_config, 'routing_node', (res) => {
			if (found || res['.name'] !== start)
				return;

			let nodes = res.node === 'urltest' ? res.urltest_nodes : res.selector_nodes;
			for (let i in (nodes || [])) {
				if (nodes[i] === target || this.selectorHasPath(uci_config, nodes[i], target, path_cache, seen)) {
					found = true;
					return;
				}
			}

			if (res.outbound === target || this.selectorHasPath(uci_config, res.outbound, target, path_cache, seen))
				found = true;
		});

		path_cache[key] = found;
		return found;
	}
});
