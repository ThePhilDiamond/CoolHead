// What the popup shows, built from the tabs and the stored state. Pure, so the worker builds it from Chrome and
// the preview page (dev/preview.html) builds the same thing from made-up data.
import * as W from './words.js';
import { heldReasons, primaryReason, risk, isWebPage, REASON_ORDER } from './reasons.js';
import { currentMemory } from './auto.js';
import { findDuplicates } from './duplicates.js';
import { canSleepOnItsOwn } from './plan.js';
import { suggest } from './session.js';
import { lastUsed } from './usage.js';

const TONE = { fine: 'good', tight: 'warn', slowed: 'warn', veryTight: 'bad' };

// The worker's stored state, turned into the context the rules read.
export function contextFrom(s, tabs, focusedWindowId, now) {
  const front = tabs.find((t) => t.active && t.windowId === focusedWindowId) ?? tabs.find((t) => t.active);
  const anyFrame = (byTab) => Object.fromEntries(
    Object.entries(byTab || {}).map(([id, frames]) => [id, Object.values(frames || {}).reduce(
      (acc, f) => (typeof f === 'object' ? { call: acc.call || !!f.call, screen: acc.screen || !!f.screen } : true),
      {},
    )]).filter(([, v]) => v === true || v.call || v.screen),
  );
  return {
    now,
    level: s.level,
    leaveDelayMs: s.leaveDelayMs,
    use: s.use || {},
    kept: new Set((s.kept || []).map((r) => r.tabId)),
    sessionIds: s.session?.active ? new Set(s.session.tabIds) : null,
    audibleAt: s.audibleAt || {},
    media: anyFrame(s.media),
    typing: anyFrame(s.typing),
    frontTabId: front?.id ?? null,
    focusedWindowId: front?.windowId ?? focusedWindowId ?? null,
  };
}

export function asleepCount(tabs, asleepIds) {
  const ours = new Set(asleepIds || []);
  return tabs.filter((t) => t.discarded && ours.has(t.id)).length;
}

function letterOf(tab) {
  try {
    const host = new URL(tab.url).hostname.replace(/^www\./, '');
    if (host) return host[0].toUpperCase();
  } catch { /* not a URL: fall back to the title */ }
  return (tab.title || '?').trim().charAt(0).toUpperCase() || '?';
}

const TILE_COLORS = ['#7A4FB5', '#2F7D5B', '#3E6FB0', '#B0563E', '#5B6470', '#B23A48', '#2E7D32', '#A0620B', '#6A5ACD', '#1F6F8B'];
function tileColor(tab) {
  let h = 0;
  for (const c of String(tab.url || tab.title || '')) h = (h * 31 + c.charCodeAt(0)) >>> 0;
  return TILE_COLORS[h % TILE_COLORS.length];
}

function face(tab, favicon) {
  return {
    id: tab.id,
    title: tab.title || tab.url || 'Untitled tab',
    favicon: favicon && isWebPage(tab.url) ? favicon(tab.url) : null,
    letter: letterOf(tab),
    color: tileColor(tab),
  };
}

