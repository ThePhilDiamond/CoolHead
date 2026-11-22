// Auto, decided together (PROTOCOL.md, "Auto, decided together"): Cool Head says how the Mac's memory is;
// the extension decides which tabs. fine and tight: nothing. slowed: tabs unused for 30 minutes sleep, one at
// a time, oldest first. veryTight: 5 minutes. Back to nothing after memory has been fine for 5 minutes.
// Without a link, nothing: Auto needs Cool Head and says so.

export const MEMORY_STATES = ['fine', 'tight', 'slowed', 'veryTight'];
export const IDLE_MS = { slowed: 30 * 60 * 1000, veryTight: 5 * 60 * 1000 };
export const CLEAR_AFTER_MS = 5 * 60 * 1000;
// Cool Head sends its state every 10 seconds. Three missed in a row means the link has gone quiet, so the
// extension stops acting on an old reading rather than sleeping tabs on memory that may have cleared.
export const STALE_MS = 35 * 1000;

export const AUTO_OFF = Object.freeze({ mode: 'off', fineSince: null });

export function nextAuto(prev, memory, now) {
  const p = prev || AUTO_OFF;
  if (!MEMORY_STATES.includes(memory)) return AUTO_OFF;
  if (memory === 'veryTight') return { mode: 'veryTight', fineSince: null };
  if (memory === 'slowed') return { mode: 'slowed', fineSince: null };
  if (memory === 'tight') return { mode: p.mode, fineSince: null };
  // fine
  if (p.mode === 'off') return AUTO_OFF;
  const fineSince = p.fineSince ?? now;
  return now - fineSince >= CLEAR_AFTER_MS ? AUTO_OFF : { mode: p.mode, fineSince };
}

// The memory reading to act on, or null when there is no link or its last reading is too old.
export function currentMemory(link, now) {
  if (!link || link.status !== 'linked' || !link.state) return null;
  if (typeof link.stateAt !== 'number' || now - link.stateAt > STALE_MS) return null;
  return MEMORY_STATES.includes(link.state.memory) ? link.state.memory : null;
}

// Whether Auto may act at all: linked, a fresh reading, and the person lets Auto follow Cool Head.
export function autoAllowed(link, now) {
  return currentMemory(link, now) !== null && link.state.auto !== false;
}
