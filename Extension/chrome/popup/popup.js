// The popup: asks the worker for a view, draws it, and passes the person's choices back. The worker does all
// the work, so the popup can close at any moment without leaving anything half done.
import { render } from './render.js';
import { windowOnly } from '../src/logic/session.js';
import * as W from '../src/logic/words.js';

const root = document.getElementById('app');
const say = document.getElementById('say');
const ALL_SITES = { origins: ['<all_urls>'] };

const ui = {
  screen: 'home',
  heldOpen: false, // folded by default, showing its count, like Cool Head's folded groups
  confirm: null,
  ending: false,
  groupName: null,
  start: null,
  ticked: new Set(),
  windowOnly: false,
  beforeWindowOnly: null,
  showAllOthers: false,
  safe: null,
};
let view = null;

function ask(msg) {
  return chrome.runtime.sendMessage(msg).then((r) => {
    if (r && r.error) throw new Error(r.error);
    return r;
  });
}

function announce(text) {
  if (!text) return;
  // Cleared first, so saying the same thing twice is still heard.
  say.textContent = '';
  setTimeout(() => { say.textContent = text; }, 50);
}

function draw() {
  if (view) render(root, view, ui, on);
}

async function refresh() {
  const before = view;
  view = await ask({ type: 'view' });
  // A change in memory while the popup is open is said aloud, once, through the lasting live region.
  if (before && before.band.title !== view.band.title) announce(`${view.band.title}. ${view.band.line}`);
  // Cool Head's "Turn off extensions" opens the safe list; Chrome only asks for a permission after a click, so
  // without it yet, Settings opens with its Choose the safe list button.
  if (view.openScreen === 'safe') {
    if (view.settings.managementGranted) {
      ui.safe = await ask({ type: 'safe' });
      ui.screen = 'safe';
    } else ui.screen = 'settings';
  }
  // Nothing the popup shows has changed (a tab finished loading, the worker saved its own bookkeeping): no redraw,
  // so nothing moves under the person's pointer.
  if (before && !view.openScreen && JSON.stringify(before) === JSON.stringify(view)) return;
  draw();
}

async function act(m) {
  const r = await ask({ type: 'act', ...m });
  view = r.view;
  announce(r.said);
  draw();
  return r;
}

async function openSafe() {
  // Chrome's "Manage your apps, extensions, and themes" permission is asked for only here, when first used.
  const granted = await chrome.permissions.request({ permissions: ['management'] }).catch(() => false);
  if (!granted) { announce(W.REST_NEEDS); return; }
  ui.safe = await ask({ type: 'safe' });
  ui.screen = 'safe';
}

