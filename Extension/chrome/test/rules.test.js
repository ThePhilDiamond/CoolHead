// Duplicates, sessions, keep, held reasons, usage, and the extensions safe list.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { findDuplicates, duplicateCount } from '../src/logic/duplicates.js';
import { suggest, windowOnly, startPlan, join, leave, groupPlan } from '../src/logic/session.js';
import { rematch, keepRecord, windowOrdinals } from '../src/logic/keep.js';
import { heldReasons, primaryReason, risk, heldCounts, isCallPage } from '../src/logic/reasons.js';
import { recordActivation, rankMostUsed, lastUsed, replaceId, pruneUse } from '../src/logic/usage.js';
import { kindOf, isAlwaysOn, restPlan, columns, move, shouldWake } from '../src/logic/extensions.js';
import { tab, ctx, used, NOW, MIN } from './helpers.js';

// ---- duplicates ----

test('duplicates keep the copy used last and close the others', () => {
  const a1 = tab({ url: 'https://mail.example.com/inbox', title: 'Inbox' });
  const a2 = tab({ url: 'https://mail.example.com/inbox', title: 'Inbox' });
  const b = tab();
  const g = findDuplicates([a1, a2, b], ctx({ use: { [a1.id]: used(1), [a2.id]: used(20) } }));
  assert.equal(g.length, 1);
  assert.equal(g[0].keepId, a1.id);
  assert.deepEqual(g[0].closeIds, [a2.id]);
  assert.equal(duplicateCount(g), 1);
});

test('two Gmail accounts are not duplicates, and a different fragment is a different page', () => {
  const tabs = [
    tab({ url: 'https://mail.google.com/mail/u/0/#inbox' }), tab({ url: 'https://mail.google.com/mail/u/1/#inbox' }),
    tab({ url: 'https://mail.google.com/mail/u/0/#sent' }),
  ];
  assert.deepEqual(findDuplicates(tabs, ctx()), []);
});

test('a copy that is in front, kept, pinned, playing, or holding typing is never closed', () => {
  const url = 'https://docs.example.com/plan';
  const front = tab({ url, active: true });
  const kept = tab({ url });
  const pinned = tab({ url, pinned: true });
  const typing = tab({ url });
  const plain = tab({ url });
  const g = findDuplicates([front, kept, pinned, typing, plain], ctx({ kept: new Set([kept.id]), typing: { [typing.id]: true } }));
  assert.equal(g[0].keepId, front.id);
  assert.deepEqual(g[0].closeIds, [plain.id]);
  // Nothing closable: no card at all.
  assert.deepEqual(findDuplicates([front, kept], ctx({ kept: new Set([kept.id]) })), []);
});

// ---- sessions ----

test('suggestions: the tab in front, calls, sound, kept, and the last 10 minutes, in that order', () => {
  const front = tab({ active: true });
  const call = tab({ url: 'https://meet.google.com/abc-defg-hij' });
  const music = tab({ audible: true });
  const kept = tab();
  const recent = tab();
  const old = tab();
  const c = ctx({ frontTabId: front.id, kept: new Set([kept.id]), use: { [recent.id]: used(4), [old.id]: used(40) } });
  const s = suggest([old, recent, kept, music, call, front], c);
  assert.deepEqual(s.suggested.map((r) => r.id), [front.id, call.id, music.id, kept.id, recent.id]);
  assert.deepEqual(s.suggested.map((r) => r.why), ["The tab you're on", 'On a call', 'Playing sound', 'Kept by you', 'Used 4 minutes ago']);
  assert.deepEqual(s.others.map((r) => r.id), [old.id]);
  assert.equal(s.others[0].why, 'Used 40 minutes ago');
});

test('"This window only" ticks this window\'s tabs and unticks the rest', () => {
  const rows = [{ id: 1, windowId: 1 }, { id: 2, windowId: 2 }, { id: 3, windowId: 1 }];
  assert.deepEqual([...windowOnly(rows, 1)], [1, 3]);
});

test('starting sleeps unticked tabs and says which stay loaded and why', () => {
  const front = tab({ active: true });
  const other = tab();
  const music = tab({ audible: true });
  const typing = tab();
  const otherWindowFront = tab({ active: true, windowId: 2 });
  const p = startPlan([front, other, music, typing, otherWindowFront], [front.id], ctx({ typing: { [typing.id]: true } }));
  assert.deepEqual(p.sleep, [other.id]);
  assert.deepEqual(p.stayLoaded, [{ id: music.id, reason: 'sound' }, { id: typing.id, reason: 'typing' }, { id: otherWindowFront.id, reason: 'active' }]);
});

