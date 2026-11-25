// A front tab the worker reloads because its window came back wasn't switched to by the person, so clicking another tab
// right after doesn't count as a quick glance and doesn't put it straight back to sleep.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { install, loadWorker } from './fake-chrome.mjs';

test('the worker\'s own wake-up isn\'t a glance', async () => {
  const W = install({ inPlace: true });
  W.local.level = 'focus'; W.local.levelChosen = true;
  W.win(1, 'normal', true); W.win(2, 'normal', false);
  const A = W.tab({ windowId: 1, active: true });
  const X = W.tab({ windowId: 2, active: true });
  const Z = W.tab({ windowId: 2 });
  await loadWorker(W);
  W.session.activeByWindow = { 1: A.id, 2: X.id };
  W.setWin(2, { state: 'minimized', focused: false }); W.setWin(1, { focused: true });
  W.fire('windows.onFocusChanged', 1); await W.settle();
  await W.advance(31000);
  assert.equal(W.byId(X.id).discarded, true);
  W.setWin(2, { state: 'normal', focused: true });
  W.fire('windows.onFocusChanged', 2); await W.settle();
  W.fire('tabs.onUpdated', X.id, { discarded: false }, structuredClone(W.byId(X.id))); await W.settle();
  assert.deepEqual(W.calls.reload.map((r) => r.id), [X.id]);
  await W.advance(2000);
  await chrome.tabs.update(Z.id, { active: true });
  W.fire('tabs.onActivated', { tabId: Z.id, windowId: 2 }); await W.settle(200);
  assert.equal(W.calls.discard.filter((i) => i === X.id).length, 1, 'slept once, not again');
});
