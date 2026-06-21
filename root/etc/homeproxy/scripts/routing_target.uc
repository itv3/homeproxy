/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * HomeProxy 路由目标解析 helper。
 */

'use strict';

import {
	get_outbound_tag,
	normalize_outbound_target as normalizeOutboundTargetValue
} from 'outbound_tag';

function isEmpty(value) {
	return !value || value === 'nil' || (type(value) in ['array', 'object'] && length(value) === 0);
}

function report(ctx, level, message, suggestion) {
	if (type(ctx.reportError) === 'function')
		ctx.reportError(level, message, suggestion);
}

function sectionType(ctx, name) {
	return ctx.uci.get_all(ctx.config, name)?.['.type'];
}

function outboundTag(ctx, section) {
	return get_outbound_tag(ctx?.tag_map, section);
}

export function is_builtin_outbound(_ctx, target) {
	return target in ['block-out', 'direct-out'];
};

export function is_node_section(ctx, target) {
	return sectionType(ctx, target) === (ctx.node_type || 'node');
};

export function is_routing_node_section(ctx, target) {
	const node = ctx.uci.get(ctx.config, target, 'node');

	return !isEmpty(node);
};

export function normalize_outbound_target(target, tag_map) {
	return normalizeOutboundTargetValue(target, tag_map);
};

export function resolve_outbound_target(ctx, target, owner, seen_path) {
	target = normalize_outbound_target(target, ctx?.tag_map);

	if (isEmpty(target))
		return null;
	else if (is_builtin_outbound(ctx, target))
		return {
			type: 'builtin',
			outbound: target,
			target: target
		};
	else if (is_node_section(ctx, target))
		return {
			type: 'node',
			outbound: outboundTag(ctx, target),
			target: target,
			node_id: target
		};

	if (!seen_path)
		seen_path = [];

	if (~index(seen_path, target)) {
		report(ctx, 'error',
			sprintf('路由节点配置错误：检测到循环引用\n循环路径: %s',
				join(' -> ', [ ...seen_path, target ])),
			'进入 LuCI 界面 -> 服务 -> HomeProxy -> 路由节点，检查以下节点的"出站"配置，移除循环引用');
		return { fatal: true };
	}

	const max_depth = ctx.max_depth || 20;
	if (length(seen_path) >= max_depth) {
		report(ctx, 'error',
			sprintf('路由节点配置错误：嵌套层级过深\n当前路径: %s\n最大允许层级: %d',
				join(' -> ', [ ...seen_path, target ]),
				max_depth),
			'简化路由节点的嵌套结构，避免过多的 Selector 嵌套');
		return { fatal: true };
	}

	const routing_node = ctx.uci.get(ctx.config, target, 'node');
	if (isEmpty(routing_node)) {
		if (owner)
			report(ctx, 'warning',
				sprintf('%s 引用了已删除或无效的节点：%s，已在本次生成中跳过。', owner, join(' -> ', [ ...seen_path, target ])),
				'请进入 LuCI 界面检查对应的节点或路由节点引用');

		return null;
	} else if (routing_node === 'urltest' || routing_node === 'selector') {
		return {
			type: routing_node,
			outbound: outboundTag(ctx, target),
			target: target,
			section_id: target
		};
	}

	return resolve_outbound_target(ctx, routing_node, owner, [ ...seen_path, target ]);
};

export function get_routing_target_outbound(ctx, target, owner) {
	const resolved = resolve_outbound_target(ctx, target, owner, []);

	if (!resolved || resolved.fatal)
		return null;

	return resolved.outbound;
};

export function get_valid_selector_outbounds(ctx, selector_nodes, owner) {
	let outbounds = [];

	for (let node_id in selector_nodes) {
		const outbound = get_routing_target_outbound(
			ctx,
			node_id,
			sprintf('路由节点 %s 的 Selector 节点', owner)
		);

		if (!isEmpty(outbound))
			push(outbounds, outbound);
	}

	return outbounds;
};

export function collect_routing_target_dependencies(ctx, client_config, target, routing_nodes, push_node_outbound, outbound_tag) {
	const resolved = resolve_outbound_target(ctx, target, null, []);

	if (!resolved || resolved.fatal || resolved.type !== 'node' || ~index(routing_nodes, resolved.node_id))
		return false;

	const node = ctx.uci.get_all(ctx.config, resolved.node_id) || {};
	push_node_outbound(client_config, node, outbound_tag(resolved.node_id));
	push(routing_nodes, resolved.node_id);

	return true;
};

export function get_outbound(ctx, cfg, fallback, owner) {
	if (isEmpty(cfg))
		return null;

	if (type(cfg) === 'array') {
		if ('any-out' in cfg)
			return 'any';

		let outbounds = [];
		for (let i in cfg)
			push(outbounds, get_outbound(ctx, i, fallback, owner));
		return outbounds;
	}

	switch (cfg) {
	case 'block-out':
	case 'direct-out':
		return cfg;
	default:
		const resolved = resolve_outbound_target(ctx, cfg, owner, []);

		if (!resolved || resolved.fatal) {
			report(ctx, 'warning',
				sprintf('%s引用了已删除或无效的节点：%s，已在本次生成中回退为 %s。', owner ? owner + ' ' : '出站', cfg, fallback || '空值'),
				'请进入 LuCI 界面检查路由、DNS、规则集中的出站引用');
			return fallback || null;
		}

		return resolved.outbound;
	}
};
