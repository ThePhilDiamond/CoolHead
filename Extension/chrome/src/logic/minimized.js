// Minimized windows. A minimized window's front tab is out of sight like any tab behind another, so it may sleep by
// the same rules (25 November 2026, tests T20 to T23 in the research notes): Chrome unloads it when asked, and its
// renderer goes. Only minimized, never a window that's merely not focused: Chrome would unload that window's front
// tab too (T21), but it may be on screen beside the one in use, and its page would go blank in view.
//
// Bringing the window back: with Chrome's older unloading the tab reloads by itself (T22); with in-place unloading
// (the tab keeps its ID) it stays blank until reloaded (T23), so the worker reloads it, at once when it knows the
// unloading was in place, and after a short wait otherwise if it's still blank. Pure: the worker passes the state in.

// The tab in front of a window that's on screen: the one tab Chrome won't let sleep in a window in use, and the one
// the person may be looking at. A minimized window's front tab isn't.
export function inFront(tab, ctx) {
  return Boolean(tab.active) && !(ctx?.minimized?.has(tab.windowId));
}

// How long a front tab, slept in a minimized window by Chrome's older unloading, may stay blank after its window comes
// back before the worker reloads it: Chrome reloaded it in about 0.6 seconds in T22.
export const RESTORE_CHECK_MS = 3000;

// What changes when windows are seen minimized or back: a window newly minimized counts as its front tab being left
// then (so its idle time starts there, as when a tab is switched away from); a window back from being minimized counts
// as its front tab in use again. windows: [{ id, state }]; fronts: { windowId: tabId }; minimizedAt: { windowId: ts }.
// Returns the new minimizedAt and use, or null when nothing changed.
export function noteWindows(windows, fronts, minimizedAt, use, now) {
  const at = { ...(minimizedAt || {}) };
  let u = use || {};
  let changed = false;
  const seen = new Set();
  for (const w of windows) {
    seen.add(String(w.id));
    const front = fronts[w.id];
    if (w.state === 'minimized' && at[w.id] == null) {
      at[w.id] = now;
      changed = true;
      if (front != null) u = { ...u, [front]: { last: null, switches: [], ...u[front], left: now } };
    } else if (w.state !== 'minimized' && at[w.id] != null) {
      delete at[w.id];
      changed = true;
      if (front != null) u = { ...u, [front]: { left: null, switches: [], ...u[front], last: now } };
    }
  }
  for (const id of Object.keys(at)) if (!seen.has(id)) { delete at[id]; changed = true; }    // closed windows
  return changed ? { minimizedAt: at, use: u } : null;
}

// When windows are seen: which front tabs to wake, and the records left. A front tab of a window on screen that's
// still blank is woken whether or not there's a record of sleeping it: the record can be missing (written after the
// window came back, or lost when the extension updated) or the tab slept by another path, and a blank page in a window
// on screen is never wanted. The record only says how soon: at once when the worker knows the unloading was in place
// (Chrome won't reload it), otherwise after RESTORE_CHECK_MS, by which time Chrome has reloaded it if it's going to.
// A front tab that's loading or loaded is in use and never woken, so a reload can't lose what's typed in it; its
// record is dropped. windows: [{ id, state, front: { id, status, discarded } }]. Returns { wake: [{ id, what }],
// frontAsleep }, frontAsleep only when it changed.
export function restorePlan(windows, frontAsleep) {
  const records = { ...(frontAsleep || {}) };
  const wake = [];
  let changed = false;
  for (const w of windows) {
    const f = w.front;
    if (w.state === 'minimized' || !f) continue;
    const what = onRestore(records, f.id);
    if (what) { delete records[f.id]; changed = true; }
    if (f.status === 'unloaded' || f.discarded) wake.push({ id: f.id, what: what || 'check' });
  }
  return changed ? { wake, frontAsleep: records } : { wake };
}

// What to do for a window's front tab when the window comes back: 'reload' at once (the worker slept it in place, so
// Chrome won't reload it), 'check' after RESTORE_CHECK_MS (slept the older way: Chrome should reload it itself), or
// null (the worker didn't sleep it as a minimized window's front tab).
export function onRestore(frontAsleep, tabId) {
  const f = frontAsleep?.[tabId];
  if (!f) return null;
  return f.inPlace ? 'reload' : 'check';
}
