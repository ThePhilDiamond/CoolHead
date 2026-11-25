// Minimized windows: their front tabs may sleep by the same rules as any tab out of sight (tests T20 to T23).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { inFront, noteWindows, onRestore, restorePlan } from '../src/logic/minimized.js';
import { canSleepOnItsOwn, planSleep, planSleepHidden } from '../src/logic/plan.js';
import { startPlan } from '../src/logic/session.js';
import { explainCheck } from '../src/logic/explain.js';
import { buildStart } from '../src/logic/view.js';
import { LOCAL_DEFAULTS, SESSION_DEFAULTS } from '../src/store.js';
import { tab, ctx, used, NOW, MIN } from './helpers.js';

const minimized = (...ids) => new Set(ids);

test('the tab in front of a minimized window is not in front; one in a window on screen is, focused or not', () => {
  const c = ctx({ minimized: minimized(2) });
  assert.equal(inFront(tab({ active: true, windowId: 1 }), c), true);
  assert.equal(inFront(tab({ active: true, windowId: 3 }), c), true);           // on screen, not focused
  assert.equal(inFront(tab({ active: true, windowId: 2 }), c), false);
  assert.equal(inFront(tab({ active: false, windowId: 1 }), c), false);
  assert.equal(inFront(tab({ active: true, windowId: 2 }), ctx()), true);         // no windows known: in front
});

test('a minimized window\'s front tab may sleep, but still not when something holds it', () => {
  const front = tab({ active: true, windowId: 2 });
  const c = ctx({ minimized: minimized(2) });
  assert.equal(canSleepOnItsOwn(front, c), true);
  assert.equal(canSleepOnItsOwn(tab({ active: true, windowId: 2, audible: true }), c), false);
  assert.equal(canSleepOnItsOwn(front, { ...c, typing: { [front.id]: true } }), false);
  assert.equal(canSleepOnItsOwn(front, { ...c, kept: new Set([front.id]) }), false);
  assert.equal(canSleepOnItsOwn(tab({ active: true, windowId: 3 }), c), false);   // a window on screen
});

test('it sleeps once it has been out of sight long enough, like any tab left', () => {
  const inUse = tab({ active: true, windowId: 1 });
  const front = tab({ active: true, windowId: 2 });
  const fresh = tab({ active: true, windowId: 4 });
  const c = ctx({
    level: 'focus', frontTabId: inUse.id, minimized: minimized(2, 4),
    use: { [inUse.id]: used(0), [front.id]: used(40), [fresh.id]: { last: NOW - 60 * MIN, left: NOW - 10000, switches: [] } },
  });
  assert.deepEqual(planSleep([inUse, front, fresh], c), [front.id]);
  assert.deepEqual(planSleepHidden([inUse, front, fresh], c), [front.id, fresh.id]);
  const auto = { ...c, level: 'auto', autoMode: 'slowed', autoAllowed: true };
  assert.deepEqual(planSleep([inUse, front, fresh], auto), [front.id]);
});

test('minimizing counts as leaving the front tab; bringing the window back, as using it again', () => {
  const w = [{ id: 1, state: 'normal' }, { id: 2, state: 'minimized' }];
  const fronts = { 1: 11, 2: 22 };
  const first = noteWindows(w, fronts, {}, { 22: { last: NOW - 60 * MIN, left: null, switches: [] } }, NOW);
  assert.deepEqual(first.minimizedAt, { 2: NOW });
  assert.equal(first.use[22].left, NOW);
  assert.equal(first.use[22].last, NOW - 60 * MIN);
  assert.equal(first.use[11], undefined);
  assert.equal(noteWindows(w, fronts, first.minimizedAt, first.use, NOW + MIN), null);   // nothing new
  const back = noteWindows([{ id: 1, state: 'normal' }, { id: 2, state: 'normal' }], fronts, first.minimizedAt, first.use, NOW + 5 * MIN);
  assert.deepEqual(back.minimizedAt, {});
  assert.equal(back.use[22].last, NOW + 5 * MIN);
  const closed = noteWindows([{ id: 1, state: 'normal' }], fronts, first.minimizedAt, first.use, NOW + MIN);
  assert.deepEqual(closed.minimizedAt, {});
  const noFront = noteWindows([{ id: 5, state: 'minimized' }], {}, {}, {}, NOW);
  assert.deepEqual(noFront, { minimizedAt: { 5: NOW }, use: {} });
});

test('a front tab slept in place is reloaded when its window comes back; one slept the older way is checked', () => {
  const f = { 7: { inPlace: true }, 8: { inPlace: false } };
  assert.equal(onRestore(f, 7), 'reload');
  assert.equal(onRestore(f, 8), 'check');
  assert.equal(onRestore(f, 9), null);
  assert.equal(onRestore(undefined, 7), null);
});

