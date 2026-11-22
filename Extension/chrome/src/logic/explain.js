// Words for the test log (src/log.js): why each tab is loaded or asleep at a check, and how a log reads as text.
// Pure, so the tests can run it in Node.
import { canSleepOnItsOwn, KEEP_LOADED } from './plan.js';
import { heldReasons, primaryReason, isWebPage } from './reasons.js';
import { lastUsed, rankMostUsed } from './usage.js';
import { IDLE_MS } from './auto.js';

// A site by host name only: enough to tell tabs apart in a log, without the page's full address.
export function host(url) {
  try {
    const u = new URL(url);
    if (u.protocol === 'file:') return 'a file';
    return u.hostname || u.protocol.replace(':', ' page');
  } catch {
    return 'a page';
  }
}

const LEVEL_NAMES = { auto: 'Auto', light: 'Light', balanced: 'Balanced', focus: 'Focus' };
const REASON_NAMES = {
  call: 'on a call', screen: 'sharing the screen', typing: 'unsent typing', sound: 'playing sound',
  kept: 'kept by you', pinned: 'pinned', session: 'in the session',
};

// Each web page tab sorted into one group, in the order the rules check them.
export function explainCheck(tabs, ctx) {
  const n = { pages: 0, asleep: 0, front: 0, held: {}, chromeKeeps: 0, mostUsed: 0, waiting: 0, notIdle: 0, autoQuiet: 0, due: 0 };
  const web = tabs.filter((t) => isWebPage(t.url));
  const rankable = tabs.filter((t) => t.id === ctx.frontTabId || canSleepOnItsOwn(t, ctx));
  const keepN = KEEP_LOADED[ctx.level] || 0;
  const keep = new Set(rankMostUsed(rankable, ctx.use, ctx.now, ctx.frontTabId).slice(0, keepN));
  const idle = IDLE_MS[ctx.autoMode];
  for (const t of web) {
    n.pages += 1;
    if (t.discarded) { n.asleep += 1; continue; }
    if (t.active) { n.front += 1; continue; }
    const p = primaryReason(heldReasons(t, ctx));
    if (p) { n.held[p] = (n.held[p] || 0) + 1; continue; }
    if (t.autoDiscardable === false) { n.chromeKeeps += 1; continue; }
    const used = lastUsed(t, ctx.use);
    if (ctx.sessionIds) { n.due += 1; continue; }
    if (ctx.level === 'auto') {
      if (!ctx.autoAllowed || !idle) n.autoQuiet += 1;
      else if (used != null && ctx.now - used < idle) n.notIdle += 1;
      else n.due += 1;
      continue;
    }
    if (keep.has(t.id)) { n.mostUsed += 1; continue; }
    if (used != null && ctx.now - used < ctx.leaveDelayMs) { n.waiting += 1; continue; }
    n.due += 1;
  }
  return n;
}

function count(k, one, many = `${one}s`) {
  return `${k} ${k === 1 ? one : many}`;
}

// One sentence for a check, the same sentence while nothing changes, so the log can skip repeats.
export function checkSentence(n, ctx) {
  const level = ctx.sessionIds ? 'Session' : LEVEL_NAMES[ctx.level] || ctx.level;
  const parts = [];
  if (n.front) parts.push(`${n.front} in front`);
  if (n.asleep) parts.push(`${n.asleep} asleep`);
  const held = Object.entries(n.held).map(([r, k]) => `${k} ${REASON_NAMES[r] || r}`);
  if (held.length) parts.push(`held: ${held.join(', ')}`);
  if (n.chromeKeeps) parts.push(`${n.chromeKeeps} kept loaded by Chrome or another extension`);
  if (n.mostUsed) parts.push(`${n.mostUsed} kept as most used`);
  if (n.waiting) parts.push(`${n.waiting} waiting out the delay after you left`);
  if (n.notIdle) parts.push(`${n.notIdle} used too recently for Auto`);
  if (n.autoQuiet) parts.push(`${n.autoQuiet} left alone while memory is fine`);
  if (n.due) parts.push(`${n.due} due to sleep`);
  return `${level}, ${count(n.pages, 'page')}${parts.length ? `: ${parts.join('; ')}` : ''}.`;
}

// 2:15:07pm, the way Cool Head writes times, with seconds for a log.
export function clock(ms) {
  const d = new Date(ms);
  const h = d.getHours();
  const two = (v) => String(v).padStart(2, '0');
  return `${h % 12 || 12}:${two(d.getMinutes())}:${two(d.getSeconds())}${h < 12 ? 'am' : 'pm'}`;
}

export function day(ms) {
  const d = new Date(ms);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

// The log as plain text, oldest first: one line per entry, its data as JSON at the end for a closer look.
export function logText(entries, header = '') {
  const lines = header ? [header] : [];
  for (const e of entries) {
    const data = e.data ? `  ${JSON.stringify(e.data)}` : '';
    lines.push(`${day(e.at)} ${clock(e.at)}  ${e.kind}  ${e.text}${data}`);
  }
  return `${lines.join('\n')}\n`;
}

// How long ago, in a log's words: "40 seconds ago", "12 minutes ago", or "never used" for no record.
export function ago(at, now) {
  if (at == null) return 'never used';
  const s = Math.max(0, Math.round((now - at) / 1000));
  if (s < 90) return `${s} seconds ago`;
  const m = Math.round(s / 60);
  if (m < 90) return `${m} minutes ago`;
  return `${Math.round(m / 60)} hours ago`;
}
