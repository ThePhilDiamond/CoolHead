// The sleeping tab's title mark (src/logic/mark.js): what it adds, what it takes off, and that every tab the worker
// reads comes with the page's own title.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { SLEEP_MARK, realTitle, withRealTitle, markInPage, unmarkInPage } from '../src/logic/mark.js';

test('the mark is plain letters and an en space, so Chrome draws it in the tab text color', () => {
  assert.equal(SLEEP_MARK, 'zzZ ');
  // no emoji or symbol: every character is a letter or a space
  assert.ok([...SLEEP_MARK].every((c) => /\p{L}|\p{Zs}/u.test(c)));
});

test('the real title comes back without the mark, and only Cool Head\'s mark is taken off', () => {
  assert.equal(realTitle(`${SLEEP_MARK}Inbox (3)`), 'Inbox (3)');
  assert.equal(realTitle('Inbox (3)'), 'Inbox (3)');
  // a page's own title that starts the same way with an ordinary space keeps its words
  assert.equal(realTitle('zzZ sleep tracker'), 'zzZ sleep tracker');
  assert.equal(realTitle(`${SLEEP_MARK}`), '');
  assert.equal(realTitle(undefined), undefined);
  assert.equal(realTitle(''), '');
});

test('a tab keeps everything but the mark, and an unmarked tab is the same object', () => {
  const t = { id: 4, title: `${SLEEP_MARK}Spring budget`, url: 'https://example.com/b', discarded: true };
  const r = withRealTitle(t);
  assert.deepEqual(r, { ...t, title: 'Spring budget' });
  assert.equal(t.title, `${SLEEP_MARK}Spring budget`, 'the tab Chrome gave is left as it was');
  const plain = { id: 5, title: 'Recipe ideas' };
  assert.equal(withRealTitle(plain), plain);
  assert.equal(withRealTitle(null), null);
  assert.deepEqual(withRealTitle({ id: 6 }), { id: 6 });
});

// The two functions Chrome runs in the page, with a made-up page.
function page(title, hostname = 'mail.example.com') {
  globalThis.document = { title };
  globalThis.location = { hostname };
}

test('marking a page puts the mark before its title once, and unmarking takes it off', () => {
  page('Inbox (3)');
  assert.equal(markInPage(SLEEP_MARK), true);
  assert.equal(document.title, `${SLEEP_MARK}Inbox (3)`);
  assert.equal(markInPage(SLEEP_MARK), true);
  assert.equal(document.title, `${SLEEP_MARK}Inbox (3)`, 'never marked twice');
  assert.equal(unmarkInPage(SLEEP_MARK), true);
  assert.equal(document.title, 'Inbox (3)');
  assert.equal(unmarkInPage(SLEEP_MARK), true);
  assert.equal(document.title, 'Inbox (3)', 'unmarking an unmarked page changes nothing');
});

test('a page without a title of its own is marked before what Chrome showed for it', () => {
  // a PDF's own title, or a text file's address, is what Chrome shows
  page('');
  markInPage(SLEEP_MARK, 'Quarterly report');
  assert.equal(document.title, `${SLEEP_MARK}Quarterly report`);
  // and with nothing shown at all, the site's name
  page('');
  markInPage(SLEEP_MARK, '');
  assert.equal(document.title, `${SLEEP_MARK}mail.example.com`);
  // a page's own title comes first
  page('Inbox');
  markInPage(SLEEP_MARK, 'mail.example.com/inbox');
  assert.equal(document.title, `${SLEEP_MARK}Inbox`);
});

test('Chrome runs each page function on its own, so neither uses anything from outside itself', () => {
  for (const f of [markInPage, unmarkInPage]) {
    const body = f.toString();
    assert.doesNotMatch(body, /SLEEP_MARK|realTitle|withRealTitle|import/, `${f.name} stands alone`);
  }
});

// The worker reads tabs in many places; each must get the page's own title, or the mark would reach a bookmark,
// a list in the popup, or a kept tab's record.
const worker = fs.readFileSync(new URL('../src/worker.js', import.meta.url), 'utf8');

test('every tab the worker reads comes through tabsNow or tabNow, which take the mark off', () => {
  const raw = worker.split('\n').filter((l) => /chrome\.tabs\.(query|get)\(/.test(l)).map((l) => l.trim());
  assert.deepEqual(raw, [
    'function tabsNow(query) { return chrome.tabs.query(query).then((tabs) => tabs.map(withRealTitle)); }',
    'function tabNow(tabId) { return chrome.tabs.get(tabId).then(withRealTitle); }',
    // the start-up check looks for the mark itself, on awake tabs
    'const awake = await chrome.tabs.query({ discarded: false });',
  ]);
});

test('each time the worker starts, a mark left on an awake tab comes off', () => {
  assert.match(worker, /\nunmarkAwake\(\)\.catch\(oops\);\n/);
});

test('tabs that arrive another way are cleaned too: a window\'s tabs and each tab update', () => {
  assert.match(worker, /populate: true[\s\S]{0,200}\(win\.tabs \|\| \[\]\)\.map\(withRealTitle\)/);
  assert.match(worker, /chrome\.tabs\.onUpdated\.addListener\(\(tabId, change, tab\) => \{\n {2}tab = withRealTitle\(tab\);/);
  // no other place hands the worker whole windows of tabs
  assert.equal((worker.match(/populate: true/g) || []).length, 1);
});
