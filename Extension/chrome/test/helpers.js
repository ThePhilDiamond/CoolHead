// Made-up tabs and state for the tests.
export const NOW = Date.UTC(2026, 10, 21, 19, 15); // 21 November 2026
export const MIN = 60 * 1000;

let next = 100;
export function tab(over = {}) {
  next += 1;
  return {
    id: next, windowId: 1, index: 0, url: `https://example.com/${next}`, title: `Tab ${next}`,
    active: false, pinned: false, audible: false, discarded: false, groupId: -1, autoDiscardable: true,
    lastAccessed: NOW - 60 * MIN,
    ...over,
  };
}

// The context the rules read (see src/logic/view.js contextFrom), with nothing held.
export function ctx(over = {}) {
  return {
    now: NOW, level: 'balanced', leaveDelayMs: 30000, use: {}, kept: new Set(), sessionIds: null,
    audibleAt: {}, media: {}, typing: {}, frontTabId: null, autoMode: 'off', autoAllowed: false,
    ...over,
  };
}

// A use record: last active `agoMin` minutes ago, switched to `switches` times in the last 30 minutes.
export function used(agoMin, switches = 1) {
  const last = NOW - agoMin * MIN;
  return { last, left: last, switches: Array.from({ length: switches }, (_, i) => last - i * 1000) };
}
