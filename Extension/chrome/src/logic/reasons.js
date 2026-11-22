// Why a tab is held in memory. Chrome lets an extension unload almost any tab: its discard is marked EXTERNAL
// and skips Chrome's own safety checks (Chromium's discard_eligibility_policy.cc; in testing, an extension's discard
// unloaded the tab playing sound, the pinned tab, and the tab with typed text). So these checks are ours to make,
// copied from Chrome's.

// Shown and checked in this order: what would be lost first (a call, typing) before what only costs a reload.
export const REASON_ORDER = ['call', 'screen', 'typing', 'sound', 'kept', 'site', 'pinned', 'session'];

// A site the person keeps awake: the host without "www.", and a rule for a host covers its subdomains too.
export function siteOf(url) {
  try {
    const u = new URL(url);
    return /^https?:$/.test(u.protocol) ? u.hostname.replace(/^www\./, '').toLowerCase() : null;
  } catch { return null; }
}
export function siteRuleFor(url, sites) {
  const host = siteOf(url);
  if (!host || !sites?.length) return null;
  return sites.find((s) => host === s || host.endsWith(`.${s}`)) || null;
}

// The protocol's held reasons (PROTOCOL.md, the `report` message). A kept site reports as kept, so Cool Head's
// side of the link needs no change.
export const PROTOCOL_REASONS = ['sound', 'call', 'screen', 'typing', 'pinned', 'kept', 'session'];

// A call that has gone quiet still matters: without the camera and microphone check (it needs access to all
// sites), a tab that played sound in the last 10 minutes is treated as playing sound, so a muted pause in a call
// doesn't end it. Chrome's own rule spares tabs that "played sound recently" for a shorter time.
export const SOUND_GRACE_MS = 10 * 60 * 1000;

// Pages only worth sleeping when they are real web pages: Chrome's own pages hold little and some refuse.
export function isWebPage(url) {
  return typeof url === 'string' && /^(https?|file):/i.test(url);
}

// Meeting rooms recognized from the address alone, so a call is protected even without the all-sites
// permission. Only addresses that are a meeting room, not the product's other pages, to avoid calling a
// chat page a call.
const CALL_PAGES = [
  /^https:\/\/meet\.google\.com\/[a-z]{3}-[a-z]{4}-[a-z]{3}(?:[/?#]|$)/i,
  /^https:\/\/([a-z0-9-]+\.)?zoom\.us\/wc\//i,
  /^https:\/\/app\.zoom\.us\/wc\//i,
  /^https:\/\/meet\.jit\.si\/[^/?#]+/i,
  /^https:\/\/whereby\.com\/[^/?#]+/i,
  /^https:\/\/teams\.(microsoft|live)\.com\/.*\b(meetup-join|light-meetings|v2\/\?meetingjoin)/i,
];
export function isCallPage(url) {
  return typeof url === 'string' && CALL_PAGES.some((re) => re.test(url));
}

// ctx: { now, kept: Set<tabId>, sessionIds: Set<tabId> | null, audibleAt: {id: ts}, media: {id: {call, screen}},
//        typing: {id: true} }
export function heldReasons(tab, ctx) {
  const reasons = [];
  const media = ctx.media?.[tab.id] || {};
  if (media.call || isCallPage(tab.url)) reasons.push('call');
  if (media.screen) reasons.push('screen');
  if (ctx.typing?.[tab.id]) reasons.push('typing');
  if (tab.audible || recentlyAudible(tab, ctx)) reasons.push('sound');
  if (ctx.kept?.has(tab.id)) reasons.push('kept');
  if (siteRuleFor(tab.url, ctx.keepSites)) reasons.push('site');
  if (tab.pinned) reasons.push('pinned');
  if (ctx.sessionIds?.has(tab.id)) reasons.push('session');
  return reasons;
}

export function recentlyAudible(tab, ctx) {
  const at = ctx.audibleAt?.[tab.id];
  return typeof at === 'number' && ctx.now - at < SOUND_GRACE_MS;
}

export function primaryReason(reasons) {
  for (const r of REASON_ORDER) if (reasons.includes(r)) return r;
  return null;
}

// What pressing Sleep or Close would cost, so the popup asks once first (render 1f).
export function risk(reasons) {
  if (reasons.includes('call')) return 'call';
  if (reasons.includes('screen')) return 'screen';
  if (reasons.includes('typing')) return 'typing';
  return null;
}

// Counts by each tab's main reason, so the counts add up to the tabs held (the link's "held").
export function heldCounts(tabs, ctx) {
  const counts = Object.fromEntries(PROTOCOL_REASONS.map((r) => [r, 0]));
  for (const tab of tabs) {
    if (tab.discarded) continue;
    const p = primaryReason(heldReasons(tab, ctx));
    if (p) counts[p === 'site' ? 'kept' : p] += 1;
  }
  return counts;
}
