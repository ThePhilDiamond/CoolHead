// A fake Chrome, enough to load the real src/worker.js in Node and drive it through its own event listeners, for the
// worker's tests (the worker can't run outside Chrome otherwise). A fake clock: Date.now and setTimeout are its own, so
// a test can move time on. Windows have a state and focus; tabs are active, discarded, and loading or not; discard is in
// place (the tab keeps its ID) or the older way (a new ID and onReplaced). Each test file gets its own process, so its
// own worker. Written for the independent review of minimized windows (25 November 2026).
const SRC = new URL('../src/', import.meta.url).href;

export function install({ inPlace = true } = {}) {
  // ---- clock ----
  let clock = Date.UTC(2026, 10, 25, 12, 0, 0);
  const realNow = Date.now;
  Date.now = () => clock;
  const timers = [];
  let tid = 1;
  globalThis.setTimeout = (fn, ms = 0) => { const id = tid++; timers.push({ id, at: clock + Math.max(0, ms || 0), fn }); return id; };
  globalThis.clearTimeout = (id) => { const i = timers.findIndex((t) => t.id === id); if (i >= 0) timers.splice(i, 1); };
  const settle = async (n = 60) => { for (let i = 0; i < n; i++) await new Promise((r) => setImmediate(r)); };
  async function advance(ms) {
    const end = clock + ms;
    for (;;) {
      timers.sort((a, b) => a.at - b.at);
      const t = timers[0];
      if (!t || t.at > end) break;
      timers.shift();
      clock = Math.max(clock, t.at);
      t.fn();
      await settle();
    }
    clock = end;
    await settle();
  }

  // ---- events ----
  const listeners = {};
  const ev = (name) => ({
    addListener: (f) => { (listeners[name] ||= []).push(f); },
    removeListener: (f) => { listeners[name] = (listeners[name] || []).filter((g) => g !== f); },
    hasListener: () => false,
  });
  const fire = (name, ...args) => { for (const f of [...(listeners[name] || [])]) f(...args); };

  // ---- model ----
  const windows = new Map();   // id -> { id, state, focused, type }
  let tabs = [];               // { id, windowId, index, active, discarded, status, url, title, audible, pinned, autoDiscardable, lastAccessed }
  let nextTab = 1000;
  let lastFocused = null;
  const calls = { reload: [], discard: [], executeScript: [] };
  const slowScript = new Set(); // tab IDs whose executeScript never answers (the 1-second race in titleMark wins)
  const copy = (o) => (o ? structuredClone(o) : o);
  const local = {}; const session = {};
  const area = (obj) => ({
    get: async (keys) => {
      const ks = keys == null ? Object.keys(obj) : Array.isArray(keys) ? keys : typeof keys === 'string' ? [keys] : Object.keys(keys);
      const out = {}; for (const k of ks) if (k in obj) out[k] = structuredClone(obj[k]); return out;
    },
    set: async (p) => { for (const [k, v] of Object.entries(p)) obj[k] = structuredClone(v); },
    remove: async () => {},
  });

  const chrome = {
    runtime: {
      id: 'fakeextid', getManifest: () => ({ version: '9.9.9' }), getURL: (p) => `chrome-extension://fakeextid${p.startsWith('/') ? '' : '/'}${p}`,
      connectNative: () => { throw new Error('no host'); }, lastError: undefined,
      getPlatformInfo: async () => ({ os: 'mac' }),
      onMessage: ev('runtime.onMessage'), onInstalled: ev('runtime.onInstalled'), onStartup: ev('runtime.onStartup'), onConnect: ev('runtime.onConnect'),
    },
    storage: { local: area(local), session: area(session), onChanged: ev('storage.onChanged') },
    alarms: { create: () => {}, get: async () => ({ name: 'tick' }), clear: async () => {}, onAlarm: ev('alarms.onAlarm') },
    action: { setIcon: async () => {}, setBadgeText: async () => {}, setTitle: async () => {}, openPopup: async () => {} },
    contextMenus: { create: () => {}, update: () => {}, removeAll: (cb) => cb && cb(), onClicked: ev('contextMenus.onClicked') },
    commands: { getAll: async () => [], onCommand: ev('commands.onCommand') },
    permissions: { contains: async () => false, onAdded: ev('permissions.onAdded'), onRemoved: ev('permissions.onRemoved') },
    scripting: {
      executeScript: ({ target }) => { calls.executeScript.push(target.tabId); return slowScript.has(target.tabId) ? new Promise(() => {}) : Promise.resolve([{ result: true }]); },
      getRegisteredContentScripts: async () => [], registerContentScripts: async () => {}, unregisterContentScripts: async () => {},
    },
    tabGroups: { query: async () => [], update: async () => {} },
    system: { memory: { getInfo: async () => ({ capacity: 1, availableCapacity: 1 }) } },
    management: { getAll: async () => [] },
    bookmarks: {},
    windows: {
      WINDOW_ID_NONE: -1,
      getAll: async (q) => [...windows.values()].filter((w) => !q?.windowTypes || q.windowTypes.includes(w.type)).map(copy),
      get: async (id) => { const w = windows.get(id); if (!w) throw new Error('no window'); return copy(w); },
      getLastFocused: async () => copy(windows.get(lastFocused)),
      create: async () => { throw new Error('not modelled'); },
      update: async () => {},
      onFocusChanged: ev('windows.onFocusChanged'), onBoundsChanged: ev('windows.onBoundsChanged'),
      onCreated: ev('windows.onCreated'), onRemoved: ev('windows.onRemoved'),
    },
    tabs: {
      query: async (q = {}) => tabs.filter((t) =>
        (q.active == null || t.active === q.active)
        && (q.windowId == null || t.windowId === q.windowId)
        && (q.discarded == null || t.discarded === q.discarded)
        && (!q.lastFocusedWindow || t.windowId === lastFocused)).map(copy),
      get: async (id) => { const t = tabs.find((x) => x.id === id); if (!t) throw new Error('no tab'); return copy(t); },
      discard: async (id) => {
        const t = tabs.find((x) => x.id === id);
        calls.discard.push(id);
        if (!t || t.discarded) return undefined;
        if (inPlace) {
          t.discarded = true; t.status = 'unloaded';
          setImmediate(() => fire('tabs.onUpdated', id, { discarded: true }, copy(t)));
          return copy(t);
        }
        const nid = nextTab++;
        t.id = nid; t.discarded = true; t.status = 'unloaded';
        setImmediate(() => fire('tabs.onReplaced', nid, id));
        return copy(t);
      },
      reload: async (id) => { const t = tabs.find((x) => x.id === id); calls.reload.push({ id, at: clock, wasStatus: t?.status }); if (t) { t.discarded = false; t.status = 'complete'; } },
      update: async (id, p) => {
        const t = tabs.find((x) => x.id === id); if (!t) throw new Error('no tab');
        if (p.active) { for (const o of tabs) if (o.windowId === t.windowId) o.active = false; t.active = true; }
        Object.assign(t, Object.fromEntries(Object.entries(p).filter(([k]) => k !== 'active')));
        return copy(t);
      },
      create: async () => { throw new Error('not modelled'); },
      remove: async (ids) => { tabs = tabs.filter((t) => !(Array.isArray(ids) ? ids : [ids]).includes(t.id)); },
      onActivated: ev('tabs.onActivated'), onCreated: ev('tabs.onCreated'), onRemoved: ev('tabs.onRemoved'), onReplaced: ev('tabs.onReplaced'),
      onUpdated: ev('tabs.onUpdated'), onMoved: ev('tabs.onMoved'), onAttached: ev('tabs.onAttached'),
    },
  };
  globalThis.chrome = chrome;
  globalThis.self = globalThis;
  globalThis.addEventListener ||= () => {};
  Object.defineProperty(globalThis, 'navigator', { value: { onLine: true }, configurable: true });

  // ---- helpers for the scenarios ----
  const W = {
    clock: () => clock, advance, settle, fire, calls, slowScript, local, session, timers,
    win(id, state = 'normal', focused = false) { windows.set(id, { id, state, focused, type: 'normal' }); if (focused) lastFocused = id; },
    setWin(id, p) { Object.assign(windows.get(id), p); if (p.focused) { lastFocused = id; for (const w of windows.values()) if (w.id !== id) w.focused = false; } },
    tab(p) { const t = { id: nextTab++, windowId: 1, index: tabs.filter((x) => x.windowId === (p.windowId ?? 1)).length, active: false, discarded: false, status: 'complete', url: `https://site${nextTab}.example/`, title: `Page ${nextTab}`, audible: false, pinned: false, autoDiscardable: true, lastAccessed: clock - 3600e3, ...p }; tabs.push(t); return t; },
    tabs: () => tabs,
    byId: (id) => tabs.find((t) => t.id === id),
    setLastFocused(id) { lastFocused = id; },
  };
  return W;
}

export async function loadWorker(W) {
  await import(SRC + 'worker.js');
  await W.settle(200);
  return globalThis.coolHead;
}