test('Start a session and the check count it as any tab out of sight, not as a tab in front', () => {
  const inUse = tab({ active: true, windowId: 1 });
  const front = tab({ active: true, windowId: 2 });
  const other = tab({ active: true, windowId: 3 });
  const c = ctx({ frontTabId: inUse.id, minimized: minimized(2) });
  const p = startPlan([inUse, front, other], [inUse.id], c);
  assert.deepEqual(p.sleep, [front.id]);
  assert.deepEqual(p.stayLoaded, [{ id: other.id, reason: 'active' }]);
  assert.equal(explainCheck([inUse, front, other], c).front, 2);
  const s = { ...structuredClone(LOCAL_DEFAULTS), ...structuredClone(SESSION_DEFAULTS) };
  const st = buildStart({ tabs: [inUse, front, other], s, now: NOW, focusedWindowId: 1, minimizedIds: [2] });
  const by = Object.fromEntries(st.rows.map((r) => [r.id, r]));
  assert.equal(by[front.id].ifUnticked, 'sleep');
  assert.equal(by[other.id].ifUnticked, 'active');
});

test('held awake in a minimized window, the front tab gives its real reason, not "in front"', () => {
  const inUse = tab({ active: true, windowId: 1 });
  const music = tab({ active: true, windowId: 2, audible: true });
  const c = ctx({ frontTabId: inUse.id, minimized: minimized(2) });
  assert.deepEqual(startPlan([inUse, music], [inUse.id], c).stayLoaded, [{ id: music.id, reason: 'sound' }]);
  const s = { ...structuredClone(LOCAL_DEFAULTS), ...structuredClone(SESSION_DEFAULTS) };
  const st = buildStart({ tabs: [inUse, music], s, now: NOW, focusedWindowId: 1, minimizedIds: [2] });
  assert.equal(st.rows.find((r) => r.id === music.id).ifUnticked, 'sound');
});

test('a window back: a blank front tab is woken, at once if slept in place, and a loaded one never', () => {
  const win = (id, state, front) => ({ id, state, front });
  const blank = (id) => ({ id, status: 'unloaded', discarded: false });
  const loaded = (id) => ({ id, status: 'complete', discarded: false });
  const records = { 7: { inPlace: true }, 8: { inPlace: false }, 9: { inPlace: true }, 10: { inPlace: true } };
  const p = restorePlan([win(1, 'normal', blank(7)), win(2, 'normal', blank(8)), win(3, 'normal', loaded(9)),
    win(4, 'minimized', blank(10)), win(5, 'normal', blank(11)), win(6, 'normal', undefined)], records);
  assert.deepEqual(p.wake, [{ id: 7, what: 'reload' }, { id: 8, what: 'check' }, { id: 11, what: 'check' }]);
  assert.deepEqual(p.frontAsleep, { 10: { inPlace: true } }, 'records of windows back are used up; a minimized one keeps its');
  assert.deepEqual(restorePlan([win(1, 'normal', loaded(1))], {}), { wake: [] }, 'nothing to change');
  assert.deepEqual(restorePlan([win(1, 'normal', { id: 3, status: 'complete', discarded: true })], {}).wake, [{ id: 3, what: 'check' }]);
});

// The worker's part, read from its source: it can't run outside Chrome.
const worker = fs.readFileSync(new URL('../src/worker.js', import.meta.url), 'utf8');

test('the worker sleeps a tab in front only when its window is minimized, checked just before', () => {
  assert.match(worker, /if \(front && !\(await isMinimized\(t\.windowId\)\)\) return \{ why: 'it came to the front', t \};/);
  assert.match(worker, /const onScreen = now && now\.active && !\(await isMinimized\(now\.windowId\)\);/);
  // the shown parameter (a title for the mark) must not be shadowed: a second "shown" broke every sleep in the live check
  assert.equal((worker.slice(worker.indexOf('async function sleepTab('), worker.indexOf('async function sleepMany(')).match(/const shown\b/g) || []).length, 0);
});

test('noting windows never schedules a check by itself, so a check doesn\'t schedule the next forever', () => {
  const body = worker.slice(worker.indexOf('async function windowsChanged()'), worker.indexOf('\n}\n', worker.indexOf('async function windowsChanged()')));
  assert.ok(body.length > 0);
  assert.doesNotMatch(body, /sweepSoon/);
  assert.match(worker, /async function sweep\(\) \{\n {2}await windowsChanged\(\);/);
});
