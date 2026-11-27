// Close duplicates, done, then next, through the real worker: what closed is read back from Chrome and saved with
// when, the popup's view shows it for a few seconds and then recommends the next card; if Chrome closes none, that
// stays until Done.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { install, loadWorker } from './fake-chrome.mjs';
import { RESULT_MS } from '../src/logic/view.js';

test('closed: the result shows, then goes after its few seconds, and the next card is recommended; a refusal stays until Done', async () => {
  const W = install({ inPlace: true });
  W.win(1, 'normal', true);
  W.tab({ windowId: 1, active: true });
  const keep = W.tab({ windowId: 1, url: 'https://docs.example/budget', title: 'Budget', lastAccessed: W.clock() - 60e3 });
  const copy = W.tab({ windowId: 1, url: 'https://docs.example/budget', title: 'Budget', lastAccessed: W.clock() - 3600e3 });
  const ch = await loadWorker(W);

  assert.equal((await ch.viewFor()).recommended.id, 'dups');
  const said = await ch.act({ action: 'closeDuplicates' });
  assert.match(said, /^Closed 1 duplicate tab\./);
  assert.equal(W.byId(copy.id), undefined);
  assert.ok(W.byId(keep.id));
  const during = await ch.viewFor();
  assert.deepEqual([during.closedDups.n, during.closedDups.failed, during.recommended.id], [1, false, 'dups']);

  await W.advance(RESULT_MS);
  const after = await ch.viewFor();
  assert.equal(after.closedDups, null);
  assert.equal(after.recommended.id, 'extrec');

  // Chrome refuses: nothing closes, and the card says so until Done, however long that is
  W.tab({ windowId: 1, url: 'https://docs.example/budget', title: 'Budget', lastAccessed: W.clock() - 7200e3 });
  chrome.tabs.remove = async () => { throw new Error('Tabs cannot be edited right now'); };
  assert.equal(await ch.act({ action: 'closeDuplicates' }), 'Chrome did not close the duplicates, so nothing changed.');
  // asked from Cool Head's card, the refusal is an answer that didn't work, so Cool Head keeps the option there
  const answer = await ch.answerLinkRequest({ action: 'closeDuplicates' });
  assert.deepEqual([answer.ok, answer.count, answer.done], [false, 0, 'Chrome did not close the duplicates, so nothing changed.']);
  await W.advance(60e3);
  const refused = await ch.viewFor();
  assert.equal(refused.closedDups.failed, true);
  assert.equal(refused.recommended.id, 'dups');
  await ch.act({ action: 'closedDupsSeen' });
  const read = await ch.viewFor();
  assert.equal(read.closedDups, null);
  assert.equal(read.duplicates.button, 'Close 1 duplicate');
});

test('a partial close says how many Chrome did not close, and still counts as done', async () => {
  const W = install({ inPlace: true });
  W.win(1, 'normal', true);
  W.tab({ windowId: 1, active: true });
  W.tab({ windowId: 1, url: 'https://docs.example/a', title: 'A', lastAccessed: W.clock() - 60e3 });
  const a2 = W.tab({ windowId: 1, url: 'https://docs.example/a', title: 'A', lastAccessed: W.clock() - 3600e3 });
  W.tab({ windowId: 1, url: 'https://docs.example/b', title: 'B', lastAccessed: W.clock() - 60e3 });
  const b2 = W.tab({ windowId: 1, url: 'https://docs.example/b', title: 'B', lastAccessed: W.clock() - 3600e3 });
  const ch = await loadWorker(W);
  // Chrome closes the first copy, then refuses the other
  const remove = chrome.tabs.remove;
  chrome.tabs.remove = async (ids) => { await remove([].concat(ids)[0]); throw new Error('Tabs cannot be edited right now'); };
  const answer = await ch.answerLinkRequest({ action: 'closeDuplicates' });
  assert.deepEqual([answer.ok, answer.count, answer.done], [true, 1, 'Closed 1 duplicate tab. Chrome did not close the other one.']);
  assert.equal([W.byId(a2.id), W.byId(b2.id)].filter(Boolean).length, 1);
});