test('a tab opened or switched to joins the session; a closed one leaves it', () => {
  const s = { active: true, tabIds: [1, 2], startedAt: NOW };
  assert.deepEqual(join(s, 3).tabIds, [1, 2, 3]);
  assert.equal(join(s, 2), s);
  assert.equal(join(null, 3), null);
  assert.deepEqual(leave(s, 1).tabIds, [2]);
});

test('saving groups tabs per window, leaves pinned tabs and tabs already in a group alone', () => {
  const tabs = [tab({ windowId: 1 }), tab({ windowId: 2 }), tab({ windowId: 1, pinned: true }), tab({ windowId: 1, groupId: 7 }), tab({ windowId: 1 })];
  const p = groupPlan(tabs, tabs.map((t) => t.id));
  assert.deepEqual(p.byWindow, { 1: [tabs[0].id, tabs[4].id], 2: [tabs[1].id] });
  assert.deepEqual(p.pinned, [tabs[2].id]);
  assert.deepEqual(p.alreadyGrouped, [tabs[3].id]);
});

// ---- keep, after a restart ----

test('a kept tab that never went away keeps its record', () => {
  const t = tab({ url: 'https://a.example/' });
  const r = keepRecord(t, windowOrdinals([t]));
  assert.deepEqual(rematch([r], [t]).kept.map((k) => k.tabId), [t.id]);
});

test('after a restart, one tab with the address is the kept tab', () => {
  const rec = { tabId: 5, url: 'https://a.example/', title: 'A', index: 2, windowOrdinal: 0 };
  const t = tab({ id: 900, url: 'https://a.example/', index: 4 });
  const out = rematch([rec], [t]);
  assert.equal(out.kept[0].tabId, 900);
});

test('after a restart, two matches are told apart by window and position, or asked about', () => {
  const rec = { tabId: 5, url: 'https://a.example/', title: 'A', index: 2, windowOrdinal: 1 };
  const w1 = tab({ id: 901, windowId: 10, url: 'https://a.example/', index: 2 });
  const w2 = tab({ id: 902, windowId: 20, url: 'https://a.example/', index: 2 });
  // Same position in both windows; the second window is the one it was in.
  assert.equal(rematch([rec], [w1, w2]).kept[0].tabId, 902);
  // Same window, both moved: ask.
  const a = tab({ id: 903, windowId: 20, url: 'https://a.example/', index: 0 });
  const b = tab({ id: 904, windowId: 20, url: 'https://a.example/', index: 5 });
  const q = rematch([rec], [w1, a, b]);
  assert.equal(q.kept.length, 0);
  assert.deepEqual(q.questions[0].candidates, [901, 903, 904]);
});

test('two kept tabs with the same address each find their own', () => {
  const r1 = { tabId: 1, url: 'https://a.example/', index: 0, windowOrdinal: 0 };
  const r2 = { tabId: 2, url: 'https://a.example/', index: 3, windowOrdinal: 0 };
  const t1 = tab({ id: 801, url: 'https://a.example/', index: 0 });
  const t2 = tab({ id: 802, url: 'https://a.example/', index: 3 });
  const out = rematch([r1, r2], [t1, t2]);
  assert.deepEqual(out.kept.map((k) => k.tabId).sort(), [801, 802]);
});

test('a kept tab not open any more is reported lost', () => {
  const rec = { tabId: 5, url: 'https://gone.example/', index: 0, windowOrdinal: 0 };
  assert.equal(rematch([rec], [tab()]).lost.length, 1);
});

// ---- why a tab is held ----

test('reasons come in order of what would be lost first', () => {
  const t = tab({ pinned: true, audible: true });
  const r = heldReasons(t, ctx({ typing: { [t.id]: true }, kept: new Set([t.id]) }));
  assert.deepEqual(r, ['typing', 'sound', 'kept', 'pinned']);
  assert.equal(primaryReason(r), 'typing');
  assert.equal(risk(r), 'typing');
  assert.equal(risk(['sound', 'pinned']), null);
});

