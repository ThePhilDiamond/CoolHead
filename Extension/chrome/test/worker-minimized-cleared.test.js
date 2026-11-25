// The extension updated while a minimized window's front tab is asleep: session storage, and the record of sleeping
// it, are gone. The front tab is still blank in a window on screen, so it's woken all the same.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { install, loadWorker } from './fake-chrome.mjs';

test('a blank front tab with no record is still woken when its window is back', async () => {
  const W = install({ inPlace: true });
  W.local.level = 'focus'; W.local.levelChosen = true;
  W.win(1, 'normal', true); W.win(2, 'normal', false);
  W.tab({ windowId: 1, active: true });
  const X = W.tab({ windowId: 2, active: true });
  await loadWorker(W);
  W.setWin(2, { state: 'minimized', focused: false }); W.setWin(1, { focused: true });
  W.fire('windows.onFocusChanged', 1); await W.settle();
  await W.advance(31000);
  assert.equal(W.byId(X.id).discarded, true);
  for (const k of Object.keys(W.session)) delete W.session[k];
  W.setWin(2, { state: 'normal', focused: true });
  W.fire('windows.onFocusChanged', 2); await W.settle();
  await W.advance(3500);
  assert.deepEqual(W.calls.reload.map((r) => r.id), [X.id]);
});
