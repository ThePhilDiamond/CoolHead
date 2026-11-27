// What the popup says, alone, together, and after the link drops.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildView, buildStart, RESULT_MS } from '../src/logic/view.js';
import { LOCAL_DEFAULTS, SESSION_DEFAULTS } from '../src/store.js';
import { tab, NOW, MIN } from './helpers.js';

function state(over = {}) {
  return { ...structuredClone(LOCAL_DEFAULTS), ...structuredClone(SESSION_DEFAULTS), ...over };
}
const linked = (memory, extra = {}) => ({ link: { status: 'linked', app: '0.16.0', state: { memory, auto: true }, stateAt: NOW - 5000, attemptAt: null }, ...extra });

function view(tabs, s, over = {}) {
  return buildView({ tabs, s, now: NOW, focusedWindowId: 1, isMac: true, memInfo: null, version: '1.0.0', ...over });
}

test('together: the band follows Cool Head\'s reading, and the snowflake melts when memory is short', () => {
  const asleep = [tab({ discarded: true }), tab({ discarded: true })];
  const s = state({ ...linked('veryTight'), level: 'auto', asleep: asleep.map((t) => t.id) });
  const v = view([tab({ active: true }), ...asleep], s);
  assert.equal(v.band.title, 'Memory is very tight');
  assert.equal(v.band.tone, 'bad');
  assert.equal(v.band.melting, true);
  assert.equal(v.band.line, '2 tabs asleep. Each wakes when you click it.');
  assert.deepEqual(v.band.link, { state: 'linked', text: 'Working with Cool Head' });
  assert.equal(v.notice, null);
  assert.equal(v.levels.options.find((o) => o.id === 'auto').disabled, false);
  const fine = view([], state({ ...linked('fine'), level: 'auto' }));
  assert.equal(fine.band.tone, 'good');
  assert.equal(fine.band.melting, false);
});

test('only tabs this extension put to sleep are counted, not ones Chrome unloaded itself', () => {
  const ours = tab({ discarded: true });
  const chromes = tab({ discarded: true });
  const v = view([ours, chromes], state({ ...linked('fine'), asleep: [ours.id] }));
  assert.equal(v.band.line, '1 tab asleep. It wakes when you click it.');
});

test('alone on a Mac: says so, offers Cool Head, and Auto is unavailable with the reason', () => {
  const v = view([], state({ link: { status: 'notInstalled' }, level: 'balanced' }));
  assert.equal(v.band.title, 'Working on its own');
  assert.deepEqual(v.band.link, { state: 'notLinked', text: 'Not linked to Cool Head' });
  assert.equal(v.notice.link.url, 'https://github.com/ThePhilDiamond/CoolHead');
  const auto = v.levels.options.find((o) => o.id === 'auto');
  assert.equal(auto.disabled, true);
  assert.equal(v.levels.needs, 'Auto needs Cool Head, which knows when memory is short.');
});

test('alone because Cool Head is closed: says to open it, offers no download', () => {
  const v = view([], state({ link: { status: 'notRunning' } }));
  assert.equal(v.band.link.text, "Cool Head isn't open");
  assert.equal(v.notice.link, null);
});

test('dropped while on Auto: the level stays Auto, and it says it is waiting for Cool Head', () => {
  const v = view([], state({ link: { status: 'notLinked' }, level: 'auto' }));
  assert.equal(v.levels.chosen, 'auto');
  assert.match(v.levels.line, /^Auto is waiting for Cool Head/);
  assert.equal(v.levels.needs, null);
});

test('linked but the reading went stale: treated as no reading', () => {
  const s = state({ ...linked('slowed'), level: 'auto' });
  s.link.stateAt = NOW - 60000;
  const v = view([], s);
  assert.equal(v.band.title, 'Working with Cool Head');
  assert.equal(v.band.tone, 'none');
  assert.match(v.levels.line, /^Auto is waiting/);
});