test('held counts add up to the tabs held, each under its main reason', () => {
  const t1 = tab({ audible: true, pinned: true });
  const t2 = tab({ pinned: true });
  const t3 = tab({ pinned: true, discarded: true });
  const counts = heldCounts([t1, t2, t3, tab()], ctx());
  assert.equal(counts.sound, 1);
  assert.equal(counts.pinned, 1);
  assert.equal(Object.values(counts).reduce((a, b) => a + b, 0), 2);
});

test('meeting rooms are recognized by address; other pages of the same products are not', () => {
  assert.equal(isCallPage('https://meet.google.com/abc-defg-hij?authuser=0'), true);
  assert.equal(isCallPage('https://meet.google.com/landing'), false);
  assert.equal(isCallPage('https://us02web.zoom.us/wc/123456/join'), true);
  assert.equal(isCallPage('https://zoom.us/pricing'), false);
});

// ---- tab use ----

test('switching records use on the tab you go to and the time you left the other', () => {
  let use = recordActivation({}, 1, null, NOW - 5 * MIN);
  use = recordActivation(use, 2, 1, NOW);
  assert.equal(use[1].left, NOW);
  assert.equal(use[2].last, NOW);
  assert.equal(lastUsed({ id: 1 }, use), NOW);
  use = recordActivation(use, 1, 2, NOW + 1000);
  assert.equal(use[1].switches.length, 2);
});

test('switches older than 30 minutes stop counting toward most used', () => {
  const use = { 1: { last: NOW, left: NOW, switches: [NOW - 40 * MIN, NOW - 35 * MIN, NOW - 31 * MIN] }, 2: { last: NOW - MIN, left: NOW - MIN, switches: [NOW - MIN] } };
  assert.deepEqual(rankMostUsed([{ id: 1 }, { id: 2 }], use, NOW), [2, 1]);
});

test('a replaced tab keeps its record; closed tabs are pruned', () => {
  assert.deepEqual(replaceId({ 1: 'a', 2: 'b' }, 1, 9), { 2: 'b', 9: 'a' });
  assert.deepEqual(pruneUse({ 1: {}, 2: {} }, [2]), { 2: {} });
});

// ---- rest extensions ----

const EXTS = [
  { id: 'pw', name: '1Password: Password Manager', type: 'extension', enabled: true, mayDisable: true, installType: 'normal', permissions: ['storage'] },
  { id: 'ub', name: 'uBlock Origin Lite', type: 'extension', enabled: true, mayDisable: true, installType: 'normal', permissions: ['declarativeNetRequest'] },
  { id: 'vpn', name: 'Some VPN', type: 'extension', enabled: true, mayDisable: true, installType: 'normal', permissions: ['proxy'] },
  { id: 'org', name: 'Company tool', type: 'extension', enabled: true, mayDisable: false, installType: 'admin', permissions: [] },
  { id: 'grammar', name: 'Writing helper', type: 'extension', enabled: true, mayDisable: true, installType: 'normal', permissions: ['storage'] },
  { id: 'off', name: 'Already off', type: 'extension', enabled: false, mayDisable: true, installType: 'normal', permissions: [] },
  { id: 'theme', name: 'A theme', type: 'theme', enabled: true, mayDisable: true, installType: 'normal', permissions: [] },
  { id: 'self', name: 'Cool Head for Chrome', type: 'extension', enabled: true, mayDisable: true, installType: 'development', permissions: [] },
];

test('the safe list starts with organization, password, blocker, VPN, and security extensions always on', () => {
  assert.deepEqual(EXTS.map(kindOf), ['password', 'blocker', 'vpn', 'admin', 'other', 'other', 'other', 'other']);
  assert.equal(kindOf({ name: 'Compass helper', permissions: [] }), 'other');
  const cols = columns(EXTS, null, 'self');
  assert.deepEqual(cols.alwaysOn.map((e) => e.id).sort(), ['org', 'pw', 'ub', 'vpn']);
  assert.deepEqual(cols.rest.map((e) => e.id).sort(), ['grammar', 'off']);
});

test('resting turns off only extensions that are on, not on the safe list, and not this one or a theme', () => {
  assert.deepEqual(restPlan(EXTS, null, 'self'), ['grammar']);
});

test('the person can move any extension, except one their organization installed', () => {
  let safe = move(null, 'pw', false);
  safe = move(safe, 'grammar', true);
  safe = move(safe, 'org', false);
  assert.deepEqual(restPlan(EXTS, safe, 'self').sort(), ['pw']);
  assert.equal(isAlwaysOn(EXTS[3], safe), true);
});

