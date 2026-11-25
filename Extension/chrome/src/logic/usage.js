// The extension's own record of tab use. Chrome's tab.lastAccessed is a fallback only: the levels need how
// often a tab is switched to, which Chrome doesn't keep. Stored in chrome.storage.session, because the
// service worker can stop at any time (test T13: after about 30 seconds idle) and tab IDs end with Chrome.

// "Most used" means switched to most often and most recently in the last 30 minutes (design, "How hard it works").
export const USE_WINDOW_MS = 30 * 60 * 1000;
const MAX_SWITCHES = 50;

// use: { [tabId]: { last: ts (became active), left: ts (stopped being active), switches: [ts] } }
export function recordActivation(use, tabId, previousTabId, now) {
  const next = { ...use };
  if (previousTabId != null && previousTabId !== tabId && next[previousTabId]) {
    next[previousTabId] = { ...next[previousTabId], left: now };
  } else if (previousTabId != null && previousTabId !== tabId) {
    next[previousTabId] = { last: null, left: now, switches: [] };
  }
  const cur = next[tabId] || { last: null, left: null, switches: [] };
  const switches = [...cur.switches.filter((t) => now - t < USE_WINDOW_MS), now].slice(-MAX_SWITCHES);
  next[tabId] = { ...cur, last: now, switches };
  return next;
}

// When the tab was last in front of the person: when it was left, or when it became active, or Chrome's own
// lastAccessed if the extension hasn't seen it yet (for example, tabs restored at startup).
export function lastUsed(tab, use) {
  const u = use[tab.id];
  const ours = Math.max(u?.left ?? 0, u?.last ?? 0);
  if (ours > 0) return ours;
  return typeof tab.lastAccessed === 'number' ? tab.lastAccessed : null;
}

// Most used first: switches in the last 30 minutes, then most recent. The tab in front of the person in the
// focused window always comes first, since it is the one in use.
export function rankMostUsed(tabs, use, now, frontTabId = null) {
  const score = (t) => (use[t.id]?.switches || []).filter((s) => now - s < USE_WINDOW_MS).length;
  return [...tabs].sort((a, b) => {
    if (a.id === frontTabId) return -1;
    if (b.id === frontTabId) return 1;
    const d = score(b) - score(a);
    if (d !== 0) return d;
    return (lastUsed(b, use) ?? 0) - (lastUsed(a, use) ?? 0);
  }).map((t) => t.id);
}

// The tab to show when the person puts the one in front to sleep (Chrome won't unload the tab in front of a window in use): the next
// awake tab to its right in the same window, going round to the first tab after the last, so pressing the shortcut
// again and again sleeps the window's tabs one after another. It used to be the tab used before it, which made the
// shortcut go back and forth between two tabs, waking each the other had just put to sleep. A tab already asleep is
// passed over, since showing it would load it again; when every other tab is asleep, the one to its right (or, for
// the last tab, its left) shows, as when a tab is closed. Null when it is the window's only tab.
export function tabToShowInstead(tabs, tabId) {
  const me = tabs.find((t) => t.id === tabId);
  if (!me) return null;
  const others = tabs.filter((t) => t.windowId === me.windowId && t.id !== tabId).sort((a, b) => a.index - b.index);
  if (!others.length) return null;
  const after = others.filter((t) => t.index > me.index);
  const before = others.filter((t) => t.index < me.index);
  const awake = [...after, ...before].find((t) => !t.discarded);
  return (awake || after[0] || before[before.length - 1]).id;
}

export function pruneUse(use, liveIds) {
  const live = new Set(liveIds);
  return Object.fromEntries(Object.entries(use).filter(([id]) => live.has(Number(id))));
}

// Chrome can give a tab a new ID when it unloads or prerenders it (tabs.onReplaced); carry its record over.
export function replaceId(map, removedId, addedId) {
  if (!map || !(removedId in map)) return map;
  const next = { ...map, [addedId]: map[removedId] };
  delete next[removedId];
  return next;
}
