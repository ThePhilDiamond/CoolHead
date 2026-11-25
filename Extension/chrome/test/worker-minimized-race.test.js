// The window comes back while the worker is still sleeping later tabs in the same check (marking a busy page's title
// can take a second): the front tab it already slept is noted at once, so it's reloaded at once, not at the next check.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { install, loadWorker } from './fake-chrome.mjs';

test('a window back mid-check still has its front tab woken at once', async () => {
  const W = install({ inPlace: true });
  W.local.level = 'focus'; W.local.levelChosen = true;
  W.win(1, 'normal', true); W.win(2, 'normal', false);
  const T0 = W.clock();
  W.tab({ windowId: 1, active: true });
  const X = W.tab({ windowId: 2, active: true });
  const Y = W.tab({ windowId: 1, lastAccessed: T0 });        // due at the same check, after X
  W.slowScript.add(Y.id);                                     // its page is busy: marking takes the full second
  await loadWorker(W);
  W.setWin(2, { state: 'minimized', focused: false }); W.setWin(1, { focused: true });
  W.fire('windows.onFocusChanged', 1); await W.settle();
  await W.advance(30300);
  assert.equal(W.byId(X.id).discarded, true);
  assert.equal(W.byId(Y.id).discarded, false, 'Y still being marked');
  W.setWin(2, { state: 'normal', focused: true });
  W.fire('windows.onFocusChanged', 2); W.fire('windows.onBoundsChanged', { id: 2 }); await W.settle();
  await W.advance(1000);
  assert.deepEqual(W.calls.reload.map((r) => r.id), [X.id]);
});
