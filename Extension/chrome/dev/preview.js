// Draws the real popup (popup/render.js and src/logic/view.js) from made-up tabs, for screenshots and design
// review without Chrome's extension APIs. Open preview.html?screen=home&theme=dark. All data here is invented.
import { render } from '../popup/render.js';
import { buildView, buildStart } from '../src/logic/view.js';
import { LOCAL_DEFAULTS, SESSION_DEFAULTS } from '../src/store.js';
import { columns } from '../src/logic/extensions.js';

const q = new URLSearchParams(location.search);
const screen = q.get('screen') || 'home';
document.documentElement.className = q.get('theme') === 'dark' ? 'dark' : 'light';

const NOW = Date.now();
const MIN = 60000;
let id = 0;
const T = (title, url, over = {}) => ({ id: ++id, windowId: 1, index: id, title, url, active: false, pinned: false, audible: false, discarded: false, groupId: -1, autoDiscardable: true, lastAccessed: NOW - 3 * 60 * MIN, ...over });

const front = T('Re: Spring proposal for Harbor & Pine', 'https://mail.example.com/mail/u/0/#inbox/1', { active: true, lastAccessed: NOW });
const call = T('Client call', 'https://meet.google.com/abc-defg-hij');
const budget = T('Spring budget', 'https://sheets.example.com/d/budget');
const deck = T('Spring proposal deck', 'https://slides.example.com/d/deck');
const music = T('Lo-fi beats to focus to', 'https://video.example.com/watch?v=lofi', { audible: true });
const sync = T('Weekly team sync', 'https://zoom.us/wc/123/join');
const form = T('Travel expense form', 'https://forms.example.com/expenses');
const calendar = T('Team calendar', 'https://calendar.example.com/week', { pinned: true });
const tracker = T('Project tracker board', 'https://tracker.example.com/board/7');
const inbox1 = T('Inbox', 'https://mail.example.com/mail/u/0/#inbox');
const inbox2 = T('Inbox', 'https://mail.example.com/mail/u/0/#inbox');
const budget2 = T('Spring budget', 'https://sheets.example.com/d/budget');
const hiring = T('Hiring plan', 'https://docs.example.com/hiring', { lastAccessed: NOW - 40 * MIN });
const notes = T('Supplier research notes', 'https://notes.example.com/supplier', { lastAccessed: NOW - 60 * MIN });
const wiki = T('Team wiki', 'https://wiki.example.com/home', { lastAccessed: NOW - 120 * MIN, windowId: 2 });
const asleep = Array.from({ length: 23 }, (_, n) => T(`Article ${n + 1}`, `https://news.example.com/${n}`, { discarded: true, lastAccessed: NOW - (200 + n) * MIN, windowId: n % 2 ? 2 : 1 }));
const tabs = [front, call, budget, deck, music, sync, form, calendar, tracker, inbox1, inbox2, budget2, hiring, notes, wiki, ...asleep];

const use = {
  [budget.id]: { last: NOW - 4 * MIN, left: NOW - 4 * MIN, switches: [NOW - 4 * MIN] },
  [deck.id]: { last: NOW - 9 * MIN, left: NOW - 9 * MIN, switches: [NOW - 9 * MIN] },
  [inbox2.id]: { last: NOW - 50 * MIN, left: NOW - 50 * MIN, switches: [] },
  [budget2.id]: { last: NOW - 70 * MIN, left: NOW - 70 * MIN, switches: [] },
};

const linkedState = (memory) => ({ status: 'linked', app: '0.16.0', state: { memory, auto: true }, stateAt: NOW, attemptAt: null });
const s = {
  ...structuredClone(LOCAL_DEFAULTS),
  ...structuredClone(SESSION_DEFAULTS),
  level: 'auto',
  use,
  asleep: asleep.map((t) => t.id),
  kept: [{ tabId: tracker.id, url: tracker.url, title: tracker.title, index: tracker.index, windowOrdinal: 0 }],
  typing: { [form.id]: { 0: true } },
  media: { [sync.id]: { 0: { call: true, screen: false } } },
  link: linkedState('tight'),
  auto: { mode: 'off', fineSince: null },
};

const ui = {
  screen: 'home', levelOpen: false, confirm: null, ending: false, groupName: null, start: null,
  ticked: new Set(), windowOnly: false, beforeWindowOnly: null, showAllOthers: false, safe: null,
};

let sessionTabs = tabs;
if (screen === 'session' || screen === 'ending') {
  // A session started with four tabs; everything else unticked went to sleep.
  s.session = { active: true, tabIds: [front.id, call.id, budget.id, deck.id], startedAt: NOW - 25 * MIN };
  s.link = linkedState('fine');
  sessionTabs = tabs.map((t) => (s.session.tabIds.includes(t.id) || t.audible || t.pinned || t.id === sync.id || t.id === form.id || t.id === tracker.id ? t : { ...t, discarded: true }));
  s.asleep = sessionTabs.filter((t) => t.discarded).map((t) => t.id);
  ui.ending = screen === 'ending';
}
if (screen === 'alone') {
  s.link = { status: 'notInstalled', app: '', state: null, stateAt: null, attemptAt: null };
  s.level = 'balanced';
}
const protectedScreen = ['held', 'confirm', 'protected-ext'].includes(screen);
if (protectedScreen) { ui.screen = 'protected'; s.restEnabled = true; }
if (screen === 'levels') ui.levelOpen = true;
if (screen === 'confirm') ui.confirm = { tabId: form.id, action: 'close' };

const view = buildView({
  tabs: sessionTabs, s, now: NOW, focusedWindowId: 1, isMac: q.get('os') !== 'other',
  memInfo: { capacity: 16 * 1024 ** 3, availableCapacity: 2.5 * 1024 ** 3 }, version: '1.0.0',
  sitesGranted: true, managementGranted: protectedScreen,
});

if (screen === 'start') {
  ui.screen = 'start';
  ui.start = buildStart({ tabs, s, now: NOW, focusedWindowId: 1 });
  ui.ticked = new Set(ui.start.suggested);
}
if (screen === 'settings') ui.screen = 'settings';
if (protectedScreen) {
  const ext = (name, permissions = [], over = {}) => ({ id: name, name, type: 'extension', enabled: true, mayDisable: true, installType: 'normal', permissions, ...over });
  ui.safe = columns([
    ext('Vaultly Password Manager'), ext('Quiet Ad Blocker', ['declarativeNetRequest']), ext('Company sign-in', [], { installType: 'admin', mayDisable: false }),
    ext('Writing helper'), ext('Coupon finder'), ext('Screenshot tool'), ext('Read later'),
  ], null, 'self');
}

const noop = () => {};
const on = new Proxy({}, { get: () => noop });
const root = document.getElementById('app');
render(root, view, ui, on);

if (screen === 'confirm') root.querySelector(`[data-key="close-${form.id}"]`).focus();
if (screen === 'protected-ext') {
  const main = root.querySelector('main');
  main.scrollTop = root.querySelector('#p-ext-part').offsetTop - main.offsetTop - 6;
}
document.body.dataset.ready = 'yes';
