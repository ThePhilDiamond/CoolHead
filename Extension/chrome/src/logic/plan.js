// Which tabs to put to sleep now. Pure: the worker gathers the tabs and state, then sleeps what this returns,
// checking each tab again just before (it may have changed in between).
import { heldReasons, isWebPage } from './reasons.js';
import { lastUsed, rankMostUsed } from './usage.js';
import { IDLE_MS } from './auto.js';

// Light keeps your 5 most used, Balanced 3, Focus only the tab you're on (README, "How hard it works").
export const KEEP_LOADED = { light: 5, balanced: 3, focus: 1 };
export const LEVELS = ['auto', 'light', 'balanced', 'focus'];
export const LEAVE_DELAYS_MS = [30000, 0];

// A tab may sleep on its own only if it is loaded, a web page, not in front in its window (Chrome refuses
// that, and test T12 found a hidden window's front tab stays blank until shown), not protected by another
// extension or by Chrome's own setting, and held for no reason (call, screen, typing, sound, kept, pinned, session).
export function canSleepOnItsOwn(tab, ctx) {
  if (tab.discarded || tab.active) return false;
  if (!isWebPage(tab.url)) return false;
  if (tab.autoDiscardable === false) return false;
  return heldReasons(tab, ctx).length === 0;
}

function oldestFirst(tabs, use) {
  return [...tabs].sort((a, b) => (lastUsed(a, use) ?? 0) - (lastUsed(b, use) ?? 0));
}

// ctx: { now, level, leaveDelayMs, use, kept, sessionIds, audibleAt, media, typing, frontTabId,
//        autoMode ('off' | 'slowed' | 'veryTight'), autoAllowed (bool) }
export function planSleep(tabs, ctx) {
  const eligible = tabs.filter((t) => canSleepOnItsOwn(t, ctx));

  // During a session everything outside it sleeps at once; the level waits until the session ends.
  if (ctx.sessionIds) return oldestFirst(eligible, ctx.use).map((t) => t.id);

  if (ctx.level === 'auto') {
    if (!ctx.autoAllowed || !IDLE_MS[ctx.autoMode]) return [];
    const idle = IDLE_MS[ctx.autoMode];
    const stale = eligible.filter((t) => {
      const used = lastUsed(t, ctx.use);
      return used == null || ctx.now - used >= idle;
    });
    // One at a time, oldest first: the next reading from Cool Head decides whether another is needed.
    return oldestFirst(stale, ctx.use).slice(0, 1).map((t) => t.id);
  }

  const n = KEEP_LOADED[ctx.level];
  if (!n) return [];
  // Rank the tabs that could sleep, plus the one in front; protected tabs stay loaded anyway and don't take a place.
  const rankable = tabs.filter((t) => t.id === ctx.frontTabId || canSleepOnItsOwn(t, ctx));
  const keep = new Set(rankMostUsed(rankable, ctx.use, ctx.now, ctx.frontTabId).slice(0, n));
  const due = eligible.filter((t) => {
    if (keep.has(t.id)) return false;
    const used = lastUsed(t, ctx.use);
    return used == null || ctx.now - used >= ctx.leaveDelayMs;
  });
  return oldestFirst(due, ctx.use).map((t) => t.id);
}

// When the next check is worth making, so the worker can set one alarm instead of polling: the soonest moment a
// tab that is waiting out the leave delay becomes due. Null if nothing is waiting.
export function nextDueAt(tabs, ctx) {
  if (ctx.sessionIds || ctx.level === 'auto') return null;
  let soonest = null;
  for (const t of tabs) {
    if (!canSleepOnItsOwn(t, ctx)) continue;
    const used = lastUsed(t, ctx.use);
    if (used == null) continue;
    const due = used + ctx.leaveDelayMs;
    if (due > ctx.now && (soonest == null || due < soonest)) soonest = due;
  }
  return soonest;
}

// "Sleep tabs you aren't looking at" (Cool Head's one-click card): every tab that could sleep on its own,
// whatever the level, keeping the protections and the keep list.
export function planSleepHidden(tabs, ctx) {
  return oldestFirst(tabs.filter((t) => canSleepOnItsOwn(t, ctx)), ctx.use).map((t) => t.id);
}
