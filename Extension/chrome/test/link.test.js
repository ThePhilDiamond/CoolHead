// The link to Cool Head: messages, framing, the extension's end against a mock port, and the mock host as a
// real process speaking Chrome's framing.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { hello, report, result, parseIncoming, sameReport, reportDue, HOST_NAME } from '../src/logic/protocol.js';
import { encodeNative, NativeDecoder, encodeLine, LineDecoder, MAX_FROM_HOST } from '../src/logic/framing.js';
import { LinkClient } from '../src/link-client.js';

// ---- messages ----

test('every message the extension sends carries v 1 and its type', () => {
  assert.deepEqual(hello('1.0.0', 'auto'), { v: 1, type: 'hello', extension: '1.0.0', browser: 'chrome', level: 'auto' });
  const r = report({ asleep: 23, held: { sound: 1, call: 1, other: 9 }, session: { active: true, tabs: 4 }, duplicates: 2, extensionsResting: 0, level: 'light', toSleep: 12 });
  assert.deepEqual(r, {
    v: 1, type: 'report', asleep: 23,
    held: { sound: 1, call: 1, screen: 0, typing: 0, pinned: 0, kept: 0, session: 0 },
    session: { active: true, tabs: 4 }, duplicates: 2, extensionsResting: 0, level: 'light', toSleep: 12,
  });
  // how many it would sleep is a count like the rest: never anything but a whole number
  assert.equal(report({ toSleep: 'https://secret.example/' }).toSleep, 0);
  assert.equal(report({ toSleep: -3 }).toSleep, 0);
  assert.deepEqual(result('r1', true, 'Put 23 tabs to sleep.', 23), { v: 1, type: 'result', id: 'r1', ok: true, done: 'Put 23 tabs to sleep.', count: 23 });
});

test('a report carries counts only: no addresses, titles, or names can get in', () => {
  const r = report({ asleep: 1, held: { sound: 'https://secret.example/' }, session: { active: true, tabs: 1, title: 'Secret' }, level: 'auto' });
  const text = JSON.stringify(r);
  assert.equal(text.includes('secret'), false);
  assert.equal(text.includes('Secret'), false);
});

test('incoming messages are checked; unknown types, fields, and actions are ignored', () => {
  assert.deepEqual(parseIncoming({ type: 'link', app: 'running' }), { kind: 'link', app: 'running' });
  assert.equal(parseIncoming({ v: 1, type: 'link', app: 'maybe' }).kind, 'ignore');
  const st = parseIncoming({ v: 1, type: 'state', memory: 'veryTight', freeMB: 512, chromeMB: 3000, hiddenTabsMB: null, extensionsMB: 1600, auto: true, extra: 1 });
  assert.deepEqual(st, { kind: 'state', state: { memory: 'veryTight', freeMB: 512, chromeMB: 3000, hiddenTabsMB: null, extensionsMB: 1600, auto: true } });
  assert.equal(parseIncoming({ v: 1, type: 'state', memory: 'hot' }).kind, 'ignore');
  assert.deepEqual(parseIncoming({ v: 1, type: 'request', id: 7, action: 'closeDuplicates' }), { kind: 'request', id: '7', action: 'closeDuplicates' });
  assert.equal(parseIncoming({ v: 1, type: 'request', id: 'x', action: 'formatDisk' }).kind, 'ignore');
  assert.equal(parseIncoming({ v: 1, type: 'newThing' }).kind, 'ignore');
  assert.equal(parseIncoming({ v: 0, type: 'hello' }).kind, 'ignore');
  assert.equal(parseIncoming({ v: 2, type: 'hello', app: '2.0' }).kind, 'hello'); // a newer Cool Head still links
  assert.equal(parseIncoming('hello').kind, 'ignore');
  assert.equal(parseIncoming([1]).kind, 'ignore');
});

test('reports go out on change, at most every 10 seconds', () => {
  assert.equal(reportDue(null, 0), true);
  assert.equal(reportDue(1000, 10999), false);
  assert.equal(reportDue(1000, 11000), true);
  const a = report({ asleep: 1, level: 'auto' });
  assert.equal(sameReport(a, report({ asleep: 1, level: 'auto' })), true);
  assert.equal(sameReport(a, report({ asleep: 2, level: 'auto' })), false);
});

// ---- framing ----

