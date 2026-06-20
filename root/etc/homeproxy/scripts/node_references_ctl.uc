#!/usr/bin/ucode
'use strict';

import { cursor } from 'uci';
import { collect_node_references } from '/etc/homeproxy/scripts/node_references.uc';

const MAX_NODE_ID_LEN = 128;

function parseInput(raw) {
	try {
		return json(raw || '{}');
	} catch (e) {
		return {};
	}
}

function validNodeId(node_id) {
	return type(node_id) === 'string' &&
	       length(node_id) > 0 &&
	       length(node_id) <= MAX_NODE_ID_LEN &&
	       match(node_id, /^[A-Za-z0-9_]+$/);
}

let input = parseInput(ARGV[0]),
    action = input.action || '',
    uci = cursor();

uci.load('homeproxy');

switch (action) {
case 'get':
	if (!validNodeId(input.node_id)) {
		print(sprintf('%.J\n', { result: false, error: 'illegal node_id' }));
		exit(1);
	}

	print(sprintf('%.J\n', {
		result: true,
		node_id: input.node_id,
		references: collect_node_references(uci, 'homeproxy', input.node_id)
	}));
	break;
default:
	print(sprintf('%.J\n', { result: false, error: 'illegal action' }));
	exit(1);
}