test('Cool Head says Auto is off: the line says where to turn it on', () => {
  const s = state({ ...linked('slowed'), level: 'auto' });
  s.link.state.auto = false;
  assert.match(view([], s).levels.line, /^Auto is off in Cool Head's settings/);
});

test('on Windows and Linux there is no Cool Head: no Auto, no offer, Chrome\'s own memory reading', () => {
  const v = view([], state({ link: { status: 'notInstalled' } }), { isMac: false, memInfo: { capacity: 16 * 1024 ** 3, availableCapacity: 2.5 * 1024 ** 3 } });
  assert.equal(v.levels.options.some((o) => o.id === 'auto'), false);
  assert.equal(v.notice, null);
  assert.equal(v.band.link, null);
  assert.equal(v.band.line, "About 2.5 GB of 16 GB free, by Chrome's count.");
});

test('held list: every tab held and why, risky ones first, Keep hidden on pinned tabs by flag', () => {
  const music = tab({ audible: true, title: 'Lo-fi beats' });
  const typing = tab({ title: 'Expense form' });
  const pinned = tab({ pinned: true, title: 'Calendar' });
  const quiet = tab({ title: 'Quiet call' });
  const plain = tab();
  const s = state({ typing: { [typing.id]: { 0: true } }, audibleAt: { [quiet.id]: NOW - 3 * MIN }, media: {} });
  const v = view([music, typing, pinned, quiet, plain], s);
  assert.deepEqual(v.held.tabs.map((r) => r.title), ['Expense form', 'Lo-fi beats', 'Quiet call', 'Calendar']);
  assert.equal(v.held.tabs[0].risk, 'typing');
  assert.equal(v.held.tabs[2].reasonText, 'Played sound recently');
  assert.equal(v.held.tabs[3].pinned, true);
  assert.equal(v.held.countText, '4 tabs');
});

test('a call seen in any frame of a tab counts for the tab', () => {
  const call = tab();
  const v = view([call], state({ media: { [call.id]: { 0: { call: false, screen: false }, 7: { call: true, screen: false } } } }));
  assert.equal(v.held.tabs[0].reason, 'call');
  assert.equal(v.held.tabs[0].risk, 'call');
});

test('during a session, its tabs show in the session card, not the held list, and the level pauses', () => {
  const front = tab({ active: true, audible: true });
  const other = tab({ discarded: true });
  const s = state({ session: { active: true, tabIds: [front.id], startedAt: NOW - 10 * MIN }, level: 'balanced' });
  const v = view([front, other], s);
  assert.equal(v.session.title, 'In session: 1 tab. 1 other asleep.');
  assert.equal(v.held.tabs.length, 0);
  assert.match(v.levels.line, /^Paused while a session runs/);
  assert.match(v.session.defaultName, /^Session at \d{1,2}(:\d\d)?(am|pm), Nov 21$/);
});

test('duplicates card words', () => {
  const a = tab({ url: 'https://x.example/a', title: 'Inbox' });
  const b = tab({ url: 'https://x.example/a', title: 'Inbox' });
  const c = tab({ url: 'https://x.example/b', title: 'Spring budget' });
  const d = tab({ url: 'https://x.example/b', title: 'Spring budget' });
  const v = view([a, b, c, d], state());
  assert.equal(v.duplicates.title, '2 pages are open twice');
  assert.equal(v.duplicates.line, 'Inbox and Spring budget each have a second copy. Closing keeps the copy you used last, so you keep your place.');
  assert.equal(v.duplicates.button, 'Close 2 duplicates');
});

// ---- option cues: one recommendation on home, and Close duplicates done, then next ----
const REC = 'Cool Head for Chrome recommends this';
function dupTabs({ asleep = false } = {}) {
  const a = tab({ url: 'https://x.example/a', title: 'Inbox' });
  const b = tab({ url: 'https://x.example/a', title: 'Inbox', discarded: asleep });
  return [a, b];
}

test('one recommendation: Close duplicates over Allow and choose, the only option that helps now', () => {
  const v = view(dupTabs(), state());
  assert.equal(v.extRec, true);
  assert.equal(v.dupsFrees, true);
  assert.deepEqual(v.recommended, { id: 'dups', why: `${REC} because it is the only option that helps.` });
});

test('one recommendation: a sleeping copy frees nothing, so Allow and choose is recommended and Close duplicates has no Helps tag', () => {
  for (const asleep of [{ discarded: true }, { status: 'unloaded' }]) {
    const [a] = dupTabs();
    const b = tab({ url: 'https://x.example/a', title: 'Inbox', ...asleep });
    const v = view([a, b], state());
    assert.equal(v.dupsFrees, false);
    assert.deepEqual(v.recommended, { id: 'extrec', why: `${REC}.` });
    // with the extensions card set aside, nothing on home frees memory: Start a session is the blue one
    assert.deepEqual(view([a, b], state({ extRecDismissed: true })).recommended, { id: 'start', why: null });
  }
});

test('one recommendation: a card alone is recommended without a reason, and Start a session only with no card', () => {
  assert.deepEqual(view([tab({ active: true })], state()).recommended, { id: 'extrec', why: `${REC}.` });
  assert.deepEqual(view(dupTabs(), state({ extRecDismissed: true })).recommended, { id: 'dups', why: `${REC}.` });
  assert.deepEqual(view([tab({ active: true })], state({ extRecDismissed: true })).recommended, { id: 'start', why: null });
});

test('done, then next: the result holds the recommendation for its few seconds, then the next card is recommended', () => {
  // Close duplicates pressed: the copy is gone, and what closed was saved with when
  const [kept] = dupTabs();
  const s = state({ closedDups: { at: NOW - 1000, groups: [{ title: 'Inbox', n: 1 }] } });
  const during = view([kept], s);
  assert.deepEqual(during.closedDups, { failed: false, groups: [{ title: 'Inbox', n: 1 }], n: 1, until: NOW - 1000 + RESULT_MS });
  assert.deepEqual(during.recommended, { id: 'dups', why: null });
  // a moment before the time is up it still shows; at the time it goes, and Allow and choose is the recommendation
  assert.notEqual(view([kept], s, { now: NOW - 1000 + RESULT_MS - 1 }).closedDups, null);
  const after = view([kept], s, { now: NOW - 1000 + RESULT_MS });
  assert.equal(after.closedDups, null);
  assert.deepEqual(after.recommended, { id: 'extrec', why: `${REC}.` });
});

test('done, then next: a failure stays on the duplicates card, however long, and Close duplicates stays recommended to try again', () => {
  const s = state({ closedDups: { at: NOW - 60 * MIN, failed: true } });
  const v = view(dupTabs(), s);
  assert.equal(v.closedDups.failed, true);
  assert.equal(v.closedDups.until, null);
  assert.ok(v.duplicates, 'the duplicates card, with its button, is still there');
  assert.deepEqual(v.recommended, { id: 'dups', why: `${REC} because it is the only option that helps.` });
  // the copies closed by hand: no card, so no line saying they're still open, and the next card is recommended
  const [kept] = dupTabs();
  const byHand = view([kept], s);
  assert.equal(byHand.duplicates, null);
  assert.equal(byHand.recommended.id, 'extrec');
});

test('done, then next: a result saved at a time ahead of the clock is not shown', () => {
  const [kept] = dupTabs();
  assert.equal(view([kept], state({ closedDups: { at: NOW + 60 * MIN, groups: [{ title: 'Inbox', n: 1 }] } })).closedDups, null);
  // nor brought back if the clock moves back after it went
  assert.equal(view([kept], state({ closedDups: { at: NOW + 1000, groups: [{ title: 'Inbox', n: 1 }] } })).closedDups, null);
});

test('done, then next: a result saved by an earlier version (a list with no time) is not shown', () => {
  const v = view(dupTabs(), state({ closedDups: [{ title: 'Inbox', n: 1 }] }));
  assert.equal(v.closedDups, null);
  assert.equal(v.recommended.id, 'dups');
});

test('a kept tab matched twice after a restart becomes a question with each place named', () => {
  const a = tab({ windowId: 1, index: 2, url: 'https://a.example/' });
  const b = tab({ windowId: 2, index: 0, url: 'https://a.example/' });
  const s = state({ keepQuestions: [{ record: { tabId: 1, url: 'https://a.example/', title: 'Inbox', index: 4, windowOrdinal: 0 }, candidates: [a.id, b.id] }] });
  const q = view([a, b], s).questions[0];
  assert.equal(q.line, 'Chrome restarted, and "Inbox" is open in 2 tabs. Choose the one to keep loaded.');
  assert.deepEqual(q.options.map((o) => o.label), ['Window 1, tab 3', 'Window 2, tab 1']);
});

test('Start a session says what unticking each tab would do', () => {
  const front = tab({ active: true });
  const recent = tab();
  const old = tab();
  const music = tab({ audible: true });
  const s = state({ use: { [recent.id]: { last: NOW - 2 * MIN, left: NOW - 2 * MIN, switches: [] } } });
  const st = buildStart({ tabs: [front, recent, old, music], s, now: NOW, focusedWindowId: 1 });
  const by = Object.fromEntries(st.rows.map((r) => [r.id, r]));
  assert.deepEqual(st.suggested, [front.id, music.id, recent.id]);
  assert.equal(by[old.id].ifUnticked, 'sleep');
  assert.equal(by[music.id].ifUnticked, 'sound');
  assert.equal(by[front.id].ifUnticked, 'active');
  assert.equal(st.windowTabs, 4);
});
