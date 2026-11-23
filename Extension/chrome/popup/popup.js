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
  levelSet: null, // the level just chosen, said on its row until Effort goes back home
  confirm: null,
  ending: false,
  groupName: null,
  start: null,
  ticked: new Set(),
  windowOnly: false,
  beforeWindowOnly: null,
  showAllOthers: false,
  safe: null,
  laterNote: false, // after "Do it later": home says where to find the move again, until the popup closes
  offered: false,   // the move was offered on this opening already
};
let view = null;
let closeLevels = null;

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
  // Cool Head's "Turn off extensions" opens Protected, at its extensions; Chrome only asks for a permission after a
  // click, so without it yet, the part shows its Allow button.
  if (view.openScreen === 'safe') {
    await loadSafe();
    ui.screen = 'protected';
  }
  // Tabs a suspender holds are offered once, when the popup first finds them, unless the person put it off; a move
  // under way, or its result, shows whenever the popup opens.
  const m = view.migrate;
  if (!before && m && ui.screen === 'home' && (m.running || m.result || (m.count && !m.later))) ui.screen = 'migrate';
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

// Protected's extensions, read when pausing is on and Chrome allows reading them.
async function loadSafe() {
  ui.safe = view.settings.restEnabled && view.settings.managementGranted ? await ask({ type: 'safe' }) : null;
}

async function openSafe() {
  // Chrome's "Manage your apps, extensions, and themes" permission is asked for only here, when first used.
  const granted = await chrome.permissions.request({ permissions: ['management'] }).catch(() => false);
  if (!granted) { announce(W.PAUSE_REFUSED); return; }
  view = await ask({ type: 'view' });
  await loadSafe();
  ui.screen = 'protected';
}

// A tool in the bottom bar: pressing the open one again goes back home, as in Cool Head. Focus stays on the tool.
async function openTool(screen) {
  if (ui.screen === screen) { on.home(); return; }
  if (screen === 'protected') await loadSafe();
  ui.screen = screen;
  ui.confirm = null;
  draw();
}

const on = {
  openSettings() { openTool('settings').catch(console.error); },
  openProtected() { openTool('protected').catch(console.error); },
  // The effort choices slide down as they open; later redraws draw them still.
  openEffort() { clearTimeout(closeLevels); ui.levelSet = null; openTool('effort').catch(console.error); },
  // Back home from a tool, by the band's pill, the band, or the open tool again; focus goes to the tool that was open.
  home() {
    const from = ui.screen;
    if (from === 'home') return;
    ui.screen = 'home';
    ui.confirm = null;
    draw();
    root.querySelector(`[data-key="${from}"]`)?.focus({ preventScroll: true });
  },
  // A click sets the level at once; its row says so, and a moment later Effort goes back home, focus going to the
  // Effort tool. Choosing the level already set goes back the same way.
  async level(id) {
    clearTimeout(closeLevels);
    if (id !== view.levels.chosen) {
      const r = await act({ action: 'level', level: id });
      announce(`${r.said} ${r.view.levels.line}`);
    }
    ui.levelSet = id;
    draw();
    closeLevels = setTimeout(() => {
      ui.levelSet = null;
      if (ui.screen === 'effort') on.home(); else draw();
    }, 1500);
  },
  keep(tabId, keep) { ui.confirm = null; act({ action: 'keep', tabId, on: keep }); },
  sleep(row) { tryRisky(row, 'sleep'); },
  // Brings the tab forward and its window to the front; the popup closes as Chrome's focus moves.
  async show(tabId) {
    const tab = await chrome.tabs.update(tabId, { active: true }).catch(() => null);
    if (tab) await chrome.windows.update(tab.windowId, { focused: true }).catch(() => {});
  },
  close(row) { tryRisky(row, 'close'); },
  closeDuplicates() { act({ action: 'closeDuplicates' }); },
  closedDupsSeen() { act({ action: 'closedDupsSeen' }); },
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
  // Chrome keeps the keys for every extension on one page of its own; an extension can open it but not set a key.
  keepSite(host, on) { act({ action: 'keepSite', host, on }); },
  offlineHold(on) { act({ action: 'offlineHold', on }); },
  openMigrate() { ui.screen = 'migrate'; draw(); },
  migrate() { act({ action: 'migrate' }); },
  async migrateLater() {
    await act({ action: 'migrateLater' });
    ui.screen = 'home';
    ui.laterNote = true;
    draw();
    announce(W.MIGRATE_LATER_NOTE);
  },
  async migrateClose() { await act({ action: 'migrateClose' }); ui.screen = 'home'; draw(); },
  // Chrome asks the person to confirm; the permission is asked for here, on the click, if it isn't given yet.
  async migrateRemove(id) {
    const ok = await chrome.permissions.request({ permissions: ['management'] }).catch(() => false);
    if (!ok) return;
    await chrome.management.uninstall(id, { showConfirmDialog: true }).catch(() => {});
    await refresh();
  },
  shortcut() { chrome.tabs.create({ url: 'chrome://extensions/shortcuts' }).catch(console.error); window.close(); },
  async sites(turnOn) {
    if (turnOn) {
      // Chrome shows its own question; the worker also hears of the answer if this popup closes meanwhile.
      const granted = await chrome.permissions.request(ALL_SITES).catch(() => false);
      if (!granted) { announce(W.SETUP_REFUSED); draw(); return; }
    }
    await act({ action: 'sites', on: turnOn });
  },
  async restEnabled(turnOn) {
    // Saved first: Chrome's permission question can close the popup before anything after it runs.
    await act({ action: 'restEnabled', on: turnOn });
    if (turnOn && !view.settings.managementGranted) {
      const granted = await chrome.permissions.request({ permissions: ['management'] }).catch(() => false);
      if (!granted) { await act({ action: 'restEnabled', on: false }); announce(W.PAUSE_REFUSED); return; }
    }
    // Protected's lists appear under the switch once pausing is on and allowed.
    if (ui.screen === 'protected') { view = await ask({ type: 'view' }); await loadSafe(); draw(); }
  },
  async openSafe() { await openSafe(); draw(); },
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
    if ((ui.screen === 'home' && !ui.ending) || ['settings', 'protected', 'effort', 'migrate'].includes(ui.screen)) refresh().catch(console.error);
  }, 200);
}
chrome.storage.onChanged.addListener(soon);
for (const ev of [chrome.tabs.onUpdated, chrome.tabs.onRemoved, chrome.tabs.onCreated, chrome.tabs.onActivated]) ev.addListener(soon);

refresh().catch((e) => {
  root.textContent = `${W.NAME} couldn't load: ${e.message}`;
});
