#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Clash API display proxy for HomeProxy dashboards.
 */

'use strict';

import * as socket from 'socket';
import * as uloop from 'uloop';
import { cursor } from 'uci';
import { urldecode, urlencode } from 'luci.http';

const uci = cursor();
const uciconfig = 'homeproxy';
const ucimain = 'config';
const shadowtls_suffix = '-out-shadowtls';
const filter_timeout = 10000;
const fallback_delay_limit = 5;

let next_id = 1;
let connections = {};
let target, listen, server;

uci.load(uciconfig);

function isEmpty(value) {
	return !value || value === 'nil' || (type(value) in ['array', 'object'] && length(value) === 0);
}

function parseController(value, default_port) {
	value = trim(replace(value || '', /^https?:\/\//, ''));
	value = replace(value, /\/.*$/, '');

	let matched = match(value, /^\[([^\]]+)\](:([0-9]+))?$/);
	if (matched)
		return { host: matched[1], port: int(matched[3] || default_port) };

	matched = match(value, /^([^:]+):([0-9]+)$/);
	if (matched)
		return { host: matched[1], port: int(matched[2]) };

	return { host: value, port: int(default_port) };
}

function deriveProxyController(target) {
	target = parseController(target || '192.168.9.1:9090', 9090);

	if (isEmpty(target.host))
		target.host = '192.168.9.1';

	return { host: target.host, port: 9091 };
}

function sendAll(sock, data) {
	let offset = 0;

	while (offset < length(data)) {
		let sent = sock.send(substr(data, offset));

		if (sent === null || sent <= 0)
			return false;

		offset += sent;
	}

	return true;
}

function recvAvailable(sock) {
	let data = '';
	let eof = false;

	for (let i = 0; i < 32; i++) {
		let chunk = sock.recv(16384);

		if (chunk === null)
			break;

		if (length(chunk) === 0) {
			eof = true;
			break;
		}

		data += chunk;

		if (length(chunk) < 16384)
			break;
	}

	return { data, eof };
}

function contentLength(headers) {
	for (let line in headers) {
		let matched = match(lc(line), /^content-length:[ \t]*([0-9]+)/);

		if (matched)
			return int(matched[1]);
	}

	return null;
}

function headerValue(headers, name) {
	name = lc(name);

	for (let line in headers) {
		let matched = match(line, /^([^:]+):(.*)$/);

		if (matched && lc(trim(matched[1])) === name)
			return trim(matched[2]);
	}

	return null;
}

function pathSegment(value) {
	return replace(urlencode(value), /\+/g, '%20');
}

function parseHttpMessage(raw, body_to_eof) {
	let header_end = index(raw, "\r\n\r\n");

	if (header_end < 0)
		return null;

	let header_text = substr(raw, 0, header_end);
	let headers = split(header_text, "\r\n");
	let body_start = header_end + 4;
	let body_len = contentLength(headers);

	if (body_len === null)
		body_len = body_to_eof ? length(raw) - body_start : 0;

	let complete_len = body_start + body_len;

	if (length(raw) < complete_len)
		return null;

	let request_line = split(headers[0] || '', /[ \t]+/);

	return {
		raw: substr(raw, 0, complete_len),
		headers,
		body: substr(raw, body_start, body_len),
		complete_len,
		method: request_line[0] || '',
		path: request_line[1] || '/'
	};
}

function shouldFilter(method, path) {
	return method === 'GET' && (
		path === '/proxies' ||
		index(path, '/proxies?') === 0 ||
		index(path, '/proxies/') === 0 ||
		path === '/providers/proxies' ||
		index(path, '/providers/proxies?') === 0 ||
		index(path, '/providers/proxies/') === 0
	);
}

function isUpgradeRequest(request) {
	return !!headerValue(request.headers, 'Upgrade') ||
		index(lc(headerValue(request.headers, 'Connection') || ''), 'upgrade') >= 0;
}

function rebuildCloseRequest(request) {
	let headers = [];

	for (let i = 0; i < length(request.headers); i++) {
		let line = request.headers[i],
		    header = lc(line);

		if (i > 0 && match(header, /^(accept-encoding|connection):/))
			continue;

		push(headers, line);
	}

	push(headers, 'Accept-Encoding: identity');
	push(headers, 'Connection: close');

	return join("\r\n", headers) + "\r\n\r\n" + request.body;
}

function isShadowTlsTag(name) {
	return type(name) === 'string' &&
		length(name) > length(shadowtls_suffix) &&
		substr(name, length(name) - length(shadowtls_suffix)) === shadowtls_suffix;
}

function filterProxyItem(item) {
	if (type(item) !== 'object')
		return;

	if (type(item.all) === 'array')
		item.all = filter(item.all, (name) => !isShadowTlsTag(name));
}

function filterProxyArray(items) {
	return filter(items, (item) => {
		if (type(item) === 'string')
			return !isShadowTlsTag(item);

		if (type(item) === 'object' && isShadowTlsTag(item.name))
			return false;

		filterProxyItem(item);
		return true;
	});
}

function filterProxiesPayload(payload) {
	if (type(payload) !== 'object')
		return payload;

	filterProxyItem(payload);

	if (type(payload.proxies) === 'object') {
		for (let name in keys(payload.proxies)) {
			if (isShadowTlsTag(name)) {
				delete payload.proxies[name];
				continue;
			}

				filterProxyItem(payload.proxies[name]);
			}
		}

	if (type(payload.providers) === 'object') {
		for (let name in keys(payload.providers)) {
			let provider = payload.providers[name];

			if (type(provider) !== 'object')
				continue;

			if (type(provider.proxies) === 'array')
				provider.proxies = filterProxyArray(provider.proxies);
		}
	}

	return payload;
}

function parseHex(value) {
	let result = 0;
	value = lc(trim(split(value, ';', 2)[0] || ''));

	for (let i = 0; i < length(value); i++) {
		let digit = index('0123456789abcdef', substr(value, i, 1));

		if (digit < 0)
			return null;

		result = result * 16 + digit;
	}

	return result;
}

function decodeChunkedBody(body) {
	let offset = 0;
	let decoded = '';

	while (offset < length(body)) {
		let line_end = index(substr(body, offset), "\r\n");

		if (line_end < 0)
			return null;

		let size = parseHex(substr(body, offset, line_end));
		if (size === null)
			return null;

		offset += line_end + 2;

		if (size === 0)
			return decoded;

		if (length(body) < offset + size + 2)
			return null;

		decoded += substr(body, offset, size);
		offset += size + 2;
	}

	return null;
}

function rebuildResponse(response, body) {
	let headers = [];

	for (let i = 0; i < length(response.headers); i++) {
		let line = response.headers[i];

		if (i > 0 && match(lc(line), /^(content-length|transfer-encoding):/))
			continue;

		push(headers, line);
	}

	push(headers, 'Content-Length: ' + length(body));

	return join("\r\n", headers) + "\r\n\r\n" + body;
}

function filterResponse(raw) {
	let response = parseHttpMessage(raw, true);

	if (response === null)
		return raw;

	let body = response.body;
	if (lc(headerValue(response.headers, 'transfer-encoding') || '') === 'chunked') {
		body = decodeChunkedBody(substr(raw, response.complete_len - length(response.body)));
		if (body === null)
			return raw;
	}

	let payload;

	try {
		payload = json(body);
	} catch (e) {
		return raw;
	}

	if (type(payload) !== 'object')
		return raw;

	payload = filterProxiesPayload(payload);

	return rebuildResponse(response, sprintf('%J', payload));
}

function responseBody(response) {
	if (response === null)
		return null;

	let body = response.body;

	if (lc(headerValue(response.headers, 'transfer-encoding') || '') === 'chunked') {
		body = decodeChunkedBody(response.body);
		if (body === null)
			return null;
	}

	return body;
}

function parseJsonBody(raw) {
	if (raw === null)
		return null;

	let response = parseHttpMessage(raw, true),
	    body = responseBody(response);

	if (body === null)
		return null;

	try {
		return json(body);
	} catch (e) {
		return null;
	}
}

function responseStatus(raw) {
	let response = parseHttpMessage(raw, true);

	if (response === null)
		return 0;

	let matched = match(response.headers[0] || '', /^HTTP\/[0-9.]+[ \t]+([0-9]+)/);

	return matched ? int(matched[1]) : 0;
}

function responseComplete(raw) {
	let header_end = index(raw, "\r\n\r\n");
	if (header_end < 0)
		return false;

	let headers = split(substr(raw, 0, header_end), "\r\n");
	if (lc(headerValue(headers, 'transfer-encoding') || '') === 'chunked')
		return decodeChunkedBody(substr(raw, header_end + 4)) !== null;

	if (contentLength(headers) === null)
		return false;

	return parseHttpMessage(raw) !== null;
}

function closeConnection(conn) {
	if (!conn)
		return;

	if (conn.client_handle) {
		conn.client_handle.delete();
		conn.client_handle = null;
	}

	if (conn.upstream_handle) {
		conn.upstream_handle.delete();
		conn.upstream_handle = null;
	}

	if (conn.timer) {
		conn.timer.cancel();
		conn.timer = null;
	}

	if (conn.client) {
		conn.client.close();
		conn.client = null;
	}

	if (conn.upstream) {
		conn.upstream.close();
		conn.upstream = null;
	}

	delete connections[conn.id];
}

function isEmptyObject(value) {
	return type(value) === 'object' && length(value) === 0;
}

function buildJsonResponse(request, payload) {
	let body = sprintf('%J', payload),
	    headers = [
		'HTTP/1.1 200 OK',
		'Content-Type: application/json',
		'Connection: close'
	    ],
	    origin = headerValue(request.headers, 'Origin');

	if (!isEmpty(origin)) {
		push(headers, 'Access-Control-Allow-Origin: ' + origin);
		push(headers, 'Vary: Origin');
	}

	push(headers, 'Content-Length: ' + length(body));

	return join("\r\n", headers) + "\r\n\r\n" + body;
}

function parseGroupDelayPath(path) {
	let parts = split(path, '?', 2),
	    matched = match(parts[0] || '', /^\/group\/(.+)\/delay$/);

	if (!matched)
		return null;

	return {
		name: urldecode(matched[1]),
		query: (length(parts) > 1) ? ('?' + parts[1]) : ''
	};
}

function upstreamHeader(request, name) {
	let value = headerValue(request.headers, name);
	return isEmpty(value) ? null : value;
}

function upstreamRequest(method, path, request, body) {
	body = body || '';

	let headers = [
		sprintf('%s %s HTTP/1.1', method, path),
		sprintf('Host: %s:%d', target.host, target.port),
		'Accept-Encoding: identity',
		'Connection: close'
	    ],
	    authorization = upstreamHeader(request, 'Authorization'),
	    origin = upstreamHeader(request, 'Origin');

	if (authorization)
		push(headers, 'Authorization: ' + authorization);

	if (origin)
		push(headers, 'Origin: ' + origin);

	if (length(body)) {
		let content_type = upstreamHeader(request, 'Content-Type');

		if (content_type)
			push(headers, 'Content-Type: ' + content_type);

		push(headers, 'Content-Length: ' + length(body));
	}

	return join("\r\n", headers) + "\r\n\r\n" + body;
}

function fetchUpstream(method, path, request, body) {
	let upstream = socket.connect(target.host, target.port, null, 3000);

	if (upstream === null)
		return null;

	let raw = '';

	if (!sendAll(upstream, upstreamRequest(method, path, request, body))) {
		upstream.close();
		return null;
	}

	for (let i = 0; i < 512; i++) {
		let chunk = upstream.recv(16384);

		if (chunk === null)
			break;

		if (length(chunk) === 0)
			break;

		raw += chunk;

		if (responseComplete(raw))
			break;
	}

	upstream.close();

	return raw;
}

function fetchVisibleProxyGroup(group_name, request) {
	let raw = fetchUpstream('GET', '/proxies', request);
	if (raw === null)
		return null;

	let payload = filterProxiesPayload(parseJsonBody(raw));
	if (type(payload) !== 'object' || type(payload.proxies) !== 'object')
		return null;

	let group = payload.proxies[group_name];
	return (type(group) === 'object') ? group : null;
}

function testProxyDelay(proxy_name, query, request) {
	let raw = fetchUpstream('GET',
		'/proxies/' + pathSegment(proxy_name) + '/delay' + query,
		request);

	if (raw === null || responseStatus(raw) < 200 || responseStatus(raw) >= 300)
		return 0;

	let payload = parseJsonBody(raw);

	if (type(payload) === 'object' && type(payload.delay) === 'double')
		return int(payload.delay);

	if (type(payload) === 'object' && type(payload.delay) === 'int')
		return payload.delay;

	return 0;
}

function fallbackGroupDelay(group_info, request) {
	let group = fetchVisibleProxyGroup(group_info.name, request);
	if (group === null || type(group.all) !== 'array')
		return null;

	let results = {},
	    tested = 0,
	    truncated = false;

	for (let proxy_name in group.all) {
		if (isShadowTlsTag(proxy_name))
			continue;

		if (tested >= fallback_delay_limit) {
			truncated = true;
			break;
		}

		results[proxy_name] = testProxyDelay(proxy_name, group_info.query, request);
		tested++;
	}

	if (truncated)
		warn(sprintf('homeproxy clash api proxy: fallback delay for group %s limited to first %d visible proxies\n',
			group_info.name, fallback_delay_limit));

	return results;
}

function handleGroupDelay(conn, request, group_info) {
	let raw = fetchUpstream(request.method, request.path, request, request.body),
	    payload = parseJsonBody(raw),
	    status = raw === null ? 0 : responseStatus(raw);

	if (type(payload) === 'object')
		payload = filterProxiesPayload(payload);

	if (status >= 200 && status < 300 && !isEmptyObject(payload)) {
		sendAll(conn.client, buildJsonResponse(request, payload));
		closeConnection(conn);
		return true;
	}

	payload = fallbackGroupDelay(group_info, request);
	if (payload !== null) {
		sendAll(conn.client, buildJsonResponse(request, payload));
		closeConnection(conn);
		return true;
	}

	if (raw !== null)
		sendAll(conn.client, raw);

	closeConnection(conn);
	return true;
}

function resetTimer(conn) {
	if (conn.timer)
		conn.timer.set(filter_timeout);
}

function relayRead(conn, from, to) {
	let received = recvAvailable(from);

	if (length(received.data) && !sendAll(to, received.data)) {
		closeConnection(conn);
		return;
	}

	if (received.eof)
		closeConnection(conn);
}

function setupRelay(conn) {
	conn.client_handle = uloop.handle(conn.client, (events, eof, error) => {
		if (events & uloop.ULOOP_READ)
			relayRead(conn, conn.client, conn.upstream);

		if (eof || error)
			closeConnection(conn);
	}, uloop.ULOOP_READ);

	conn.upstream_handle = uloop.handle(conn.upstream, (events, eof, error) => {
		if (events & uloop.ULOOP_READ)
			relayRead(conn, conn.upstream, conn.client);

		if (eof || error)
			closeConnection(conn);
	}, uloop.ULOOP_READ);
}

function finishFilteredResponse(conn) {
	sendAll(conn.client, filterResponse(conn.response_buffer));
	closeConnection(conn);
}

function setupFilteredResponse(conn) {
	conn.response_buffer = '';
	conn.timer = uloop.timer(filter_timeout, () => closeConnection(conn));

	conn.upstream_handle = uloop.handle(conn.upstream, (events, eof, error) => {
		if (events & uloop.ULOOP_READ) {
			let received = recvAvailable(conn.upstream);

			if (length(received.data)) {
				conn.response_buffer += received.data;
				resetTimer(conn);
			}

			if (responseComplete(conn.response_buffer) || received.eof) {
				finishFilteredResponse(conn);
				return;
			}
		}

		if (eof || error) {
			if (length(conn.response_buffer))
				finishFilteredResponse(conn);
			else
				closeConnection(conn);
		}
	}, uloop.ULOOP_READ);
}

function startUpstream(conn, request) {
	try {
		let group_delay = parseGroupDelayPath(request.path);

		if (request.method === 'GET' && group_delay !== null)
			return handleGroupDelay(conn, request, group_delay);

		if (conn.client_handle) {
			conn.client_handle.delete();
			conn.client_handle = null;
		}

		conn.filter_read = shouldFilter(request.method, request.path);
		conn.upstream = socket.connect(target.host, target.port, null, 3000);

		if (conn.upstream === null) {
			warn(sprintf('homeproxy clash api proxy: connect to %s:%d failed: %s\n',
				target.host, target.port, socket.error()));
			closeConnection(conn);
			return;
		}

		let upstream_request = (conn.filter_read || !isUpgradeRequest(request))
			? rebuildCloseRequest(request)
			: conn.request_buffer;
		if (!sendAll(conn.upstream, upstream_request)) {
			warn('homeproxy clash api proxy: failed to send upstream request\n');
			closeConnection(conn);
			return;
		}

		conn.request_buffer = '';

		if (conn.filter_read)
			setupFilteredResponse(conn);
		else
			setupRelay(conn);
	} catch (e) {
		warn(sprintf('homeproxy clash api proxy: start upstream exception: %J\n', e));
		closeConnection(conn);
	}
}

function onClientRequest(conn, events, eof, error) {
	if (events & uloop.ULOOP_READ) {
		let received = recvAvailable(conn.client);

		if (length(received.data))
			conn.request_buffer += received.data;

		let request = parseHttpMessage(conn.request_buffer);
		if (request !== null) {
			startUpstream(conn, request);
			return;
		}

		if (received.eof) {
			closeConnection(conn);
			return;
		}
	}

	if (eof || error)
		closeConnection(conn);
}

function acceptClients(server) {
	while (true) {
		let client = server.accept();

		if (client === null)
			break;

		let conn = {
			id: next_id++,
			client,
			upstream: null,
			client_handle: null,
			upstream_handle: null,
			timer: null,
			request_buffer: '',
			response_buffer: ''
		};

		connections[conn.id] = conn;
		conn.client_handle = uloop.handle(client, (events, eof, error) => onClientRequest(conn, events, eof, error), uloop.ULOOP_READ);
	}
}

const clash_api_enabled = uci.get(uciconfig, ucimain, 'clash_api_enabled') || '0';

if (clash_api_enabled !== '1')
	exit(0);

target = parseController(uci.get(uciconfig, ucimain, 'clash_api_external_controller') || '192.168.9.1:9090', 9090);
listen = isEmpty(uci.get(uciconfig, ucimain, 'clash_api_proxy_external_controller'))
	? deriveProxyController((index(target.host, ':') >= 0 ? '[' + target.host + ']' : target.host) + ':' + target.port)
	: parseController(uci.get(uciconfig, ucimain, 'clash_api_proxy_external_controller'), 9091);

if (isEmpty(listen.host))
	listen.host = '192.168.9.1';

server = socket.listen(listen.host, listen.port, null, 128, true);

if (server === null) {
	warn(sprintf('homeproxy clash api proxy: failed to listen on %s:%d: %s\n', listen.host, listen.port, socket.error()));
	exit(1);
}

uloop.init();
uloop.handle(server, () => acceptClients(server), uloop.ULOOP_READ);

warn(sprintf('homeproxy clash api proxy: listening on %s:%d, forwarding to %s:%d\n',
	listen.host, listen.port, target.host, target.port));

uloop.run();
