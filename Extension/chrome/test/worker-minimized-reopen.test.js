// Saved windows' Reopen sleeps its tabs as they load. A tab clicked while loading, in a window then minimized, is
// slept as the minimized window's front tab; when the window is back it's woken, not left blank.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { install, loadWorker } from './fake-chrome.mjs';

test('a reopened window\'s tab slept while it was minimized is woken when the window is back', async () => {
  const W = install({ inPlace: true });
  W.win(1, 'normal', true);
  W.tab({ windowId: 1, active: true });
  chrome.bookmarks.getSubTree = async () => [{ id: 'f1', children: [{ url: 'https://one.example/', title: 'One' }, { url: 'https://two.example/', title: 'Two' }, { url: 'https://three.example/', title: 'Three' }] }];
  chrome.bookmarks.removeTree = async () => {};
  chrome.windows.create = async ({ url }) => {
    W.win(3, 'normal', false); W.setWin(3, { focused: true }); W.setWin(1, { focused: false });
    W.tab({ windowId: 3, url, active: true, status: 'complete' });
    return await chrome.windows.get(3);
  };
  chrome.tabs.create = async ({ windowId, url, active }) => W.tab({ windowId, url, active: Boolean(active), status: 'loading' });
  const ch = await loadWorker(W);
  const done = ch.act({ action: 'reopenWindow', id: 'f1' });
  await W.settle();
  const [, two, three] = W.tabs().filter((t) => t.windowId === 3);
  await chrome.tabs.update(two.id, { active: true });
  W.fire('tabs.onActivated', { tabId: two.id, windowId: 3 }); await W.settle();
  W.setWin(3, { state: 'minimized', focused: false }); W.setWin(1, { focused: true });
  W.fire('windows.onFocusChanged', 1); await W.settle();
  for (const t of [two, three]) { W.byId(t.id).status = 'complete'; W.fire('tabs.onUpdated', t.id, { status: 'complete' }, structuredClone(W.byId(t.id))); }
  await W.settle(200);
  await done;
  W.setWin(3, { state: 'normal', focused: true });
  W.fire('windows.onFocusChanged', 3); await W.settle();
  await W.advance(3500);
  if (W.byId(two.id).discarded) assert.fail('Two is still blank in a window on screen');
  assert.ok(W.calls.reload.some((r) => r.id === two.id) || !W.calls.discard.includes(two.id));
});
