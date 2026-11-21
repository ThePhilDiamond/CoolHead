import { test } from 'node:test';
import assert from 'node:assert/strict';
import { nextAuto, currentMemory, autoAllowed, AUTO_OFF, CLEAR_AFTER_MS, STALE_MS } from '../src/logic/auto.js';
import { NOW, MIN } from './helpers.js';

test('fine and tight start nothing; slowed and very tight do', () => {
  assert.equal(nextAuto(AUTO_OFF, 'fine', NOW).mode, 'off');
  assert.equal(nextAuto(AUTO_OFF, 'tight', NOW).mode, 'off');
  assert.equal(nextAuto(AUTO_OFF, 'slowed', NOW).mode, 'slowed');
  assert.equal(nextAuto(AUTO_OFF, 'veryTight', NOW).mode, 'veryTight');
});

test('tight holds what is running; very tight eases to slowed', () => {
  assert.equal(nextAuto({ mode: 'veryTight', fineSince: null }, 'tight', NOW).mode, 'veryTight');
  assert.equal(nextAuto({ mode: 'veryTight', fineSince: null }, 'slowed', NOW).mode, 'slowed');
});

test('backs off only after memory has been fine for 5 minutes', () => {
  let a = nextAuto({ mode: 'slowed', fineSince: null }, 'fine', NOW);
  assert.deepEqual(a, { mode: 'slowed', fineSince: NOW });
  a = nextAuto(a, 'fine', NOW + 4 * MIN);
  assert.equal(a.mode, 'slowed');
  // A tight reading in between starts the 5 minutes again.
  const interrupted = nextAuto(nextAuto(a, 'tight', NOW + 4.5 * MIN), 'fine', NOW + 5 * MIN);
  assert.equal(interrupted.fineSince, NOW + 5 * MIN);
  assert.equal(nextAuto(a, 'fine', NOW + CLEAR_AFTER_MS).mode, 'off');
});

test('no reading, or a reading that makes no sense, turns Auto off', () => {
  assert.deepEqual(nextAuto({ mode: 'veryTight', fineSince: null }, null, NOW), AUTO_OFF);
  assert.deepEqual(nextAuto({ mode: 'veryTight', fineSince: null }, 'boiling', NOW), AUTO_OFF);
});

test('a reading counts only while linked and for 35 seconds', () => {
  const link = { status: 'linked', state: { memory: 'slowed', auto: true }, stateAt: NOW };
  assert.equal(currentMemory(link, NOW + 10000), 'slowed');
  assert.equal(currentMemory(link, NOW + STALE_MS + 1), null);
  assert.equal(currentMemory({ ...link, status: 'notRunning' }, NOW), null);
  assert.equal(currentMemory(null, NOW), null);
});

test('Auto is not allowed when Cool Head says the person turned it off', () => {
  const link = { status: 'linked', state: { memory: 'slowed', auto: false }, stateAt: NOW };
  assert.equal(autoAllowed(link, NOW), false);
  assert.equal(autoAllowed({ ...link, state: { memory: 'slowed', auto: true } }, NOW), true);
});