test('rested extensions wake only when no reason to rest is left', () => {
  assert.equal(shouldWake({ ids: ['a'], session: true, memory: false }), false);
  assert.equal(shouldWake({ ids: ['a'], session: false, memory: true }), false);
  assert.equal(shouldWake({ ids: ['a'], session: false, memory: false }), true);
  assert.equal(shouldWake({ ids: [], session: false, memory: false }), false);
});

test('an extension with its own tabs open is never paused, since Chrome would close those tabs', async () => {
  const { withOpenTabs } = await import('../src/logic/extensions.js');
  const napper = 'abcdefghijklmnopabcdefghijklmnop';
  const exts = [...EXTS, { id: napper, name: 'Tab napper', type: 'extension', enabled: true, mayDisable: true, installType: 'normal', permissions: [] }];
  const open = withOpenTabs([{ url: `chrome-extension://${napper}/suspended.html#uri=https://example.com` }, { url: 'https://example.com' }, { url: '' }]);
  assert.deepEqual([...open], [napper]);
  assert.deepEqual(restPlan(exts, null, 'self', open), ['grammar']);
  assert.deepEqual(restPlan(exts, null, 'self').sort(), [napper, 'grammar'].sort());
  assert.equal(columns(exts, null, 'self', open).rest.find((e) => e.id === napper).open, true);
});

test('the shortcut shows the tab used before the one put to sleep, or else its neighbor, in the same window', async () => {
  const { tabToShowInstead } = await import('../src/logic/usage.js');
  const tabs = [
    { id: 1, windowId: 1, index: 0 }, { id: 2, windowId: 1, index: 1 }, { id: 3, windowId: 1, index: 2 },
    { id: 9, windowId: 2, index: 0 },
  ];
  assert.equal(tabToShowInstead(tabs, 2, { 1: { last: 100, left: 200, switches: [] }, 3: { last: 50, left: 60, switches: [] }, 9: { last: 900, left: 950, switches: [] } }), 1);
  assert.equal(tabToShowInstead(tabs, 2, {}), 3);
  assert.equal(tabToShowInstead(tabs, 3, {}), 2);
  assert.equal(tabToShowInstead(tabs, 9, {}), null);
});

test('a suspended tab gives up its real address, whichever way the suspender writes it', async () => {
  const { suspendedAt, migrationPlan, suspenders } = await import('../src/logic/migrate.js');
  const id = 'noogafoofpebimajpfpamcfhoaifemoa';
  // The Great Suspender's family: the address last, unencoded, with its own query and hash
  assert.deepEqual(suspendedAt(`chrome-extension://${id}/suspended.html#ttl=Inbox&pos=0&uri=https://mail.example.com/a?b=1&c=2#inbox`, 'self'),
    { extId: id, url: 'https://mail.example.com/a?b=1&c=2#inbox' });
  // an encoded address in the query, followed by other values
  assert.equal(suspendedAt(`chrome-extension://${id}/park.html?title=Docs&url=https%3A%2F%2Fdocs.example.com%2Fd%3Fx%3D1&tabId=4`, 'self').url, 'https://docs.example.com/d?x=1');
  // not suspended: this extension's own page, a web page, an extension page with no address
  assert.equal(suspendedAt(`chrome-extension://${id}/options.html`, 'self'), null);
  assert.equal(suspendedAt(`chrome-extension://${id}/suspended.html#uri=https://a.example`, id), null);
  assert.equal(suspendedAt('https://example.com/?url=https://b.example', 'self'), null);
  assert.equal(suspendedAt(`chrome-extension://${id}/x.html?url=javascript%3Aalert(1)`, 'self'), null);
  const other = 'abcdefghijklmnopabcdefghijklmnop';
  const plan = migrationPlan([
    { id: 1, url: `chrome-extension://${id}/suspended.html#uri=https://a.example` },
    { id: 2, url: 'https://b.example' },
    { id: 3, url: `chrome-extension://${other}/p.html?url=https%3A%2F%2Fc.example`, active: true },
    { id: 4, url: `chrome-extension://${id}/suspended.html#uri=https://d.example` },
  ], 'self');
  assert.deepEqual(plan.map((p) => p.tabId), [1, 3, 4]);
  assert.deepEqual(suspenders(plan), [id, other]);
});