test('Chrome framing: 4-byte little-endian length, then UTF-8 JSON', () => {
  const bytes = encodeNative({ type: 'link', app: 'running' });
  const len = new DataView(bytes.buffer).getUint32(0, true);
  assert.equal(len, bytes.length - 4);
  assert.equal(new TextDecoder().decode(bytes.subarray(4)), '{"type":"link","app":"running"}');
});

test('Chrome framing survives reads split anywhere, even inside a character', () => {
  const msgs = [{ a: 1 }, { title: 'Café ☕ résumé' }, { b: [1, 2, 3] }];
  const all = new Uint8Array(msgs.flatMap((m) => [...encodeNative(m)]));
  for (let cut = 1; cut < all.length; cut += 1) {
    const d = new NativeDecoder();
    const got = [...d.push(all.subarray(0, cut)), ...d.push(all.subarray(cut))];
    assert.deepEqual(got, msgs, `cut at ${cut}`);
  }
  const d = new NativeDecoder();
  const oneByOne = [];
  for (const byte of all) oneByOne.push(...d.push(Uint8Array.of(byte)));
  assert.deepEqual(oneByOne, msgs);
});

test('Chrome framing refuses a message over 1 MB from the host', () => {
  assert.throws(() => encodeNative({ big: 'x'.repeat(MAX_FROM_HOST) }), RangeError);
  const header = new Uint8Array(4);
  new DataView(header.buffer).setUint32(0, MAX_FROM_HOST + 1, true);
  assert.throws(() => new NativeDecoder().push(header), RangeError);
});

test('socket framing: one JSON object per line, split reads and blank lines handled', () => {
  const bytes = new Uint8Array([...encodeLine({ x: 'é' }), ...new TextEncoder().encode('\n'), ...encodeLine({ y: 2 })]);
  const d = new LineDecoder();
  const out = [];
  for (const byte of bytes) out.push(...d.push(Uint8Array.of(byte)));
  assert.deepEqual(out, [{ x: 'é' }, { y: 2 }]);
});

// ---- the extension's end, against a mock port ----

function mockPort() {
  const listeners = { message: [], disconnect: [] };
  return {
    sent: [],
    onMessage: { addListener: (f) => listeners.message.push(f) },
    onDisconnect: { addListener: (f) => listeners.disconnect.push(f) },
    postMessage(m) { if (this.closed) throw new Error('Attempting to use a disconnected port object'); this.sent.push(m); },
    disconnect() { this.closed = true; },
    async deliver(m) { for (const f of listeners.message) await f(m); },
    drop() { this.closed = true; for (const f of listeners.disconnect) f(); },
  };
}

function client({ error = '', onRequest } = {}) {
  const port = mockPort();
  const events = { status: [], states: [], requests: [] };
  const link = new LinkClient({
    connect: (name) => { assert.equal(name, HOST_NAME); return port; },
    lastError: () => error,
    helloInfo: () => ({ version: '1.0.0', level: 'balanced' }),
    onStatus: (s) => events.status.push(s),
    onState: (st) => events.states.push(st),
    onRequest: onRequest || (async (r) => { events.requests.push(r); return { ok: true, done: 'Put 3 tabs to sleep.', count: 3 }; }),
  });
  return { link, port, events };
}

test('alone: no host installed, the extension says not installed and works on its own', () => {
  const { link, port, events } = client({ error: 'Specified native messaging host not found.' });
  link.start();
  port.drop();
  assert.equal(link.status, 'notInstalled');
  assert.deepEqual(events.status, ['connecting', 'notInstalled']);
  assert.equal(link.send({ v: 1, type: 'report' }), false);
});

test('alone: host there, Cool Head not open; together once it opens', async () => {
  const { link, port, events } = client();
  link.start();
  await port.deliver({ type: 'link', app: 'notRunning' });
  assert.equal(link.status, 'notRunning');
  assert.equal(port.sent.length, 0);
  await port.deliver({ v: 1, type: 'state', memory: 'slowed' }); // not linked: ignored
  assert.equal(events.states.length, 0);
  await port.deliver({ type: 'link', app: 'running' });
  assert.equal(link.status, 'linked');
  assert.deepEqual(port.sent[0], { v: 1, type: 'hello', extension: '1.0.0', browser: 'chrome', level: 'balanced' });
});

