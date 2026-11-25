// Sessions (journey 1, the meeting): the last 30 minutes don't say what a meeting needs; the person does, in
// about ten seconds, if asked once. So Start a session suggests, and the person ticks.
import { heldReasons, isWebPage, primaryReason } from './reasons.js';
import { lastUsed } from './usage.js';
import { canSleepOnItsOwn } from './plan.js';
import { inFront } from './minimized.js';
import { usedAgo, WHY } from './words.js';

// Tabs used in the last 10 minutes are suggested (design, "Sessions").
export const RECENT_MS = 10 * 60 * 1000;

function listed(tab, ctx) {
  return isWebPage(tab.url) || tab.id === ctx.frontTabId;
}

// Returns { suggested: [{id, why}], others: [{id, why}] }; suggested ones start ticked.
// ctx: { now, use, kept, media, audibleAt, typing, frontTabId }
export function suggest(tabs, ctx) {
  const suggested = [];
  const others = [];
  const rank = { active: 0, call: 1, screen: 2, sound: 3, kept: 4, recent: 5 };
  for (const t of tabs) {
    if (!listed(t, ctx)) continue;
    const reasons = heldReasons(t, { ...ctx, sessionIds: null });
    const used = lastUsed(t, ctx.use);
    const ago = used == null ? null : ctx.now - used;
    let kind = null;
    if (t.id === ctx.frontTabId) kind = 'active';
    else if (reasons.includes('call')) kind = 'call';
    else if (reasons.includes('screen')) kind = 'screen';
    else if (reasons.includes('sound') && t.audible) kind = 'sound';
    else if (reasons.includes('kept')) kind = 'kept';
    else if (ago != null && ago < RECENT_MS) kind = 'recent';
    const row = { id: t.id, windowId: t.windowId, used: used ?? 0, kind, why: kind && kind !== 'recent' ? WHY[kind] : usedAgo(ago) };
    (kind ? suggested : others).push(row);
  }
  suggested.sort((a, b) => rank[a.kind] - rank[b.kind] || b.used - a.used);
  others.sort((a, b) => b.used - a.used);
  return { suggested, others };
}

// "This window only" means use only this window: tick its tabs, untick the rest.
export function windowOnly(rows, windowId) {
  return new Set(rows.filter((r) => r.windowId === windowId).map((r) => r.id));
}

// What starting would do: which tabs sleep, and which unticked tabs stay loaded and why, so the popup can say
// so before Start is pressed.
export function startPlan(tabs, tickedIds, ctx) {
  const sessionIds = new Set(tickedIds);
  const inner = { ...ctx, sessionIds };
  const sleep = [];
  const stayLoaded = [];
  for (const t of tabs) {
    if (sessionIds.has(t.id) || t.discarded || !isWebPage(t.url)) continue;
    if (canSleepOnItsOwn(t, inner)) sleep.push(t.id);
    else if (inFront(t, inner)) stayLoaded.push({ id: t.id, reason: 'active' });
    else {
      const r = primaryReason(heldReasons(t, inner));
      if (r) stayLoaded.push({ id: t.id, reason: r });
    }
  }
  return { sessionIds: [...sessionIds], sleep, stayLoaded };
}

// Any tab you open or switch to during a session joins it.
export function join(session, tabId) {
  if (!session?.active || session.tabIds.includes(tabId)) return session;
  return { ...session, tabIds: [...session.tabIds, tabId] };
}

export function leave(session, tabId) {
  if (!session?.active || !session.tabIds.includes(tabId)) return session;
  return { ...session, tabIds: session.tabIds.filter((id) => id !== tabId) };
}

// Saving the session as a group: one group per window under the same name, since moving a tab between windows
// (a call, say) to group it would disturb what the person is doing. Pinned tabs can't be grouped. A tab already
// in a group stays in its own group, so nothing the person set up is undone.
export function groupPlan(tabs, sessionIds) {
  const ids = new Set(sessionIds);
  const byWindow = {};
  const alreadyGrouped = [];
  const pinned = [];
  for (const t of tabs) {
    if (!ids.has(t.id)) continue;
    if (t.pinned) pinned.push(t.id);
    else if (typeof t.groupId === 'number' && t.groupId !== -1) alreadyGrouped.push(t.id);
    else (byWindow[t.windowId] ||= []).push(t.id);
  }
  return { byWindow, alreadyGrouped, pinned };
}
