// The worker against a fake Chrome unloading the older way (the tab gets a new ID): Chrome reloads such a tab itself
// when its window is back, so the worker only checks after 3 seconds and reloads it if it's still blank.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { install, loadWorker } from './fake-chrome.mjs';

test('slept the older way, a front tab still blank 3 seconds after its window is back is reloaded once', async () => {
  const W = install({ inPlace: false });
  W.local.level = 'focus'; W.local.levelChosen = true;
  W.win(1, 'normal', true); W.win(2, 'normal', false);
  W.tab({ windowId: 1, active: true });
  W.tab({ windowId: 2, active: true });
  await loadWorker(W);
  // a reload that takes a moment to start, as Chrome's does: two checks at once would each see the tab still blank
  chrome.tabs.reload = async (id) => { W.calls.reload.push({ id, at: W.clock() }); };
  W.setWin(2, { state: 'minimized', focused: false }); W.setWin(1, { focused: true });
  W.fire('windows.onFocusChanged', 1); await W.settle();
  await W.advance(31000);
  const X = W.tabs().find((t) => t.windowId === 2);
  assert.equal(X.discarded, true);
  assert.deepEqual(W.session.frontAsleep, { [X.id]: { inPlace: false } }, 'noted under its new ID');
  W.setWin(2, { state: 'normal', focused: true });
  W.fire('windows.onFocusChanged', 2); W.fire('windows.onBoundsChanged', { id: 2 }); await W.settle();
  await W.advance(1000);
  assert.equal(W.calls.reload.length, 0, 'not at once: Chrome may reload it itself');
  await W.advance(2500);
  assert.deepEqual(W.calls.reload.map((r) => r.id), [X.id], 'reloaded once after the check, despite two events');
});