// i: { tabs, s, now, focusedWindowId, isMac, memInfo: {capacity, availableCapacity} | null, version,
//      sitesGranted, managementGranted, favicon: (url) => string }
export function buildView(i) {
  const { tabs, s, now, isMac } = i;
  const ctx = contextFrom(s, tabs, i.focusedWindowId, now);
  const status = s.link?.status || 'connecting';
  const linked = status === 'linked';
  const asleep = asleepCount(tabs, s.asleep);
  const memory = currentMemory(s.link, now);
  const inSession = Boolean(ctx.sessionIds);

  // ---- the top band ----
  let band;
  if (linked) {
    band = {
      tone: memory ? TONE[memory] : 'none',
      melting: Boolean(memory && memory !== 'fine'),
      title: memory ? W.MEMORY_TITLE[memory] : W.LINKED_WAITING_TITLE,
      line: W.asleepLine(asleep),
      link: { state: 'linked', text: W.LINK_TEXT.linked },
    };
  } else if (isMac) {
    const linkState = status === 'notRunning' ? 'notRunning' : status === 'connecting' ? null : 'notLinked';
    band = {
      tone: 'none',
      melting: false,
      title: W.ALONE_TITLE,
      line: asleep > 0 ? `${W.ALONE_LINE_MAC} ${W.asleepLine(asleep)}` : W.ALONE_LINE_MAC,
      link: linkState ? { state: linkState, text: W.LINK_TEXT[linkState] } : null,
    };
  } else {
    // Windows, Linux, and ChromeOS: no Cool Head there (the app is Mac only), so working alone is the whole product.
    // Chrome's own memory reading stands in.
    band = {
      tone: 'none',
      melting: false,
      title: asleep > 0 ? `${W.plural(asleep, 'tab')} asleep` : 'No tabs asleep',
      line: [asleep > 0 ? 'Each wakes when you click it.' : '', i.memInfo ? W.freeLine(i.memInfo.availableCapacity, i.memInfo.capacity) : '']
        .filter(Boolean).join(' '),
      link: null,
    };
  }

  let notice = null;
  if (isMac && !linked && status !== 'connecting' && !inSession) {
    notice = status === 'notRunning'
      ? { text: W.NOTICE_NOT_RUNNING, link: null }
      : { text: W.NOTICE_NOT_LINKED, link: { label: W.GET_COOL_HEAD, aria: W.GET_COOL_HEAD_LABEL, url: W.COOL_HEAD_URL } };
  }

  // ---- kept tabs to find again after a restart ----
  const byId = new Map(tabs.map((t) => [t.id, t]));
  const ordinals = new Map([...new Set(tabs.map((t) => t.windowId))].sort((a, b) => a - b).map((id, n) => [id, n]));
  const questions = (s.keepQuestions || []).map((q, n) => {
    const words = W.keepQuestion(q.record.title || q.record.url, q.candidates.length);
    return {
      key: n,
      title: words.title,
      line: words.line,
      options: q.candidates.filter((id) => byId.has(id)).map((id) => {
        const t = byId.get(id);
        return { tabId: id, label: W.whereIs((ordinals.get(t.windowId) ?? 0) + 1, t.index + 1) };
      }),
    };
  }).filter((q) => q.options.length > 0);

  // ---- the session ----
  let session = null;
  if (inSession) {
    const inIt = tabs.filter((t) => ctx.sessionIds.has(t.id));
    const others = tabs.filter((t) => !ctx.sessionIds.has(t.id) && t.discarded).length;
    session = {
      count: inIt.length,
      asleep: others,
      title: W.sessionTitle(inIt.length, others),
      tabs: inIt.map((t) => face(t, i.favicon)),
      note: W.SESSION_NOTE,
      saveQuestion: W.saveQuestion(inIt.filter((t) => !t.pinned).length),
      defaultName: W.defaultGroupName(new Date(s.session.startedAt || now)),
      endNote: W.endNote(others),
    };
  }

  // ---- held in memory ----
  // During a session, its tabs show only in the session card, not here.
  const heldCtx = { ...ctx, sessionIds: null };
  const held = [];
  for (const t of tabs) {
    if (t.discarded || ctx.sessionIds?.has(t.id)) continue;
    const reasons = heldReasons(t, heldCtx);
    const reason = primaryReason(reasons);
    if (!reason) continue;
    held.push({
      ...face(t, i.favicon),
      reason,
      reasons,
      reasonText: reason === 'sound' && !t.audible ? W.REASON_TEXT.soundRecent : W.REASON_TEXT[reason],
      kept: reasons.includes('kept'),
      pinned: Boolean(t.pinned),
      active: Boolean(t.active),
      risk: risk(reasons),
    });
  }
  held.sort((a, b) => REASON_ORDER.indexOf(a.reason) - REASON_ORDER.indexOf(b.reason) || a.title.localeCompare(b.title));

  // ---- duplicates ----
  const dupGroups = findDuplicates(tabs, ctx);
  const duplicates = dupGroups.length ? W.duplicatesCard(dupGroups) : null;

  // ---- the level ----
  const levels = {
    chosen: s.level,
    label: W.LEVEL_LABEL,
    tone: band.tone,
    options: ['auto', 'light', 'balanced', 'focus']
      .filter((l) => l !== 'auto' || isMac)
      .map((l) => ({ id: l, label: W.LEVEL_NAME[l], what: W.LEVEL_SHORT[l], disabled: l === 'auto' && !linked })),
    line: W.levelLine(s.level, {
      delayMs: s.leaveDelayMs,
      autoMode: s.auto?.mode,
      linked: linked && memory !== null,
      coolHeadAuto: s.link?.state?.auto !== false,
      session: inSession,
    }),
    needs: isMac && !linked && s.level !== 'auto' ? W.AUTO_NEEDS : null,
  };
  // Under the Effort choices, what the level is doing now, only when its row's line doesn't already say it: a session
  // pausing it, or Auto at work, waiting for Cool Head, or turned off there.
  const autoUnusual = s.level === 'auto' && (!(linked && memory !== null) || s.link?.state?.auto === false || (s.auto?.mode && s.auto.mode !== 'off'));
  levels.status = inSession || autoUnusual ? levels.line : null;

  return {
    version: i.version,
    band,
    notice,
    questions,
    session,
    held: { count: held.length, countText: W.plural(held.length, 'tab'), tabs: held },
    duplicates,
    start: { label: W.START, note: W.START_NOTE },
    levels,
    settings: {
      leaveDelayMs: s.leaveDelayMs,
      sitesGranted: Boolean(i.sitesGranted),
      restEnabled: Boolean(s.restEnabled),
      managementGranted: Boolean(i.managementGranted),
      restingText: W.restingNow(s.rest?.ids?.length || 0),
      about: W.about(i.version),
      shortcut: i.shortcut || '',
    },
  };
}

// The Start a session screen: suggestions ticked, the rest unticked, and what unticking each would do, so the
// popup can count what sleeps as the person ticks, without asking the worker each time.
export function buildStart(i) {
  const { tabs, s, now } = i;
  const ctx = contextFrom(s, tabs, i.focusedWindowId, now);
  const { suggested, others } = suggest(tabs, ctx);
  const byId = new Map(tabs.map((t) => [t.id, t]));
  const noSession = { ...ctx, sessionIds: new Set() };
  const row = (r, ticked) => {
    const t = byId.get(r.id);
    let ifUnticked = 'none';
    if (!t.discarded && isWebPage(t.url)) {
      if (canSleepOnItsOwn(t, noSession)) ifUnticked = 'sleep';
      else ifUnticked = t.active ? 'active' : primaryReason(heldReasons(t, noSession)) || 'none';
    }
    return { ...face(t, i.favicon), why: r.why, windowId: t.windowId, ticked, ifUnticked, used: lastUsed(t, ctx.use) ?? 0 };
  };
  const rows = [...suggested.map((r) => row(r, true)), ...others.map((r) => row(r, false))];
  return {
    windowId: ctx.focusedWindowId,
    windowTabs: rows.filter((r) => r.windowId === ctx.focusedWindowId).length,
    suggested: suggested.map((r) => r.id),
    others: others.map((r) => r.id),
    rows,
    resting: Boolean(s.restEnabled),
  };
}
