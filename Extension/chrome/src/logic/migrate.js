// Moving tabs over from a tab suspender. A suspender such as The Marvellous Suspender swaps each tab for a page of
// its own that holds the real address; Chrome closes those pages if the suspender is removed or turned off, so the
// tabs would be lost. Taking them over means opening each real address once and unloading it straight away with
// chrome.tabs.discard, one tab at a time so memory never jumps.

const EXT_PAGE = /^chrome-extension:\/\/([a-p]{32})\/(.*)$/;
// The names suspenders give the real address in their page's link. "uri" is The Great Suspender's family, which puts
// it last and unencoded, so everything after it is the address; the others are cut at the next "&" and decoded.
const KEYS = ['uri', 'url', 'u', 'link', 'href', 'target', 'page', 'original'];
const WEB = /^https?:\/\//i;

function decoded(v) {
  let out = v;
  for (let i = 0; i < 3 && !WEB.test(out); i++) {
    try { out = decodeURIComponent(out); } catch { return null; }
  }
  return WEB.test(out) ? out : null;
}

// The real address behind a tab on another extension's page, or null when it isn't a suspended web page.
export function suspendedAt(tabUrl, selfId) {
  const m = EXT_PAGE.exec(tabUrl || '');
  if (!m || m[1] === selfId) return null;
  const rest = m[2];
  for (const key of KEYS) {
    const at = new RegExp(`[?#&]${key}=`, 'i').exec(rest);
    if (!at) continue;
    const value = rest.slice(at.index + at[0].length);
    const url = key === 'uri' && WEB.test(value) ? value : decoded(value.split(/[&#]/)[0]);
    if (url) return { extId: m[1], url };
  }
  return null;
}

// Every tab a suspender holds: { tabId, extId, url, active }.
export function migrationPlan(tabs, selfId) {
  const out = [];
  for (const t of tabs) {
    const s = suspendedAt(t.url || t.pendingUrl, selfId);
    if (s) out.push({ tabId: t.id, extId: s.extId, url: s.url, active: Boolean(t.active) });
  }
  return out;
}

// The suspender holding the most tabs comes first, for naming it.
export function suspenders(plan) {
  const counts = new Map();
  for (const p of plan) counts.set(p.extId, (counts.get(p.extId) || 0) + 1);
  return [...counts.entries()].sort((a, b) => b[1] - a[1]).map(([id]) => id);
}
