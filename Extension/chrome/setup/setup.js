// Opened once, when the extension is installed. The all-sites permission is asked here, with the cost of saying
// no, and never assumed (decided 21 November 2026: "an optional host permission for all sites, asked at setup
// with the cost of saying no").
import { h } from '../popup/render.js';
import * as W from '../src/logic/words.js';

const page = document.getElementById('page');
const ALL_SITES = { origins: ['<all_urls>'] };

function done(text) {
  const p = h('p', { role: 'status', class: 'lede strong', text });
  const actions = document.getElementById('actions');
  actions.replaceWith(h('div', {}, p, h('p', { class: 'note', text: W.SETUP_NEXT })));
}

async function answer(yes) {
  let granted = false;
  if (yes) granted = await chrome.permissions.request(ALL_SITES).catch(() => false);
  await chrome.runtime.sendMessage({ type: 'act', action: 'sites', on: granted }).catch(() => {});
  done(yes ? (granted ? W.SETUP_DONE_YES : W.SETUP_REFUSED) : W.SETUP_DONE_NO);
}

page.append(
  h('img', { class: 'logo', src: '../icons/icon128.png', alt: '' }),
  h('h1', { id: 'title', text: W.SETUP_TITLE }),
  h('p', { class: 'lede strong', text: W.SETUP_LEDE }),
  h('section', { class: 'card', 'aria-labelledby': 'ask' },
    h('h2', { id: 'ask', text: W.SETUP_ASK }),
    h('p', { text: W.SETUP_WHY }),
    h('p', { class: 'note', text: W.SITES_HOW }),
    h('p', { class: 'note', text: W.SETUP_NO_COST }),
    h('div', { class: 'row', id: 'actions' },
      h('button', { class: 'btn primary', onclick: () => answer(true) }, W.SETUP_YES),
      h('button', { class: 'btn tall', onclick: () => answer(false) }, W.SETUP_NO))),
);

chrome.permissions.contains(ALL_SITES).then((granted) => { if (granted) done(W.SETUP_DONE_YES); });
