// Opened once, when the extension is installed. The all-sites permission is asked here, with the cost of saying
// no, and never assumed (decided 21 November 2026: "an optional host permission for all sites, asked at setup
// with the cost of saying no").
import { h } from '../popup/render.js';
import { icon } from '../popup/icons.js';
import * as W from '../src/logic/words.js';

const page = document.getElementById('page');
const ALL_SITES = { origins: ['<all_urls>'] };

// The answer, in a box with a check (or a warning when Chrome said no) in place of the buttons, so it's plain that the
// click worked; then what's next.
function done(title, text, ok) {
  const box = h('div', { class: ok ? 'confirm' : 'confirm off', role: 'status' },
    icon(ok ? 'check' : 'warn'),
    h('div', {}, h('b', { text: `${title}.` }), h('span', { text: ` ${text}` })));
  document.getElementById('asking')?.remove();
  const actions = document.getElementById('actions');
  actions.replaceWith(h('div', { id: 'actions' }, box,
    h('p', { class: 'note', text: `${W.SETUP_CLOSE} ${W.SETUP_NEXT}` })));
}

async function answer(yes) {
  let granted = false;
  if (yes) {
    // while Chrome's own question is open, the buttons wait and say where to look
    for (const b of document.querySelectorAll('#actions button')) b.disabled = true;
    const primary = document.querySelector('#actions .primary');
    primary.textContent = W.SETUP_ASKING;
    document.getElementById('actions').after(h('p', { class: 'note', id: 'asking', text: W.SETUP_ASKING_NOTE }));
    granted = await chrome.permissions.request(ALL_SITES).catch(() => false);
  }
  await chrome.runtime.sendMessage({ type: 'act', action: 'sites', on: granted }).catch(() => {});
  if (!yes) done(W.SETUP_DONE_NO_TITLE, W.SETUP_DONE_NO, true);
  else if (granted) done(W.SETUP_DONE_YES_TITLE, W.SETUP_DONE_YES, true);
  else done(W.SETUP_REFUSED_TITLE, W.SETUP_REFUSED.replace("Chrome didn't allow it, so this", 'So this'), false);
}

page.append(
  h('img', { class: 'logo', src: '../icons/icon128.png', alt: '' }),
  h('h1', { id: 'title', text: W.SETUP_TITLE }),
  h('p', { class: 'lede strong', text: W.SETUP_LEDE }),
  // how to use it first, so the page that opens after installing reads as a welcome, not a warning
  h('section', { class: 'card', 'aria-labelledby': 'how' },
    h('h2', { id: 'how', text: W.SETUP_HOW }),
    h('ol', { class: 'steps' }, ...W.SETUP_STEPS.map((t) => h('li', { text: t }))),
    h('p', { class: 'note', text: W.SETUP_NOTHING_ELSE })),
  h('section', { class: 'card', 'aria-labelledby': 'ask' },
    h('h2', { id: 'ask', text: W.SETUP_ASK }),
    h('p', { text: W.SETUP_WHY }),
    h('p', { class: 'note', text: W.SITES_HOW }),
    h('p', { class: 'note', text: W.SETUP_NO_COST }),
    h('div', { class: 'row', id: 'actions' },
      h('button', { class: 'btn primary', onclick: () => answer(true) }, W.SETUP_YES),
      h('button', { class: 'btn tall', onclick: () => answer(false) }, W.SETUP_NO))),
);

// Optional, after the one choice: let it turn off extensions you don't need, with what stays on said up front.
async function allowExtensions(btn) {
  btn.disabled = true;
  await chrome.runtime.sendMessage({ type: 'act', action: 'restEnabled', on: true }).catch(() => {});
  const ok = await chrome.permissions.request({ permissions: ['management'] }).catch(() => false);
  const row = document.getElementById('ext-actions');
  row.replaceWith(h('div', { id: 'ext-actions', class: ok ? 'confirm' : 'confirm off', role: 'status' },
    icon(ok ? 'check' : 'warn'), h('div', { text: ok ? W.SETUP_EXT_DONE : W.PAUSE_REFUSED })));
  if (!ok) await chrome.runtime.sendMessage({ type: 'act', action: 'restEnabled', on: false }).catch(() => {});
}
page.append(h('section', { class: 'card', 'aria-labelledby': 'ext' },
  h('h2', { id: 'ext', text: W.EXT_REC_TITLE }),
  h('p', { text: W.EXT_REC_LINE }),
  h('p', { class: 'note', text: W.EXT_REC_NOTE }),
  h('div', { class: 'row', id: 'ext-actions' },
    h('button', { class: 'btn', onclick: (e) => allowExtensions(e.currentTarget) }, W.EXT_REC_ALLOW))));

chrome.permissions.contains(ALL_SITES).then((granted) => { if (granted) done(W.SETUP_DONE_YES_TITLE, W.SETUP_DONE_YES, true); });
