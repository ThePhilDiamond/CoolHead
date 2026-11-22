// Cool Head's voice, the mechanical parts (docs/BRAND.md, "Voice"): no em dashes, no exclamation marks, the
// Oxford comma, times as 8:45am and 2pm. Whether each sentence ends in what it means for the person is read by eye.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as W from '../src/logic/words.js';

const ROOT = path.dirname(path.dirname(fileURLToPath(import.meta.url)));

// Every string the words module can produce, from its constants and from its functions with sample arguments.
function allWords() {
  const out = [];
  const walk = (v) => {
    if (typeof v === 'string') out.push(v);
    else if (typeof v === 'function') {
      for (const args of [[0], [1], [2], [23], ['A tab'], [1, 'Inbox', 0], [3, 'Harbor & Pine meeting', 2], ['close', 'typing'], ['sleep', 'call'], ['close', 'screen']]) {
        try { walk(v(...args)); } catch { /* not for these arguments */ }
      }
    } else if (v && typeof v === 'object') Object.values(v).forEach(walk);
  };
  Object.values(W).forEach(walk);
  for (const level of ['auto', 'light', 'balanced', 'focus']) {
    for (const o of [{}, { delayMs: 0 }, { linked: false }, { coolHeadAuto: false }, { autoMode: 'slowed' }, { autoMode: 'veryTight' }, { session: true }]) out.push(W.levelLine(level, o));
  }
  out.push(W.startNote(31, [{ reason: 'sound' }, { reason: 'typing' }], true), W.startNote(0, [{ reason: 'kept' }], false));
  out.push(...Object.values(W.duplicatesCard([{ title: 'Inbox', closeIds: [1] }, { title: 'Budget', closeIds: [2, 3] }])));
  return out.filter(Boolean);
}

test('no em dashes or exclamation marks in anything the extension says', () => {
  const words = allWords();
  assert.ok(words.length > 100, `checked ${words.length}`);
  for (const w of words) {
    assert.equal(w.includes('\u2014'), false, `em dash: ${w}`);
    assert.equal(w.includes('!'), false, `exclamation mark: ${w}`);
  }
});

test('no em dashes in any file of the extension', () => {
  const files = [];
  const walk = (dir) => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, e.name);
      if (e.isDirectory()) walk(p);
      else if (/\.(js|mjs|html|css|json|md)$/.test(e.name)) files.push(p);
    }
  };
  walk(ROOT);
  for (const f of files) assert.equal(fs.readFileSync(f, 'utf8').includes('\u2014'), false, f);
});

test('lists take the Oxford comma', () => {
  assert.equal(W.list(['Inbox']), 'Inbox');
  assert.equal(W.list(['Inbox', 'Budget']), 'Inbox and Budget');
  assert.equal(W.list(['Inbox', 'Budget', 'Wiki']), 'Inbox, Budget, and Wiki');
  assert.equal(W.list(['A', 'B', 'C', 'D', 'E']), 'A, B, and 3 others');
});

test('times read 8:45am, 2pm, 4:15pm', () => {
  assert.equal(W.clock(new Date(2026, 10, 21, 8, 45)), '8:45am');
  assert.equal(W.clock(new Date(2026, 10, 21, 14, 0)), '2pm');
  assert.equal(W.clock(new Date(2026, 10, 21, 16, 15)), '4:15pm');
  assert.equal(W.clock(new Date(2026, 10, 21, 0, 5)), '12:05am');
  assert.equal(W.clock(new Date(2026, 10, 21, 12, 0)), '12pm');
});

test('counts agree with their nouns', () => {
  assert.equal(W.asleepLine(1), '1 tab asleep. It wakes when you click it.');
  assert.equal(W.startButton(1), 'Start with 1 tab');
  assert.equal(W.startNote(1, [{ reason: 'sound' }], false), "1 tab sleeps. Nothing closes. 1 unticked tab stays loaded because it is playing sound.");
  assert.equal(W.startNote(31, [{ reason: 'sound' }, { reason: 'typing' }], false), "31 tabs sleep. Nothing closes. 2 unticked tabs stay loaded: 1 is playing sound and 1 has unsent typing.");
  assert.equal(W.startNote(3, [{ reason: 'pinned' }, { reason: 'pinned' }], false), '3 tabs sleep. Nothing closes. 2 unticked tabs stay loaded because they are pinned.');
  assert.equal(W.startNote(0, [{ reason: 'typing' }, { reason: 'typing' }, { reason: 'kept' }, { reason: 'call' }], true), "No tabs need to sleep. Nothing closes. 4 unticked tabs stay loaded: 2 have unsent typing, 1 is kept by you, and 1 is on a call. Extensions that aren't protected pause until it ends.");
  assert.equal(W.sessionTitle(4, 31), 'In session: 4 tabs. 31 others asleep.');
  assert.equal(W.usedAgo(30 * 1000), 'Used less than a minute ago');
  assert.equal(W.usedAgo(61 * 60 * 1000), 'Used 1 hour ago');
});

test('the warnings say what pressing again would cost', () => {
  assert.equal(W.warning('close', 'typing'), 'Closing loses what you typed in this tab. Press Close again to close it anyway.');
  assert.equal(W.warning('sleep', 'call'), 'Sleeping ends the call in this tab. Press Sleep again to sleep it anyway.');
});