test('a site kept awake holds every tab from it and its subdomains, and reports to Cool Head as kept', async () => {
  const { heldReasons, siteOf, siteRuleFor, heldCounts } = await import('../src/logic/reasons.js');
  assert.equal(siteOf('https://www.Example.com/a'), 'example.com');
  assert.equal(siteOf('chrome://settings'), null);
  assert.equal(siteRuleFor('https://mail.example.com/x', ['example.com']), 'example.com');
  assert.equal(siteRuleFor('https://notexample.com/', ['example.com']), null);
  const ctx = { now: 0, keepSites: ['example.com'] };
  assert.deepEqual(heldReasons({ id: 1, url: 'https://docs.example.com/d' }, ctx), ['site']);
  assert.deepEqual(heldReasons({ id: 2, url: 'https://other.org/' }, ctx), []);
  assert.equal(heldCounts([{ id: 1, url: 'https://example.com/' }], ctx).kept, 1);
});

test('the most used suspenders each give up the real address (shapes from their source, read 22 November 2026)', async () => {
  const { suspendedAt } = await import('../src/logic/migrate.js');
  // Tab Suspender: park.html, every value encoded, the address third
  assert.equal(suspendedAt('chrome-extension://fiabciakcmgepblmdkmemdbbkilneeeh/park.html?tabId=412&title=Example%20Page&url=https%3A%2F%2Fexample.com%2Fdocs%3Fa%3D1%26b%3D2&sessionId=1732280000000&icon=https%3A%2F%2Fexample.com%2Ffavicon.ico#secondTime', 'self').url,
    'https://example.com/docs?a=1&b=2');
  // The Marvellous Suspender: suspended.html, the address last and unencoded, including a local file
  assert.equal(suspendedAt('chrome-extension://noogafoofpebimajpfpamcfhoaifemoa/suspended.html#ttl=Example%20Page&pos=0&uri=https://example.com/docs?a=1&b=2#section', 'self').url,
    'https://example.com/docs?a=1&b=2#section');
  assert.equal(suspendedAt('chrome-extension://noogafoofpebimajpfpamcfhoaifemoa/suspended.html#ttl=Notes&pos=0&uri=file:///Users/someone/notes.html', 'self').url,
    'file:///Users/someone/notes.html');
  // The Great Suspender 2026: The Marvellous Suspender's shape, under html/
  assert.equal(suspendedAt('chrome-extension://hlofigcdgjlnalbkeeinfcjceabpamci/html/suspended.html#ttl=Alpha%20page&pos=0&uri=http://127.0.0.1:8765/a.html?x=1&y=2#part', 'self').url,
    'http://127.0.0.1:8765/a.html?x=1&y=2#part');
  // tabssuspender.com: suspended.html, title first, the address encoded; about:blank isn't a page to move
  assert.equal(suspendedAt('chrome-extension://laameccjpleogmfhilmffpdbiibgbekf/suspended.html?title=Bravo%20%26%20co&url=http%3A%2F%2F127.0.0.1%3A8765%2Fb.html%3Fq%3Dhello%2520world&time=1795366555013', 'self').url,
    'http://127.0.0.1:8765/b.html?q=hello%20world');
  assert.equal(suspendedAt('chrome-extension://laameccjpleogmfhilmffpdbiibgbekf/suspended.html?title=about%3Ablank&url=about%3Ablank&time=1', 'self'), null);
  // Workona: a web page of its own, the address encoded after #
  assert.deepEqual(suspendedAt('https://workona.com/suspended/#title=Alpha%20page&url=https%3A%2F%2Fexample.com%2Fa%3Fx%3D1%26y%3D2&favIconUrl=https%3A%2F%2Fexample.com%2Ff.ico', 'self'),
    { extId: 'kkahjkjjcepelnnikconblkonolboiok', url: 'https://example.com/a?x=1&y=2' });
  assert.equal(suspendedAt('https://workona.com/pricing?url=https%3A%2F%2Fexample.com', 'self'), null);
  // Tiny Suspender: suspend.html, the address first and encoded, with favIconUrl after it
  assert.equal(suspendedAt('chrome-extension://bbomjaikkcabgmfaomdichgcodnaeecf/suspend.html?url=https%3A%2F%2Fexample.com%2Fdocs%3Fa%3D1%26b%3D2&title=Example%20Page&favIconUrl=https%3A%2F%2Fexample.com%2Ffavicon.ico&scroll_x=0&scroll_y=640', 'self').url,
    'https://example.com/docs?a=1&b=2');
});
