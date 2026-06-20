#!/usr/bin/ucode
'use strict';

import { cursor } from 'uci';
import { remove_subscription_nodes } from '/etc/homeproxy/scripts/node_references.uc';

const MAX_NODE_IDS = 1000;
const MAX_NODE_ID_LEN = 128;

function parseInput(raw) {
	try {
		return json(raw || '{}');
	} catch (e) {
		return {};
	}
}

function replyError(error) {
	print(sprintf('%.J\n', { result: false, error: error }));
	exit(1);
}

function validNodeId(node_id) {
	return type(node_id) === 'string' &&
	       length(node_id) > 0 &&
	       length(node_id) <= MAX_NODE_ID_LEN &&
	       match(node_id, /^[A-Za-z0-9_]+$/);
}

let input = parseInput(ARGV[0]),
    uci = cursor();

if (type(input.node_ids) !== 'array')
	replyError('illegal node_ids');

if (length(input.node_ids) > MAX_NODE_IDS)
	replyError('too many node_ids');

for (let node_id in input.node_ids)
	if (!validNodeId(node_id))
		replyError('illegal node id');

uci.load('homeproxy');

let result = remove_subscription_nodes(uci, 'homeproxy', input.node_ids);
uci.commit('homeproxy');

print(sprintf('%.J\n', {
	result: true,
	removed: result.removed,
	changed: result.changed,
	changes: result.changes,
	main_node_fallback: result.main_node_fallback,
	main_udp_fallback: result.main_udp_fallback
}));
