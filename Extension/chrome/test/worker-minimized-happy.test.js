// The worker, run for real against a fake Chrome, with Chrome unloading in place (the tab keeps its ID): a minimized
// window's front tab sleeps after the leave delay, and is reloaded at once, and only once, when the window is back.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { install, loadWorker } from './fake-chrome.mjs';

test('a minimized window\'s front tab sleeps after the leave delay and is reloaded once when the window is back', async () => {
  const W = install({ inPlace: true });
  W.local.level = 'focus'; W.local.levelChosen = true;
  W.win(1, 'normal', true); W.win(2, 'normal', false);
  W.tab({ windowId: 1, active: true });
  const X = W.tab({ windowId: 2, active: true });
  await loadWorker(W);
  W.setWin(2, { state: 'minimized', focused: false }); W.setWin(1, { focused: true });
  W.fire('windows.onFocusChanged', 1); await W.settle();
  assert.ok(W.session.minimizedAt?.[2], 'the minimize is noted');
  await W.advance(10000);
  assert.equal(W.byId(X.id).discarded, false, 'not before the leave delay');
  await W.advance(21000);
  assert.equal(W.byId(X.id).discarded, true, 'asleep after the leave delay');
  assert.deepEqual(W.session.frontAsleep, { [X.id]: { inPlace: true } });
  W.setWin(2, { state: 'normal', focused: true });
  W.fire('windows.onFocusChanged', 2); await W.settle();
  assert.deepEqual(W.calls.reload.map((r) => r.id), [X.id], 'reloaded at once');
  await W.advance(3500);
  assert.equal(W.calls.reload.length, 1, 'and only once');
});
