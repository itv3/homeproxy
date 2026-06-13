#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2025 ImmortalWrt.org
 */

'use strict';

import { cursor } from 'uci';
import { executeCommand, isEmpty, parseURL } from 'homeproxy';

const uci = cursor();

const uciconfig = 'homeproxy';
uci.load(uciconfig);

const uciinfra = 'infra',
      ucimigration = 'migration',
      ucimain = 'config',
      ucinode = 'node',
      ucidns = 'dns',
      ucidnsserver = 'dns_server',
      ucidnsrule = 'dns_rule',
      ucirouting = 'routing',
      uciroutingnode = 'routing_node',
      uciroutingrule = 'routing_rule',
      uciserver = 'server';

function firstValue(value) {
	return (type(value) === 'array') ? value[0] : value;
}

function stripCidr(value) {
	return replace(trim(firstValue(value) || ''), /\/.*$/, '');
}

function isIPv4Address(value) {
	return !!match(value || '', /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/);
}

function isPortableBindHost(value) {
	value = lc(trim(value || ''));

	return value === 'localhost' ||
		value === '0.0.0.0' ||
		value === '::' ||
		value === '[::]' ||
		value === '::1' ||
		value === '[::1]' ||
		!!match(value, /^127\./);
}

function appendIPv4Address(addresses, value) {
	value = stripCidr(value);

	if (isIPv4Address(value) && index(addresses, value) === -1)
		push(addresses, value);
}

function localIPv4Addresses() {
	const netuci = cursor();
	let addresses = [];

	netuci.load('network');

	let lan_ipaddr = netuci.get('network', 'lan', 'ipaddr');
	if (type(lan_ipaddr) === 'array') {
		for (let addr in lan_ipaddr)
			appendIPv4Address(addresses, addr);
	} else {
		appendIPv4Address(addresses, lan_ipaddr);
	}

	const ip_addresses = executeCommand('/sbin/ip -4 -o addr show scope global')?.stdout || '';
	for (let line in split(ip_addresses, /\n/)) {
		let matched = match(line, /[ \t]inet[ \t]+([0-9.]+)(\/[0-9]+)?[ \t]/);
		if (matched)
			appendIPv4Address(addresses, matched[1]);
	}

	return addresses;
}

