// What the popup says, alone, together, and after the link drops.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildView, buildStart } from '../src/logic/view.js';
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
