// Slept the older way, a front tab Chrome reloads itself when its window is back is never reloaded again by the worker.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { install, loadWorker } from './fake-chrome.mjs';

test('a front tab Chrome reloaded itself is left alone by the check', async () => {
  const W = install({ inPlace: false });
  W.local.level = 'focus'; W.local.levelChosen = true;
  W.win(1, 'normal', true); W.win(2, 'normal', false);
  W.tab({ windowId: 1, active: true });
  W.tab({ windowId: 2, active: true });
  await loadWorker(W);
  W.setWin(2, { state: 'minimized', focused: false }); W.setWin(1, { focused: true });
  W.fire('windows.onFocusChanged', 1); await W.settle();
  await W.advance(31000);
  const X = W.tabs().find((t) => t.windowId === 2);
  W.setWin(2, { state: 'normal', focused: true });
  W.fire('windows.onFocusChanged', 2); await W.settle();
  X.status = 'loading'; X.discarded = false;
  await W.advance(600);
  X.status = 'complete';
  await W.advance(3500);
  assert.equal(W.calls.reload.length, 0);
});
