import { test } from 'node:test';
import assert from 'node:assert/strict';
import { planSleep, planSleepHidden, nextDueAt, canSleepOnItsOwn } from '../src/logic/plan.js';
import { tab, ctx, used, NOW, MIN } from './helpers.js';

test('never sleeps the tab in front, a non-web page, an asleep tab, or one Chrome protects', () => {
  const c = ctx();
  assert.equal(canSleepOnItsOwn(tab({ active: true }), c), false);
  assert.equal(canSleepOnItsOwn(tab({ url: 'chrome://settings/' }), c), false);
  assert.equal(canSleepOnItsOwn(tab({ discarded: true }), c), false);
  assert.equal(canSleepOnItsOwn(tab({ autoDiscardable: false }), c), false);
  assert.equal(canSleepOnItsOwn(tab(), c), true);
});

test('never sleeps a tab held for a reason: sound, recent sound, call, screen, typing, kept, pinned', () => {
  const t = [tab({ audible: true }), tab(), tab(), tab(), tab(), tab(), tab({ pinned: true }), tab({ url: 'https://meet.google.com/abc-defg-hij' })];
  const c = ctx({
    audibleAt: { [t[1].id]: NOW - 2 * MIN },
    media: { [t[2].id]: { call: true }, [t[3].id]: { screen: true } },
    typing: { [t[4].id]: true },
    kept: new Set([t[5].id]),
  });
  for (const x of t) assert.equal(canSleepOnItsOwn(x, c), false, x.id);
});

test('sound stops protecting a tab 10 minutes after it goes quiet', () => {
  const t = tab();
  assert.equal(canSleepOnItsOwn(t, ctx({ audibleAt: { [t.id]: NOW - 9 * MIN } })), false);
  assert.equal(canSleepOnItsOwn(t, ctx({ audibleAt: { [t.id]: NOW - 11 * MIN } })), true);
});

test('Balanced keeps the 3 most used loaded and sleeps the rest once the leave delay has passed', () => {
  const front = tab({ active: true });
  const a = tab(); const b = tab(); const c2 = tab(); const d = tab(); const e = tab();
  const use = {
    [front.id]: used(0, 9), [a.id]: used(1, 8), [b.id]: used(2, 5),
    [c2.id]: used(3, 1), [d.id]: used(20, 1), [e.id]: used(0.2, 1), // e left 12 seconds ago
  };
  const out = planSleep([front, a, b, c2, d, e], ctx({ level: 'balanced', use, frontTabId: front.id }));
  // front, a, b stay; d (20 min) and c2 (3 min) sleep, oldest first; e waits out its 30 seconds.
  assert.deepEqual(out, [d.id, c2.id]);
});

test('Light keeps 5, Focus keeps only the tab in front', () => {
  const front = tab({ active: true });
  const others = Array.from({ length: 6 }, () => tab());
  const use = Object.fromEntries(others.map((t, i) => [t.id, used(5 + i, 6 - i)]));
  use[front.id] = used(0, 1);
  const all = [front, ...others];
  assert.equal(planSleep(all, ctx({ level: 'light', use, frontTabId: front.id })).length, 2);
  assert.equal(planSleep(all, ctx({ level: 'focus', use, frontTabId: front.id })).length, 6);
});

test('with "At once", a tab sleeps as soon as it is left', () => {
  const front = tab({ active: true });
  const left = tab();
  const use = { [front.id]: used(0, 1), [left.id]: used(0.05, 1) }; // 3 seconds ago
  assert.deepEqual(planSleep([front, left], ctx({ level: 'focus', use, frontTabId: front.id, leaveDelayMs: 0 })), [left.id]);
  assert.deepEqual(planSleep([front, left], ctx({ level: 'focus', use, frontTabId: front.id, leaveDelayMs: 30000 })), []);
});

test('protected tabs do not take a place among the most used', () => {
  const front = tab({ active: true });
  const music = tab({ audible: true });
  const a = tab(); const b = tab(); const c2 = tab();
  const use = { [front.id]: used(0, 1), [music.id]: used(1, 20), [a.id]: used(2, 3), [b.id]: used(3, 2), [c2.id]: used(4, 1) };
  // Balanced: front, a, b stay; music stays anyway; only c2 sleeps.
  assert.deepEqual(planSleep([front, music, a, b, c2], ctx({ level: 'balanced', use, frontTabId: front.id })), [c2.id]);
});

test('a tab the extension has never seen falls back to Chrome\'s lastAccessed', () => {
  const front = tab({ active: true });
  const old = tab({ lastAccessed: NOW - 2 * MIN });
  const fresh = tab({ lastAccessed: NOW - 5000 });
  const out = planSleep([front, old, fresh], ctx({ level: 'focus', frontTabId: front.id }));
  assert.deepEqual(out, [old.id]);
});

test('Auto does nothing alone, nothing while memory is fine, and one tab at a time when slowed', () => {
  const tabs = [tab({ active: true }), tab({ lastAccessed: NOW - 40 * MIN }), tab({ lastAccessed: NOW - 50 * MIN }), tab({ lastAccessed: NOW - 10 * MIN })];
  // Alone: Auto needs Cool Head.
  assert.deepEqual(planSleep(tabs, ctx({ level: 'auto', autoAllowed: false, autoMode: 'slowed' })), []);
  // Together, memory fine.
  assert.deepEqual(planSleep(tabs, ctx({ level: 'auto', autoAllowed: true, autoMode: 'off' })), []);
  // Slowed: unused 30 minutes, oldest first, one at a time.
  assert.deepEqual(planSleep(tabs, ctx({ level: 'auto', autoAllowed: true, autoMode: 'slowed' })), [tabs[2].id]);
  // Very tight: 5 minutes, still one at a time, still the oldest.
  assert.deepEqual(planSleep(tabs, ctx({ level: 'auto', autoAllowed: true, autoMode: 'veryTight' })), [tabs[2].id]);
  // Very tight, after the two oldest are asleep, the 10-minute tab goes next.
  const rest = tabs.map((t, i) => (i === 1 || i === 2 ? { ...t, discarded: true } : t));
  assert.deepEqual(planSleep(rest, ctx({ level: 'auto', autoAllowed: true, autoMode: 'veryTight' })), [tabs[3].id]);
  assert.deepEqual(planSleep(rest, ctx({ level: 'auto', autoAllowed: true, autoMode: 'slowed' })), []);
});

test('during a session everything outside it sleeps, whatever the level, and session tabs never do', () => {
  const front = tab({ active: true });
  const inS = tab(); const out1 = tab(); const out2 = tab({ audible: true });
  const c = ctx({ level: 'auto', sessionIds: new Set([front.id, inS.id]), autoAllowed: false });
  assert.deepEqual(planSleep([front, inS, out1, out2], c), [out1.id]);
});

test('nextDueAt says when the next tab finishes its leave delay', () => {
  const front = tab({ active: true });
  const left = tab();
  const use = { [front.id]: used(0, 1), [left.id]: { last: NOW - 10000, left: NOW - 10000, switches: [] } };
  assert.equal(nextDueAt([front, left], ctx({ level: 'focus', use, frontTabId: front.id })), NOW + 20000);
  assert.equal(nextDueAt([front, left], ctx({ level: 'auto', use })), null);
});

test('Sleep tabs you aren\'t looking at keeps the protections and the keep list', () => {
  const front = tab({ active: true });
  const kept = tab(); const plain = tab(); const typing = tab();
  const c = ctx({ kept: new Set([kept.id]), typing: { [typing.id]: true } });
  assert.deepEqual(planSleepHidden([front, kept, plain, typing], c), [plain.id]);
});
