// The worker's report to Cool Head says how many tabs "Sleep tabs you aren't looking at" would sleep now: out of sight
// and not held (pinned, sound, kept, typing), so Cool Head's card can say how many, never how much.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { install, loadWorker } from './fake-chrome.mjs';

test('the report counts the tabs that would sleep, leaving out the tab in front and held tabs', async () => {
  const W = install({ inPlace: true });
  W.local.level = 'auto'; W.local.levelChosen = true;
  W.win(1, 'normal', true);
  W.tab({ windowId: 1, active: true });                     // in front
  W.tab({ windowId: 1 });                                   // would sleep
  W.tab({ windowId: 1 });                                   // would sleep
  W.tab({ windowId: 1, pinned: true });                     // held: pinned
  W.tab({ windowId: 1, audible: true });                    // held: sound
  // a link to Cool Head: the host's port, recording what the extension sends
  const sent = [];
  const listeners = { message: [], disconnect: [] };
  const port = {
    onMessage: { addListener: (f) => listeners.message.push(f) },
    onDisconnect: { addListener: (f) => listeners.disconnect.push(f) },
    postMessage: (m) => sent.push(m),
    disconnect: () => {},
  };
  chrome.runtime.connectNative = () => port;
  await loadWorker(W);
  for (const f of listeners.message) f({ type: 'link', app: 'running' });
  await W.settle(200);
  W.fire('alarms.onAlarm', { name: 'tick' }); await W.settle(200);
  await W.advance(11000);
  const reports = sent.filter((m) => m.type === 'report');
  assert.ok(reports.length > 0, 'a report was sent');
  assert.equal(reports.at(-1).toSleep, 2);
});