function parseController(value, default_port) {
	value = trim(replace(firstValue(value) || '', /^https?:\/\//, ''));
	value = replace(value, /\/.*$/, '');

	let matched = match(value, /^\[([^\]]+)\](:([0-9]+))?$/);
	if (matched)
		return { host: matched[1], port: int(matched[3] || default_port) };

	matched = match(value, /^([^:]+):([0-9]+)$/);
	if (matched)
		return { host: matched[1], port: int(matched[2]) };

	return { host: value, port: int(default_port) };
}

function formatController(host, port) {
	return sprintf((index(host, ':') >= 0) ? '[%s]:%d' : '%s:%d', host, port);
}

function normalizeLocalControllerOption(local_addresses, fallback_host, option, default_port, set_when_empty) {
	let value = uci.get(uciconfig, ucimain, option);

	if (isEmpty(value)) {
		if (set_when_empty)
			uci.set(uciconfig, ucimain, option, formatController(fallback_host, default_port));

		return;
	}

	let controller = parseController(value, default_port),
	    host = controller.host;

	if (isEmpty(host))
		host = fallback_host;
	else if (isPortableBindHost(host))
		return;
	else if (!isIPv4Address(host) || index(local_addresses, host) !== -1)
		return;

	uci.set(uciconfig, ucimain, option, formatController(fallback_host, controller.port || default_port));
}

function normalizeLocalControllerOptions() {
	let local_addresses = localIPv4Addresses(),
	    fallback_host = local_addresses[0];

	if (isEmpty(fallback_host))
		return;

	for (let item in [
		[ 'clash_api_external_controller', 9090, true ],
		[ 'clash_api_proxy_external_controller', 9091, false ]
	])
		normalizeLocalControllerOption(local_addresses, fallback_host, item[0], item[1], item[2]);
}

/* chinadns-ng has been removed */
if (uci.get(uciconfig, uciinfra, 'china_dns_port'))
	uci.delete(uciconfig, uciinfra, 'china_dns_port');

/* chinadns server now only accepts single server */
const china_dns_server = uci.get(uciconfig, ucimain, 'china_dns_server');
if (type(china_dns_server) === 'array') {
	uci.set(uciconfig, ucimain, 'china_dns_server', china_dns_server[0]);
} else {
	if (china_dns_server === 'wan_114')
		uci.set(uciconfig, ucimain, 'china_dns_server', '114.114.114.114');
	else if (match(china_dns_server, /,/))
		uci.set(uciconfig, ucimain, 'china_dns_server', split(china_dns_server, ',')[0]);
}

/* github_token option has been moved to config section */
const github_token = uci.get(uciconfig, uciinfra, 'github_token');
if (github_token) {
	uci.set(uciconfig, ucimain, 'github_token', github_token);
	uci.delete(uciconfig, uciinfra, 'github_token')
}

/* ntp_server was introduced */
if (!uci.get(uciconfig, uciinfra, 'ntp_server'))
	uci.set(uciconfig, uciinfra, 'ntp_server', 'nil');

/* tun_gso was deprecated in sb 1.11 */
if (!isEmpty(uci.get(uciconfig, uciinfra, 'tun_gso')))
	uci.delete(uciconfig, uciinfra, 'tun_gso');

/* create migration section */
if (!uci.get(uciconfig, ucimigration))
	uci.set(uciconfig, ucimigration, uciconfig);

/* delete old crontab command */
const migration_crontab = uci.get(uciconfig, ucimigration, 'crontab');
if (!migration_crontab) {
	system('sed -i "/update_crond.sh/d" "/etc/crontabs/root" 2>"/dev/null"');
	uci.set(uciconfig, ucimigration, 'crontab', '1');
}

/* log_level was introduced */
if (isEmpty(uci.get(uciconfig, ucimain, 'log_level')))
	uci.set(uciconfig, ucimain, 'log_level', 'warn');

if (isEmpty(uci.get(uciconfig, uciserver, 'log_level')))
	uci.set(uciconfig, uciserver, 'log_level', 'warn');

/* Clash API dashboard integration */
if (isEmpty(uci.get(uciconfig, ucimain, 'clash_api_enabled')))
	uci.set(uciconfig, ucimain, 'clash_api_enabled', '1');

if (isEmpty(uci.get(uciconfig, ucimain, 'clash_api_external_controller')))
	uci.set(uciconfig, ucimain, 'clash_api_external_controller', '192.168.9.1:9090');

normalizeLocalControllerOptions();

if (isEmpty(uci.get(uciconfig, ucimain, 'clash_api_default_mode')))
	uci.set(uciconfig, ucimain, 'clash_api_default_mode', 'Rule');

if (isEmpty(uci.get(uciconfig, ucimain, 'clash_api_allow_origin'))) {
	uci.add_list(uciconfig, ucimain, 'clash_api_allow_origin', 'https://metacubex.github.io');
	uci.add_list(uciconfig, ucimain, 'clash_api_allow_origin', 'https://metacubexd.pages.dev');
	uci.add_list(uciconfig, ucimain, 'clash_api_allow_origin', 'http://d.metacubex.one');
	uci.add_list(uciconfig, ucimain, 'clash_api_allow_origin', 'https://yacd.metacubex.one');
}

if (isEmpty(uci.get(uciconfig, ucimain, 'clash_api_allow_private_network')))
	uci.set(uciconfig, ucimain, 'clash_api_allow_private_network', '1');

if (isEmpty(uci.get(uciconfig, ucimain, 'metacubexd_url')))
	uci.set(uciconfig, ucimain, 'metacubexd_url', 'https://metacubexd.pages.dev/#/overview');

/* empty value defaults to all ports now */
if (uci.get(uciconfig, ucimain, 'routing_port') === 'all')
	uci.delete(uciconfig, ucimain, 'routing_port');

/* experimental section was removed */
if (uci.get(uciconfig, 'experimental'))
	uci.delete(uciconfig, 'experimental');

/* block-dns was removed from built-in dns servers */
const default_dns_server = uci.get(uciconfig, ucidns, 'default_server');
if (default_dns_server === 'block-dns') {
	/* append a rule at last to block all DNS queries */
	uci.set(uciconfig, '_migration_dns_final_block', ucidnsrule);
	uci.set(uciconfig, '_migration_dns_final_block', 'label', 'migration_final_block_dns');
	uci.set(uciconfig, '_migration_dns_final_block', 'enabled', '1');
	uci.set(uciconfig, '_migration_dns_final_block', 'mode', 'default');
	uci.set(uciconfig, '_migration_dns_final_block', 'action', 'reject');
	uci.set(uciconfig, ucidns, 'default_server', 'default-dns');
}

const dns_server_migration = {};
/* DNS servers options */
uci.foreach(uciconfig, ucidnsserver, (cfg) => {
	/* legacy format was deprecated in sb 1.12 */
	if (cfg.address) {
		const addr = parseURL((!match(cfg.address, /:\/\//) ? 'udp://' : '') + (validation('ip6addr', cfg.address) ? `[${cfg.address}]` : cfg.address));
		/* RCode was moved into DNS rules */
		if (addr.protocol === 'rcode') {
			dns_server_migration[cfg['.name']] = { action: 'predefined' };
			switch (addr.hostname) {
			case 'success':
				dns_server_migration[cfg['.name']].rcode = 'NOERROR';
				break;
			case 'format_error':
				dns_server_migration[cfg['.name']].rcode = 'FORMERR';
				break;
			case 'server_failure':
				dns_server_migration[cfg['.name']].rcode = 'SERVFAIL';
				break;
			case 'name_error':
				dns_server_migration[cfg['.name']].rcode = 'NXDOMAIN';
				break;
			case 'not_implemented':
				dns_server_migration[cfg['.name']].rcode = 'NOTIMP';
				break;
			case 'refused':
			default:
				dns_server_migration[cfg['.name']].rcode = 'REFUSED';
				break;
			}

			uci.delete(uciconfig, cfg['.name']);
			return;
		}
		uci.set(uciconfig, cfg['.name'], 'type', addr.protocol);
		uci.set(uciconfig, cfg['.name'], 'server', addr.hostname);
		uci.set(uciconfig, cfg['.name'], 'server_port', addr.port);
		uci.set(uciconfig, cfg['.name'], 'path', (addr.pathname !== '/') ? addr.pathname : null);
		uci.delete(uciconfig, cfg['.name'], 'address');
	}

	if (cfg.strategy) {
		if (cfg['.name'] === default_dns_server)
			uci.set(uciconfig, ucidns, 'default_strategy', cfg.strategy);
		dns_server_migration[cfg['.name']] = { strategy: cfg.strategy };
		uci.delete(uciconfig, cfg['.name'], 'strategy');
	}

	if (cfg.client_subnet) {
		if (cfg['.name'] === default_dns_server)
			uci.set(uciconfig, ucidns, 'client_subnet', cfg.client_subnet);

		if (isEmpty(dns_server_migration[cfg['.name']]))
			dns_server_migration[cfg['.name']] = {};
		dns_server_migration[cfg['.name']].client_subnet = cfg.client_subnet;
		uci.delete(uciconfig, cfg['.name'], 'client_subnet');
	}
});

/* DNS rules options */
uci.foreach(uciconfig, ucidnsrule, (cfg) => {
	/* outbound was removed in sb 1.12 */
	if (cfg.outbound) {
		uci.delete(uciconfig, cfg['.name']);
		if (!cfg.enabled)
			return;

		map(cfg.outbound, (outbound) => {
			switch (outbound) {
			case 'direct-out':
			case 'block-out':
				break;
			case 'any-out':
				uci.set(uciconfig, ucirouting, 'default_outbound_dns', cfg.server);
				break;
			default:
				uci.set(uciconfig, cfg.outbound, 'domain_resolver', cfg.server);
				break;
			}
		});

		return;
	}

	/* rule_set_ipcidr_match_source was renamed in sb 1.10 */
	if (cfg.rule_set_ipcidr_match_source === '1')
		uci.rename(uciconfig, cfg['.name'], 'rule_set_ipcidr_match_source', 'rule_set_ip_cidr_match_source');

	/* block-dns was moved into action in sb 1.11 */
	if (cfg.server === 'block-dns') {
		uci.set(uciconfig, cfg['.name'], 'action', 'reject');
		uci.delete(uciconfig, cfg['.name'], 'server');
	} else if (!cfg.action) {
		/* add missing 'action' field */
		uci.set(uciconfig, cfg['.name'], 'action', 'route');
	}

	/* strategy and client_subnet were moved into dns rules */
	if (dns_server_migration[cfg.server]) {
		if (dns_server_migration[cfg.server].strategy)
			uci.set(uciconfig, cfg['.name'], 'strategy', dns_server_migration[cfg.server].strategy);

		if (dns_server_migration[cfg.server].client_subnet)
			uci.set(uciconfig, cfg['.name'], 'client_subnet', dns_server_migration[cfg.server].client_subnet);

		if (dns_server_migration[cfg.server].rcode) {
			uci.set(uciconfig, cfg['.name'], 'action', 'predefined');
			uci.set(uciconfig, cfg['.name'], 'rcode', dns_server_migration[cfg.server].rcode);
			uci.delete(uciconfig, cfg['.name'], 'server');
		}
	}
});

/* nodes options */
uci.foreach(uciconfig, ucinode, (cfg) => {
	/* tls_ech_tls_disable_drs is useless and deprecated in sb 1.12 */
	if (!isEmpty(cfg.tls_ech_tls_disable_drs))
		uci.delete(uciconfig, cfg['.name'], 'tls_ech_tls_disable_drs');

	/* tls_ech_enable_pqss is useless and deprecated in sb 1.12 */
	if (!isEmpty(cfg.tls_ech_enable_pqss))
		uci.delete(uciconfig, cfg['.name'], 'tls_ech_enable_pqss');

	/* wireguard_gso was deprecated in sb 1.11 */
	if (!isEmpty(cfg.wireguard_gso))
		uci.delete(uciconfig, cfg['.name'], 'wireguard_gso');
});

/* routing rules options */
uci.foreach(uciconfig, uciroutingrule, (cfg) => {
	/* rule_set_ipcidr_match_source was renamed in sb 1.10 */
	if (cfg.rule_set_ipcidr_match_source === '1')
		uci.rename(uciconfig, cfg['.name'], 'rule_set_ipcidr_match_source', 'rule_set_ip_cidr_match_source');

	/* block-out was moved into action in sb 1.11 */
	if (cfg.outbound === 'block-out') {
		uci.set(uciconfig, cfg['.name'], 'action', 'reject');
		uci.delete(uciconfig, cfg['.name'], 'outbound');
	} else if (!cfg.action) {
		/* add missing 'action' field */
		uci.set(uciconfig, cfg['.name'], 'action', 'route');
	}
});

/* server options */
/* auto_firewall was moved into server options */
const auto_firewall = uci.get(uciconfig, uciserver, 'auto_firewall');
if (!isEmpty(auto_firewall))
	uci.delete(uciconfig, uciserver, 'auto_firewall');

uci.foreach(uciconfig, uciserver, (cfg) => {
	/* auto_firewall was moved into server options */
	if (auto_firewall === '1')
		uci.set(uciconfig, cfg['.name'], 'firewall' , '1');

	/* sniff_override was deprecated in sb 1.11 */
	if (!isEmpty(cfg.sniff_override))
		uci.delete(uciconfig, cfg['.name'], 'sniff_override');

	/* domain_strategy is now pointless without sniff override */
	if (!isEmpty(cfg.domain_strategy))
		uci.delete(uciconfig, cfg['.name'], 'domain_strategy');
});

if (!isEmpty(uci.changes(uciconfig)))
	uci.commit(uciconfig);
