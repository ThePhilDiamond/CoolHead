#!/usr/bin/env node
// A stand-in for Cool Head's link host (PROTOCOL.md), for tests only. Chrome starts it the way it would start
// coolhead-chrome-host, and it speaks Chrome's framing on standard input and output. It plays Cool Head too, so
// no socket is involved. What it does comes from the COOLHEAD_MOCK environment variable or a file named by
// COOLHEAD_MOCK_FILE (read again on each tick, so a test can change the scenario while it runs):
//   { "app": "running" | "notRunning", "memory": "fine" | "tight" | "slowed" | "veryTight", "auto": true,
//     "requests": [{ "id": "r1", "action": "sleepHidden" }], "log": "/path/to/log.jsonl", "everyMs": 10000 }
// Every message from the extension is appended to the log, one JSON object per line.
import fs from 'node:fs';
import { encodeNative, NativeDecoder } from '../src/logic/framing.js';

function scenario() {
  try {
    if (process.env.COOLHEAD_MOCK_FILE) return JSON.parse(fs.readFileSync(process.env.COOLHEAD_MOCK_FILE, 'utf8'));
    return JSON.parse(process.env.COOLHEAD_MOCK || '{}');
  } catch {
    return {};
  }
}

const send = (obj) => process.stdout.write(encodeNative(obj));
const log = (obj) => { const s = scenario(); if (s.log) fs.appendFileSync(s.log, JSON.stringify(obj) + '\n'); };

let s = scenario();
let app = s.app || 'running';
const sentRequests = new Set();
send({ type: 'link', app });

function tick() {
  s = scenario();
  // "exit": true plays the host ending (Cool Head quit or was updated), which Chrome reports as a disconnect.
  if (s.exit) process.exit(0);
  if ((s.app || 'running') !== app) {
    app = s.app || 'running';
    send({ type: 'link', app });
  }
  if (app !== 'running') return;
  send({ v: 1, type: 'state', memory: s.memory || 'fine', freeMB: 2048, chromeMB: 3500, hiddenTabsMB: null, extensionsMB: null, auto: s.auto !== false, future: 'ignored' });
  for (const r of s.requests || []) {
    if (sentRequests.has(r.id)) continue;
    sentRequests.add(r.id);
    send({ v: 1, type: 'request', id: r.id, action: r.action });
  }
}

const decoder = new NativeDecoder(64 * 1024 * 1024);
process.stdin.on('data', (chunk) => {
  for (const m of decoder.push(new Uint8Array(chunk))) {
    log(m);
    if (m.type === 'hello' && app === 'running') {
      send({ v: 1, type: 'hello', app: 'mock' });
      tick();
    }
  }
});
process.stdin.on('end', () => process.exit(0));
setInterval(tick, s.everyMs || 10000);