const on = {
  openSettings() { ui.screen = 'settings'; ui.confirm = null; draw(); root.querySelector('[data-key="back"]')?.focus(); },
  back() {
    const from = ui.screen;
    ui.screen = from === 'safe' ? 'settings' : 'home';
    draw();
    root.querySelector(`[data-key="${from === 'safe' ? 'safe' : 'settings'}"]`)?.focus();
  },
  toggleHeld() { ui.heldOpen = !ui.heldOpen; ui.confirm = null; draw(); },
  async level(id) { const r = await act({ action: 'level', level: id }); announce(`${r.said} ${r.view.levels.line}`); },
  keep(tabId, keep) { ui.confirm = null; act({ action: 'keep', tabId, on: keep }); },
  sleep(row) { tryRisky(row, 'sleep'); },
  close(row) { tryRisky(row, 'close'); },
  closeDuplicates() { act({ action: 'closeDuplicates' }); },
  getCoolHead() { act({ action: 'openCoolHead' }); },
  keepAnswer(key, tabId) { act({ action: 'keepAnswer', key, tabId }); },

  async openStart() {
    ui.start = await ask({ type: 'start' });
    ui.ticked = new Set(ui.start.suggested);
    ui.windowOnly = false;
    ui.beforeWindowOnly = null;
    ui.showAllOthers = false;
    ui.screen = 'start';
    draw();
    root.querySelector('[data-key="close-start"]')?.focus();
  },
  closeStart() { ui.screen = 'home'; draw(); root.querySelector('[data-key="start"]')?.focus(); },
  tick(id, checked) {
    if (checked) ui.ticked.add(id); else ui.ticked.delete(id);
    draw();
  },
  windowOnly(checked) {
    ui.windowOnly = checked;
    if (checked) {
      ui.beforeWindowOnly = new Set(ui.ticked);
      ui.ticked = windowOnly(ui.start.rows, ui.start.windowId);
    } else {
      ui.ticked = ui.beforeWindowOnly || new Set(ui.start.suggested);
    }
    draw();
  },
  showMore() { ui.showAllOthers = !ui.showAllOthers; draw(); },
  async startSession() {
    await act({ action: 'startSession', tabIds: [...ui.ticked] });
    ui.screen = 'home';
    draw();
    root.querySelector('[data-key="end"]')?.focus();
  },
  endSession() { ui.ending = true; ui.groupName = null; draw(); root.querySelector('[data-key="group-name"]')?.focus(); },
  groupName(v) { ui.groupName = v; },
  async save(name) { ui.ending = false; await act({ action: 'endSession', save: true, name }); root.querySelector('[data-key="start"]')?.focus(); },
  async endWithout() { ui.ending = false; await act({ action: 'endSession', save: false }); root.querySelector('[data-key="start"]')?.focus(); },

  leaveDelay(ms) { act({ action: 'leaveDelay', ms }); },
  async sites(turnOn) {
    if (turnOn) {
      // Chrome shows its own question; the worker also hears of the answer if this popup closes meanwhile.
      const granted = await chrome.permissions.request(ALL_SITES).catch(() => false);
      if (!granted) { announce(W.SETUP_REFUSED); return; }
    }
    await act({ action: 'sites', on: turnOn });
  },
  async restEnabled(turnOn) {
    // Saved first: Chrome's permission question can close the popup before anything after it runs.
    await act({ action: 'restEnabled', on: turnOn });
    if (turnOn && !view.settings.managementGranted) {
      const granted = await chrome.permissions.request({ permissions: ['management'] }).catch(() => false);
      if (!granted) { await act({ action: 'restEnabled', on: false }); announce(W.REST_NEEDS); }
    }
  },
  async openSafe() { await openSafe(); draw(); root.querySelector('[data-key="back"]')?.focus(); },
  async safeMove(id, toAlwaysOn) {
    await act({ action: 'safeMove', id, toAlwaysOn });
    ui.safe = await ask({ type: 'safe' });
    draw();
  },
};

// Sleep or Close on a tab on a call, sharing the screen, or with unsent typing asks once; the second press does
// it. Focus stays on the button, and the warning is said aloud.
function tryRisky(row, action) {
  if (row.risk && !(ui.confirm && ui.confirm.tabId === row.id && ui.confirm.action === action)) {
    ui.confirm = { tabId: row.id, action };
    draw();
    announce(W.warning(action, row.risk));
    return;
  }
  ui.confirm = null;
  act({ action, tabId: row.id });
}

// Redraw when tabs or state change while the popup is open, at most every 200 ms.
// Not while the person is scrolling either: replacing the list mid-scroll stops it; the redraw waits for a pause.
let pending = null;
let scrolledAt = 0;
document.addEventListener('scroll', () => { scrolledAt = Date.now(); }, { capture: true, passive: true });
function soon() {
  clearTimeout(pending);
  pending = setTimeout(() => {
    if (Date.now() - scrolledAt < 400) { soon(); return; }
    // Not while the group name is being typed: a redraw would move the caret and break input methods.
    if ((ui.screen === 'home' && !ui.ending) || ui.screen === 'settings') refresh().catch(console.error);
  }, 200);
}
chrome.storage.onChanged.addListener(soon);
for (const ev of [chrome.tabs.onUpdated, chrome.tabs.onRemoved, chrome.tabs.onCreated, chrome.tabs.onActivated]) ev.addListener(soon);

refresh().catch((e) => {
  root.textContent = `${W.NAME} couldn't load: ${e.message}`;
});
