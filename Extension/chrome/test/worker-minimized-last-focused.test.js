// Chrome can report a minimized window as the one last focused (focus went to another program). Its front tab still
// isn't the tab in use, so it sleeps like any tab out of sight.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { install, loadWorker } from './fake-chrome.mjs';

test('the last-focused window minimized: its front tab isn\'t taken as the tab in use', async () => {
  const W = install({ inPlace: true });
  W.local.level = 'focus'; W.local.levelChosen = true;
  W.win(1, 'normal', false); W.win(2, 'normal', true);
  W.tab({ windowId: 1, active: true });
  const X = W.tab({ windowId: 2, active: true });
  await loadWorker(W);
  W.setWin(2, { state: 'minimized', focused: false });
  W.fire('windows.onFocusChanged', -1); await W.settle();
  await W.advance(2 * 60 * 1000);
  assert.equal(W.byId(X.id).discarded, true);
});
