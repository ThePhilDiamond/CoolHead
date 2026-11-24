// Saved windows' pure rules (src/logic/windows.js): naming, what can be saved, and telling Cool Head's folders from
// anything else in its parent folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { dayText, savable, defaultWords, cleanWords, folderTitle, wordsOf, savedAgo, urlsIn, pagesIn, splitParent } from '../src/logic/windows.js';

const DAY = 86400000;
const AT = new Date(2026, 10, 24, 15, 30).getTime();

test('a folder is named from its words, how many tabs, and the day', () => {
  assert.equal(dayText(AT), '24 November 2026');
  assert.equal(folderTitle('Trip planning', 12, AT), 'Trip planning · 12 tabs · 24 November 2026');
  assert.equal(folderTitle('One thing', 1, AT), 'One thing · 1 tab · 24 November 2026');
  assert.equal(wordsOf('Trip planning · 12 tabs · 24 November 2026'), 'Trip planning');
  assert.equal(wordsOf('Renamed by hand'), 'Renamed by hand');
});

test('without words, the window\'s main site and how many others name it', () => {
  assert.equal(defaultWords(['https://mail.example.com/a', 'https://www.docs.example.com/b', 'https://mail.example.com/c']), 'mail.example.com and 1 more');
  assert.equal(defaultWords(['https://news.example.com/1']), 'news.example.com');
  assert.equal(defaultWords([]), 'Saved window');
  assert.equal(cleanWords('  Trip \n planning  '), 'Trip planning');
  assert.equal(cleanWords('x'.repeat(60)).length, 40);
});

test('only pages that open again from a bookmark are saved', () => {
  assert.equal(savable('https://example.com/'), true);
  assert.equal(savable('chrome://settings/'), true);
  assert.equal(savable('chrome://newtab/'), false);
  assert.equal(savable('about:blank'), false);
  assert.equal(savable(''), false);
  assert.equal(savable('javascript:alert(1)'), false);
});

test('how long ago a window was saved, in words', () => {
  assert.equal(savedAgo(AT, AT + 3600000), 'today');
  assert.equal(savedAgo(AT, AT + DAY + 1), 'yesterday');
  assert.equal(savedAgo(AT, AT + 3 * DAY), '3 days ago');
  assert.equal(savedAgo(AT, AT + 8 * DAY), 'a week ago');
  assert.equal(savedAgo(AT, AT + 21 * DAY), '3 weeks ago');
  assert.equal(savedAgo(AT, AT + 65 * DAY), '2 months ago');
});

test('Cool Head\'s folders are told from anything else in its folder, newest first, links inside folders counted', () => {
  const children = [
    { id: 'a', title: 'Older · 2 tabs · 1 November 2026', children: [{ id: 'a1', url: 'https://a/1' }, { id: 'a2', url: 'https://a/2' }] },
    { id: 'x', title: 'Recipe ideas', url: 'https://recipes.example.com' },
    { id: 'b', title: 'Newer · 1 tab · 20 November 2026', children: [{ id: 'b1', url: 'https://b/1' }, { id: 'b2', title: 'added', children: [{ id: 'b3', url: 'https://b/3' }] }] },
    { id: 'y', title: 'A folder the person made', children: [] },
  ];
  const { saved, others } = splitParent(children, [{ id: 'a', savedAt: AT - 20 * DAY }, { id: 'b', savedAt: AT - 4 * DAY }], AT);
  assert.deepEqual(saved.map((f) => [f.id, f.words, f.n, f.ago]), [['b', 'Newer', 2, '4 days ago'], ['a', 'Older', 2, '2 weeks ago']]);
  assert.deepEqual(others.map((o) => o.id), ['x', 'y']);
  assert.deepEqual(urlsIn(children[2]), ['https://b/1', 'https://b/3']);
  assert.deepEqual(pagesIn(children[2]).map((p) => p.url), urlsIn(children[2]), 'the same pages in the same order');
  assert.ok(pagesIn(children[2]).every((p) => typeof p.title === 'string'));
});
