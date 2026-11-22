// The test log's words (src/logic/explain.js): each tab sorted into one group, sites by host name only, and the
// text a saved log reads as.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { explainCheck, checkSentence, host, clock, logText, ago } from '../src/logic/explain.js';
import { TEST_BUILD } from '../src/build.js';
import { tab, ctx, used, NOW, MIN } from './helpers.js';

test('the repository and the store build keep the test log off', () => {
  assert.equal(TEST_BUILD, false);
});

test('sites appear by host name only', () => {
  assert.equal(host('https://mail.example.com/inbox/12345?q=private#x'), 'mail.example.com');
  assert.equal(host('file:///Users/someone/notes.html'), 'a file');
  assert.equal(host('not a url'), 'a page');
});

test('each tab falls into one group, in the order the rules check them', () => {
  const front = tab({ active: true });
  const asleep = tab({ discarded: true });
  const pinned = tab({ pinned: true });
  const chromeKeeps = tab({ autoDiscardable: false });
  const a = tab(); const b = tab(); const c = tab(); const d = tab(); const e = tab();
  const settings = tab({ url: 'chrome://settings' });
  const use = { [a.id]: used(1, 9), [b.id]: used(2, 8), [c.id]: used(3, 7), [d.id]: used(40, 1), [e.id]: { last: NOW - 10 * 1000, left: NOW - 10 * 1000, switches: [] } };
  const c1 = ctx({ use, frontTabId: front.id });
  const n = explainCheck([front, asleep, pinned, chromeKeeps, a, b, c, d, e, settings], c1);
  assert.equal(n.pages, 9);
  assert.deepEqual([n.front, n.asleep, n.held.pinned, n.chromeKeeps], [1, 1, 1, 1]);
  assert.equal(n.mostUsed + n.waiting + n.due, 5);
  assert.equal(n.mostUsed, 2); // Balanced keeps 3 most used, the front tab taking one place
  assert.equal(checkSentence(n, c1).startsWith('Balanced, 9 pages: 1 in front; 1 asleep; held: 1 pinned;'), true);
});

test('Auto leaves everything alone while memory is fine', () => {
  const t1 = tab(); const t2 = tab();
  const n = explainCheck([t1, t2], ctx({ level: 'auto', autoMode: 'off', autoAllowed: true }));
  assert.equal(n.autoQuiet, 2);
  assert.equal(checkSentence(n, ctx({ level: 'auto' })), 'Auto, 2 pages: 2 left alone while memory is fine.');
});

test('a saved log reads one line per entry, oldest first, times as 2:15:07pm', () => {
  const at = new Date(2026, 10, 22, 14, 15, 7).getTime();
  assert.equal(clock(at), '2:15:07pm');
  assert.equal(clock(new Date(2026, 10, 22, 0, 5, 0).getTime()), '12:05:00am');
  const text = logText([{ at, kind: 'slept', text: 'Slept example.com', data: { tab: 4 } }], 'header');
  assert.equal(text, 'header\n2026-11-22 2:15:07pm  slept  Slept example.com  {"tab":4}\n');
  assert.equal(ago(NOW - 40 * 1000, NOW), '40 seconds ago');
  assert.equal(ago(NOW - 12 * MIN, NOW), '12 minutes ago');
  assert.equal(ago(null, NOW), 'never used');
});
