// A page of Cool Head for Chrome's own for a tab that a tab suspender held whose address downloads a file instead of
// opening a page (src/worker.js, runMigration). Opening the address only downloads the file again, so the tab can't
// leave the suspender's page by itself; this page takes it over, with the title and address in its link
// (#title=…&url=…), so the suspender can be removed without closing the tab and losing the address.
import { h } from '../popup/render.js';
import * as W from '../src/logic/words.js';

const q = new URLSearchParams(location.hash.slice(1));
const title = q.get('title') || W.PARKED_UNTITLED;
const url = q.get('url') || '';
document.title = title;

async function closeTab() {
  const tab = await chrome.tabs.getCurrent();
  if (tab) chrome.tabs.remove(tab.id);
}

document.getElementById('page').append(
  h('img', { class: 'logo', src: '../icons/icon128.png', alt: '' }),
  h('h1', { id: 'title', text: title }),
  h('p', { class: 'lede', text: W.PARKED_WHY }),
  h('section', { class: 'card' },
    h('p', { class: 'note', text: W.PARKED_ADDRESS }),
    h('p', { class: 'address' }, h('a', { href: url, text: url })),
    h('div', { class: 'row' },
      h('a', { class: 'btn primary', href: url, text: W.PARKED_DOWNLOAD }),
      h('button', { class: 'btn', onclick: closeTab }, W.PARKED_CLOSE))),
);
