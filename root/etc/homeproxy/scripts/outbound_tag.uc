/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * HomeProxy outbound tag mapping helpers.
 */

'use strict';

function reserve_tag(used_tags, tag) {
	if (type(tag) === 'string' && tag !== '')
		used_tags[tag] = true;
}

function sanitize_outbound_tag(label) {
	if (type(label) !== 'string')
		return '';

	let tag = '';
	for (let i = 0; i < length(label); i++) {
		let ch = ord(label, i);
		if (ch >= 32 && ch !== 127)
			tag += substr(label, i, 1);
	}

	return tag;
}

function conflicts_outbound_tag(tag, used_tags) {
	return tag in used_tags ||
	       match(tag, /^cfg-.+-out$/) ||
	       match(tag, /^cfg-.+-out-shadowtls$/) ||
	       match(tag, /^cfg-.+-dns$/) ||
	       match(tag, /^cfg-.+-rule$/) ||
	       match(tag, /-out-shadowtls$/);
}

function make_suffixed_outbound_tag(base, section, used_tags) {
	let prefix_len = (length(section) < 6) ? length(section) : 6;

	for (let i = prefix_len; i <= length(section); i++) {
		let tag = base + ' #' + substr(section, 0, i);
		if (!conflicts_outbound_tag(tag, used_tags))
			return tag;
	}

	for (let n = 2; ; n++) {
		let tag = base + ' #' + section + '-' + n;
		if (!conflicts_outbound_tag(tag, used_tags))
			return tag;
	}
}

function sort_outbound_tag_items(items) {
	for (let i = 0; i < length(items); i++) {
		let min = i;

		for (let j = i + 1; j < length(items); j++)
			if (items[j].section < items[min].section)
				min = j;

		if (min !== i) {
			let item = items[i];
			items[i] = items[min];
			items[min] = item;
		}
	}
}

export function build_outbound_tag_map(uci) {
	const uciconfig = 'homeproxy';
	let items = [],
	    used_tags = {},
	    tag_map = {},
	    routing_mode = uci.get(uciconfig, 'config', 'routing_mode') || 'bypass_mainland_china';

	const reserved_tags = [
		'GLOBAL', 'any',
		'direct-out', 'block-out', 'main-out', 'main-udp-out',
		'default-dns', 'system-dns', 'main-dns', 'china-dns',
		'dns-in', 'mixed-in', 'redirect-in', 'tproxy-in', 'tun-in',
		'direct-domain', 'proxy-domain', 'geoip-cn', 'geosite-cn', 'geosite-noncn',
		// 旧隐藏测速组的保留占位，避免用户标签或旧配置与保留名冲突；不是运行时测速组。
		'__homeproxy_delay_test__'
	];

	for (let tag in reserved_tags)
		reserve_tag(used_tags, tag);

	uci.foreach(uciconfig, 'dns_server', (cfg) => {
		reserve_tag(used_tags, 'cfg-' + cfg['.name'] + '-dns');
	});

	uci.foreach(uciconfig, 'ruleset', (cfg) => {
		reserve_tag(used_tags, 'cfg-' + cfg['.name'] + '-rule');
	});

	uci.foreach(uciconfig, 'node', (cfg) => {
		push(items, {
			section: cfg['.name'],
			label: cfg.label
		});
	});

	if (routing_mode === 'custom')
		uci.foreach(uciconfig, 'routing_node', (cfg) => {
			if (cfg.enabled === '1' && cfg.node in ['selector', 'urltest'])
				push(items, {
					section: cfg['.name'],
					label: cfg.label
				});
		});

	sort_outbound_tag_items(items);

	for (let item in items) {
		let section = item.section,
		    base = sanitize_outbound_tag(item.label),
		    final_tag;

		if (base === '') {
			final_tag = 'cfg-' + section + '-out';
			reserve_tag(used_tags, final_tag);
			tag_map[section] = final_tag;
			continue;
		}

		final_tag = conflicts_outbound_tag(base, used_tags)
			? make_suffixed_outbound_tag(base, section, used_tags)
			: base;

		reserve_tag(used_tags, final_tag);
		tag_map[section] = final_tag;
	}

	return tag_map;
};