test('together: readings are passed on, requests answered with a result', async () => {
  const { link, port, events } = client();
  link.start();
  await port.deliver({ type: 'link', app: 'running' });
  await port.deliver({ v: 1, type: 'hello', app: '0.16.0' });
  await port.deliver({ v: 1, type: 'state', memory: 'veryTight', freeMB: 300, auto: true });
  assert.equal(events.states[0].memory, 'veryTight');
  await port.deliver({ v: 1, type: 'request', id: 'r9', action: 'sleepHidden' });
  assert.deepEqual(events.requests, [{ id: 'r9', action: 'sleepHidden' }]);
  assert.deepEqual(port.sent.at(-1), { v: 1, type: 'result', id: 'r9', ok: true, done: 'Put 3 tabs to sleep.', count: 3 });
  assert.equal(link.send({ v: 1, type: 'report' }), true);
});

test('a request that fails still gets an answer, saying it failed', async () => {
  const { link, port } = client({ onRequest: async () => { throw new Error('No tabs'); } });
  link.start();
  await port.deliver({ type: 'link', app: 'running' });
  await port.deliver({ v: 1, type: 'request', id: 'r1', action: 'closeDuplicates' });
  assert.deepEqual(port.sent.at(-1), { v: 1, type: 'result', id: 'r1', ok: false, done: 'No tabs', count: 0 });
});

test('dropped: Cool Head closing or the host ending puts the extension back on its own', async () => {
  const { link, port, events } = client();
  link.start();
  await port.deliver({ type: 'link', app: 'running' });
  await port.deliver({ type: 'link', app: 'notRunning' });
  assert.equal(link.status, 'notRunning');
  await port.deliver({ v: 1, type: 'request', id: 'late', action: 'sleepHidden' }); // after the drop: not acted on
  assert.equal(events.requests.length, 0);
  port.drop();
  assert.equal(link.status, 'notLinked');
  assert.equal(link.connected, false);
  // Started again later, it links again.
  const again = mockPort();
  link.deps.connect = () => again;
  link.start();
  await again.deliver({ type: 'link', app: 'running' });
  assert.equal(link.status, 'linked');
});

test('dropped mid-send: a send on a closed port counts as a drop, not a crash', async () => {
  const { link, port } = client();
  link.start();
  await port.deliver({ type: 'link', app: 'running' });
  port.closed = true;
  assert.equal(link.send({ v: 1, type: 'report' }), false);
  assert.equal(link.status, 'notLinked');
});

test('a late disconnect or message from an old port does not touch the new link', async () => {
  const { link, port } = client();
  link.start();
  await port.deliver({ type: 'link', app: 'running' });
  port.closed = true;
  link.port = null; // as after a drop already handled
  const fresh = mockPort();
  link.deps.connect = () => fresh;
  link.start();
  await fresh.deliver({ type: 'link', app: 'running' });
  port.drop(); // the old port's disconnect arrives late
  await port.deliver({ type: 'link', app: 'notRunning' });
  assert.equal(link.status, 'linked');
  assert.equal(link.port, fresh);
});

test('a host that stops after saying hello is a drop, not a missing install', async () => {
  const { link, port } = client({ error: 'Native host has exited.' });
  link.start();
  await port.deliver({ type: 'link', app: 'running' });
  port.drop();
  assert.equal(link.status, 'notLinked');
});

// ---- the mock host as a real process ----

test('the mock host speaks Chrome framing: link, hello, state, request', async () => {
  const host = fileURLToPath(new URL('../tools/mock-host.mjs', import.meta.url));
  const child = spawn(process.execPath, [host], {
    env: { ...process.env, COOLHEAD_MOCK: JSON.stringify({ app: 'running', memory: 'slowed', requests: [{ id: 'q1', action: 'closeDuplicates' }], everyMs: 60000 }) },
    stdio: ['pipe', 'pipe', 'inherit'],
  });
  const decoder = new NativeDecoder();
  const got = [];
  let check = () => {};
  child.stdout.on('data', (c) => { got.push(...decoder.push(new Uint8Array(c))); check(); });
  const wait = (n) => new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`only ${got.length} messages: ${JSON.stringify(got)}`)), 5000);
    check = () => { if (got.length >= n) { clearTimeout(timer); resolve(); } };
    check();
  });
  try {
    await wait(1);
    assert.deepEqual(got[0], { type: 'link', app: 'running' });
    child.stdin.write(encodeNative(hello('1.0.0', 'auto'), 64 * 1024 * 1024));
    await wait(4);
    assert.equal(parseIncoming(got[1]).kind, 'hello');
    assert.deepEqual(parseIncoming(got[2]).state.memory, 'slowed');
    assert.deepEqual(parseIncoming(got[3]), { kind: 'request', id: 'q1', action: 'closeDuplicates' });
  } finally {
    child.kill();
  }
});
