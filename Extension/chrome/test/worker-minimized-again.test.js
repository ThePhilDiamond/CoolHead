// A window brought back and minimized again before the 3-second check: its front tab isn't loaded out of sight.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { install, loadWorker } from './fake-chrome.mjs';

test('the check doesn\'t reload a front tab whose window was minimized again', async () => {
  const W = install({ inPlace: false });
  W.local.level = 'focus'; W.local.levelChosen = true;
  W.win(1, 'normal', true); W.win(2, 'normal', false);
  W.tab({ windowId: 1, active: true });
  W.tab({ windowId: 2, active: true });
  await loadWorker(W);
  W.setWin(2, { state: 'minimized', focused: false }); W.setWin(1, { focused: true });
  W.fire('windows.onFocusChanged', 1); await W.settle();
  await W.advance(31000);
  W.setWin(2, { state: 'normal', focused: true });
  W.fire('windows.onFocusChanged', 2); await W.settle();
  await W.advance(1000);
  W.setWin(2, { state: 'minimized', focused: false }); W.setWin(1, { focused: true });
  W.fire('windows.onFocusChanged', 1); await W.settle();
  await W.advance(3500);
  assert.equal(W.calls.reload.length, 0);
});
