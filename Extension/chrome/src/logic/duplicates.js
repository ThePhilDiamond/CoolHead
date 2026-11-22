// Tabs with the same address in the same Chrome profile are the same page, since a profile shares its
// sign-ins (design, "Duplicates"). Two Gmail accounts aren't duplicates: Google puts the account in the address.
// The extension only ever sees its own profile, so profiles are never compared. Never closed automatically.
import { heldReasons, isWebPage } from './reasons.js';
import { lastUsed } from './usage.js';

// The whole address, fragment included: a fragment can be a different view (Gmail's #inbox and #sent), and
// closing a tab is the one action here that can't be undone in place, so only exact copies count.
export function sameAddressKey(url) {
  return url;
}

// A copy is never closed if it is in front, or held for a reason the person would miss (a call, typing,
// sound, kept, pinned, or in the session).
function closable(tab, ctx) {
  return !tab.active && heldReasons(tab, ctx).length === 0;
}

// Returns [{ url, title, keepId, closeIds }], one per page open more than once, keeping the copy used last.
export function findDuplicates(tabs, ctx) {
  const byUrl = new Map();
  for (const t of tabs) {
    if (!isWebPage(t.url)) continue;
    const k = sameAddressKey(t.url);
    if (!byUrl.has(k)) byUrl.set(k, []);
    byUrl.get(k).push(t);
  }
  const groups = [];
  for (const [url, copies] of byUrl) {
    if (copies.length < 2) continue;
    const sorted = [...copies].sort((a, b) => {
      if (a.active !== b.active) return a.active ? -1 : 1;
      return (lastUsed(b, ctx.use || {}) ?? 0) - (lastUsed(a, ctx.use || {}) ?? 0);
    });
    const keep = sorted[0];
    const closeIds = sorted.slice(1).filter((t) => closable(t, ctx)).map((t) => t.id);
    if (closeIds.length === 0) continue;
    groups.push({ url, title: keep.title || url, keepId: keep.id, closeIds });
  }
  return groups;
}

export function duplicateCount(groups) {
  return groups.reduce((n, g) => n + g.closeIds.length, 0);
}
