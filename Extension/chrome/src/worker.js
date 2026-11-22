// Cool Head for Chrome's service worker. Chrome may stop it at any moment and start it again for the next event,
// so every handler reads its state from storage (store.js) and nothing depends on a variable surviving.
// The rules themselves are pure functions in logic/, tested in Node; this file only gathers, acts, and records.
import * as store from './store.js';
import * as W from './logic/words.js';
import { planSleep, planSleepHidden, nextDueAt, canSleepOnItsOwn, LEVELS, LEAVE_DELAYS_MS } from './logic/plan.js';
import { recordActivation, pruneUse, replaceId, lastUsed } from './logic/usage.js';
import { nextAuto, autoAllowed, AUTO_OFF } from './logic/auto.js';
import { findDuplicates, duplicateCount } from './logic/duplicates.js';
import { startPlan, join, leave, groupPlan } from './logic/session.js';
import { rematch, keepRecord, windowOrdinals } from './logic/keep.js';
import { restPlan, shouldWake, columns, move } from './logic/extensions.js';
import { heldCounts } from './logic/reasons.js';
import { report, sameReport, reportDue, REPORT_EVERY_MS } from './logic/protocol.js';
import { buildView, buildStart, contextFrom, asleepCount } from './logic/view.js';
import { LinkClient } from './link-client.js';
import * as sites from './sites.js';

const VERSION = chrome.runtime.getManifest().version;
const ALL_SITES = { origins: ['<all_urls>'] };
const MANAGEMENT = { permissions: ['management'] };
const BADGE_BLUE = '#1769D1'; // Cool Head blue; white on it is 5.3:1 (docs/BRAND.md)

// ---------- gathering ----------

async function gather() {
  const [tabs, s, win] = await Promise.all([
    chrome.tabs.query({}),
    store.load(),
    chrome.windows.getLastFocused().catch(() => null),
  ]);
  const now = Date.now();
  return { tabs, s, now, focusedWindowId: win?.id ?? null, ctx: contextFrom(s, tabs, win?.id ?? null, now) };
}

function planCtx(s, ctx, now) {
  return { ...ctx, autoMode: s.auto?.mode || 'off', autoAllowed: autoAllowed(s.link, now) };
}

// ---------- sleeping ----------

// Each tab is checked again just before it sleeps: it may have come to the front or started playing sound
// since the plan was made. Every sleep is chrome.tabs.discard, never a stand-in page, so a tab keeps its place,
// title, and icon, and still works if this extension is removed. Extensions that swap in a page of their own, as The
// Marvellous Suspender does, leave tabs pointing at a page that's gone once the extension is removed or broken.
async function sleepTab(tabId, { force = false } = {}) {
  const t = await chrome.tabs.get(tabId).catch(() => null);
  if (!t || t.active || t.discarded) return null;
  if (!force && t.audible) return null;
  const d = await chrome.tabs.discard(tabId).catch(() => null);
  return d && d.discarded !== false ? d.id : null;
}

async function sleepMany(ids, opts) {
  const slept = [];
  for (const id of ids) {
    const newId = await sleepTab(id, opts);
    if (newId != null) slept.push(newId);
  }
  if (slept.length) {
    await store.change((s) => ({ asleep: [...new Set([...s.asleep, ...slept])] }));
  }
  return slept;
}

let sweepTimer = null;
function sweepSoon(ms) {
  clearTimeout(sweepTimer);
  // setTimeout covers the usual case while the worker is awake; the alarm covers a worker that stopped meanwhile.
  sweepTimer = setTimeout(() => sweep().catch(console.error), Math.max(0, ms));
  chrome.alarms.create('sweep', { when: Date.now() + Math.max(ms, 30000) });
}

async function sweep() {
  const { tabs, s, now, ctx } = await gather();
  const pc = planCtx(s, ctx, now);
  const ids = planSleep(tabs, pc);
  if (ids.length) await sleepMany(ids);
  const due = nextDueAt(tabs, pc);
  if (due != null) sweepSoon(due - Date.now() + 500);
  await refreshBadge();
  await maybeReport();
}

// ---------- the badge and the right-click item ----------

async function refreshBadge() {
  const [tabs, s] = await Promise.all([chrome.tabs.query({}), store.load()]);
  const n = asleepCount(tabs, s.asleep);
  await chrome.action.setBadgeText({ text: n ? String(n) : '' });
  await chrome.action.setBadgeBackgroundColor({ color: BADGE_BLUE });
  await chrome.action.setBadgeTextColor?.({ color: '#FFFFFF' });
  // The badge is a picture; the title is what a screen reader says for the toolbar button.
  await chrome.action.setTitle({ title: `${W.NAME}. ${W.asleepLine(n)}` });
}

function ensureMenu() {
  chrome.contextMenus.removeAll(() => {
    // Install and a new run of Chrome can both ask for the menu at once; the second create is then a duplicate,
    // which is harmless, so its error is read and dropped.
    chrome.contextMenus.create({ id: 'keep', title: W.MENU_KEEP, type: 'checkbox', contexts: ['page', 'frame', 'action'] }, () => void chrome.runtime.lastError);
  });
}

async function refreshMenu(tab) {
  if (!tab) return;
  const s = await store.load();
  const kept = s.kept.some((r) => r.tabId === tab.id);
  // Hidden for a pinned tab, as in the popup: pinned tabs stay loaded already.
  chrome.contextMenus.update('keep', { checked: kept, visible: !tab.pinned }, () => void chrome.runtime.lastError);
}

// ---------- keep ----------

async function setKeep(tabId, on) {
  const tab = await chrome.tabs.get(tabId).catch(() => null);
  if (!tab) return null;
  const all = await chrome.tabs.query({});
  await store.change((s) => {
    const others = s.kept.filter((r) => r.tabId !== tabId);
    return { kept: on ? [...others, keepRecord(tab, windowOrdinals(all))] : others };
  });
  // Also tells Chrome's own Memory Saver to leave it: "stays loaded until you un-keep it" (design, "Keep").
  await chrome.tabs.update(tabId, { autoDiscardable: !on }).catch(() => {});
  await refreshMenu(tab);
  return tab;
}

async function refreshKeptPositions() {
  const tabs = await chrome.tabs.query({});
  const byId = new Map(tabs.map((t) => [t.id, t]));
  const ord = windowOrdinals(tabs);
  await store.change((s) => {
    let changed = false;
    const kept = s.kept.map((r) => {
      const t = byId.get(r.tabId);
      if (!t) return r;
      const next = { ...r, url: t.url, title: t.title || r.title, index: t.index, windowOrdinal: ord.get(t.windowId) ?? r.windowOrdinal };
      if (JSON.stringify(next) !== JSON.stringify(r)) changed = true;
      return next;
    });
    return changed ? { kept } : null;
  });
}

async function findKeptAgain() {
  const tabs = await chrome.tabs.query({});
  await store.change((s) => {
    const pendingRecords = [...s.kept, ...s.keepQuestions.map((q) => q.record)];
    const { kept, questions, lost } = rematch(pendingRecords, tabs);
    // A kept tab that isn't open yet may still be on its way back (Chrome restores windows over a few seconds);
    // it is kept in the list until the check a minute later, then let go.
    const late = Date.now() - (s.runStartedAt || 0) < 60000 ? lost : [];
    return { kept: [...kept, ...late], keepQuestions: questions };
  });
  const s = await store.load();
  for (const r of s.kept) chrome.tabs.update(r.tabId, { autoDiscardable: false }).catch(() => {});
}

// ---------- the session ----------

async function startSession(tabIds) {
  const { tabs, s, now, ctx } = await gather();
  const plan = startPlan(tabs, tabIds, ctx);
  await store.change(() => ({ session: { active: true, tabIds: plan.sessionIds, startedAt: now } }));
  const slept = await sleepMany(plan.sleep);
  if (s.restEnabled) await restExtensions('session');
  await refreshBadge();
  await maybeReport(true);
  return W.DONE.started(plan.sessionIds.length, slept.length);
}

async function endSession(save, name) {
  const s = await store.load();
  if (!s.session?.active) return W.DONE.ended;
  let message = W.DONE.ended;
  if (save) {
    const tabs = await chrome.tabs.query({});
    const plan = groupPlan(tabs, s.session.tabIds);
    const title = (name || '').trim() || W.defaultGroupName(new Date(s.session.startedAt || Date.now()));
    let grouped = 0;
    for (const ids of Object.values(plan.byWindow)) {
      try {
        const groupId = await chrome.tabs.group({ tabIds: ids });
        await chrome.tabGroups.update(groupId, { title });
        grouped += ids.length;
      } catch { /* a window closed meanwhile: its tabs simply aren't grouped */ }
    }
    message = W.DONE.saved(grouped, title, plan.alreadyGrouped.length);
  }
  await store.change(() => ({ session: null }));
  await store.change((st) => ({ rest: { ...st.rest, session: false } }));
  await wakeExtensionsIfDone();
  await maybeReport(true);
  return message;
}

// ---------- rest extensions ----------

async function hasManagement() {
  return chrome.permissions.contains(MANAGEMENT);
}

async function restExtensions(reason) {
  if (!(await hasManagement())) return { ok: false, count: 0, done: W.DONE.restNeedsYes };
  const s = await store.load();
  const exts = await chrome.management.getAll();
  const ids = restPlan(exts, s.safeList, chrome.runtime.id);
  // Recorded before any is turned off, so a worker stopped halfway still knows to turn them back on. Turning on
  // one that was never turned off does nothing, so recording too many is harmless; recording too few isn't.
  await store.change((st) => ({ rest: { ids: [...new Set([...st.rest.ids, ...ids])], session: st.rest.session || reason === 'session', memory: st.rest.memory || reason === 'memory' } }));
  const rested = [];
  for (const id of ids) {
    try {
      await chrome.management.setEnabled(id, false);
      rested.push(id);
    } catch { /* Chrome refused (it may be required by policy): leave it on */ }
  }
  await maybeReport();
  return { ok: true, count: rested.length, done: W.DONE.rested(rested.length) };
}

// Rested extensions come back as soon as no reason to rest is left, so a dropped link or an ended session never
// leaves the person's extensions off.
async function wakeExtensionsIfDone() {
  const s = await store.load();
  if (!shouldWake(s.rest)) return;
  // Without the permission they can't be turned on; the list is kept, so they come back if it is given again.
  if (!(await hasManagement())) return;
  const woken = [];
  for (const id of s.rest.ids) {
    await chrome.management.setEnabled(id, true).catch(() => {});
    woken.push(id);
  }
  // Only the ones turned back on leave the list: a rest that started meanwhile keeps its own.
  await store.change((st) => ({ rest: { ...st.rest, ids: st.rest.ids.filter((id) => !woken.includes(id)) } }));
  await maybeReport();
}

// ---------- the link to Cool Head ----------

const link = new LinkClient({
  connect: (name) => chrome.runtime.connectNative(name),
  lastError: () => chrome.runtime.lastError?.message,
  helloInfo: () => ({ version: VERSION, level: cachedLevel }),
  onStatus: (status, app) => onLinkStatus(status, app).catch(console.error),
  onState: (state) => onLinkState(state),
  onRequest: (req) => onLinkRequest(req),
});
let cachedLevel = 'balanced';

async function onLinkStatus(status, app) {
  const s = await store.change((st) => {
    const patch = { link: { ...st.link, status, app: app || st.link.app } };
    if (status !== 'linked') {
      // Carry on alone, with nothing lost: Auto stops acting on an old reading, the level stays as chosen,
      // and extensions rested because memory was tight come back on.
      patch.link.state = null;
      patch.link.stateAt = null;
      patch.auto = AUTO_OFF;
      patch.rest = { ...st.rest, memory: false };
      // A level the person never chose went to Auto only because Cool Head was there; alone, it goes back, so
      // tabs keep sleeping instead of waiting for Cool Head.
      if (!st.levelChosen && st.level === 'auto') patch.level = 'balanced';
    } else if (!st.levelChosen && st.level !== 'auto') {
      // The person never picked a level: Auto is the better start once Cool Head can say when memory is short.
      patch.level = 'auto';
    }
    return patch;
  });
  cachedLevel = s.level;
  if (status !== 'linked') {
    await wakeExtensionsIfDone();
    if (status === 'notRunning' || status === 'notLinked') scheduleReconnect(10000);
  } else {
    await maybeReport(true);
  }
}

async function onLinkState(state) {
  const now = Date.now();
  let before;
  const s = await store.change((st) => {
    before = st.auto?.mode || 'off';
    return { link: { ...st.link, state, stateAt: now }, auto: nextAuto(st.auto, state.memory, now) };
  });
  const after = s.auto.mode;
  if (after !== before) {
    // Resting on tight memory is part of Auto, and only when the person lets Auto follow Cool Head.
    if (after === 'veryTight' && s.restEnabled && s.level === 'auto' && autoAllowed(s.link, now)) await restExtensions('memory');
    // Memory has cleared: extensions rested for memory come back, whoever asked (Auto or Cool Head's card).
    if (after === 'off') {
      await store.change((st) => ({ rest: { ...st.rest, memory: false } }));
      await wakeExtensionsIfDone();
    }
  }
  // Auto sleeps one tab per reading, oldest first; the next reading, 10 seconds on, decides whether another goes.
  if (s.level === 'auto' && !s.session?.active) await sweep();
  else await maybeReport();
}

async function onLinkRequest({ action }) {
  const { tabs, s, now, ctx } = await gather();
  switch (action) {
    case 'sleepHidden': {
      const slept = await sleepMany(planSleepHidden(tabs, planCtx(s, ctx, now)));
      await refreshBadge();
      return { ok: true, count: slept.length, done: W.DONE.sleptMany(slept.length) };
    }
    case 'closeDuplicates': {
      const n = await closeDuplicates();
      return { ok: true, count: n, done: W.DONE.closedDuplicates(n) };
    }
    case 'hideUnusedGroups':
      return hideUnusedGroups(tabs, ctx);
    case 'restExtensions':
      return restExtensions('memory');
    case 'openExtensionsList':
      await store.save({ popupScreen: 'safe' });
      return openPopup();
    case 'openPopup':
      return openPopup();
    default:
      return { ok: false, count: 0, done: '' };
  }
}

async function openPopup() {
  try {
    await chrome.action.openPopup();
    return { ok: true, count: 0, done: '' };
  } catch {
    return { ok: false, count: 0, done: `Click ${W.NAME} in Chrome's toolbar to open it.` };
  }
}

// "Hide groups not used today": folds each group none of whose tabs was used since midnight and puts its tabs
// to sleep. Folding, not closing: whether Chrome keeps a closed group saved is untested on Chrome 158 (design),
// and folding loses nothing.
async function hideUnusedGroups(tabs, ctx) {
  const midnight = new Date(); midnight.setHours(0, 0, 0, 0);
  const groups = await chrome.tabGroups.query({});
  let folded = 0;
  const toSleep = [];
  for (const g of groups) {
    const inGroup = tabs.filter((t) => t.groupId === g.id);
    if (inGroup.some((t) => t.active || (lastUsed(t, ctx.use) ?? 0) >= midnight.getTime())) continue;
    try {
      await chrome.tabGroups.update(g.id, { collapsed: true });
      folded += 1;
    } catch { continue; }
    toSleep.push(...inGroup.filter((t) => canSleepOnItsOwn(t, ctx)).map((t) => t.id));
  }
  const slept = await sleepMany(toSleep);
  await refreshBadge();
  return { ok: true, count: slept.length, done: W.DONE.foldedGroups(folded, slept.length) };
}

async function closeDuplicates() {
  const { tabs, ctx } = await gather();
  const ids = findDuplicates(tabs, ctx).flatMap((g) => g.closeIds);
  if (ids.length) await chrome.tabs.remove(ids).catch(() => {});
  return ids.length;
}

function scheduleReconnect(ms) {
  setTimeout(() => connectLink().catch(console.error), ms);
}

// The host isn't there on Windows or Linux, or before Cool Head sets up the link, so a missing host is tried again
// only every 5 minutes; a host that is there but lost Cool Head is tried every 10 seconds (and keeps itself
// trying the socket meanwhile, per the protocol).
async function connectLink() {
  if (link.connected) return;
  const s = await store.load();
  const now = Date.now();
  if (s.link.status === 'notInstalled' && s.link.attemptAt && now - s.link.attemptAt < 5 * 60 * 1000) return;
  await store.change((st) => ({ link: { ...st.link, attemptAt: now } }));
  link.start();
}

let reportTimer = null;
async function maybeReport(force = false) {
  if (link.status !== 'linked') return;
  const { tabs, s, now, ctx } = await gather();
  const r = report({
    asleep: asleepCount(tabs, s.asleep),
    held: heldCounts(tabs, ctx),
    session: { active: Boolean(s.session?.active), tabs: s.session?.tabIds?.length || 0 },
    duplicates: duplicateCount(findDuplicates(tabs, ctx)),
    extensionsResting: s.rest.ids.length,
    level: s.level,
  });
  if (!force && sameReport(r, s.lastReport)) return;
  // On change, at most every 10 seconds (protocol, "report").
  if (!force && !reportDue(s.lastReportAt, now)) {
    clearTimeout(reportTimer);
    reportTimer = setTimeout(() => maybeReport().catch(console.error), REPORT_EVERY_MS - (now - s.lastReportAt));
    return;
  }
  if (link.send(r)) await store.save({ lastReport: r, lastReportAt: now });
}

// ---------- a new run of Chrome ----------

// Session storage starts empty with each run of Chrome (and when the extension is reloaded or updated), so a
// missing "run" mark means tab IDs may all have changed: find kept tabs again, end a session that belonged to
// the last run, and bring back any extensions left resting.
let runChecked = null;
function newBrowserRun() {
  // The worker's start and Chrome's onStartup can both call this; one check per worker is enough.
  runChecked ||= checkBrowserRun();
  return runChecked;
}

async function checkBrowserRun() {
  const s = await store.load();
  if (s.run) return;
  await store.save({ run: true, runStartedAt: Date.now() });
  const tabs = await chrome.tabs.query({});
  const live = new Set(tabs.map((t) => t.id));
  await store.change((st) => ({
    session: st.session?.active && st.session.tabIds.some((id) => live.has(id)) ? st.session : null,
    asleep: st.asleep.filter((id) => live.has(id)),
    rest: { ...st.rest, memory: false, session: Boolean(st.session?.active && st.session.tabIds.some((id) => live.has(id))) },
  }));
  await findKeptAgain();
  chrome.alarms.create('find-kept', { delayInMinutes: 1 });
  await wakeExtensionsIfDone();
  await sites.ensure({ injectOpenPages: true });
  ensureMenu();
  await refreshBadge();
}

// ---------- popup messages ----------

async function viewFor() {
  const { tabs, s, now, focusedWindowId } = await gather();
  const [isMac, memInfo, sitesGranted, managementGranted] = await Promise.all([
    chrome.runtime.getPlatformInfo().then((p) => p.os === 'mac'),
    chrome.system.memory.getInfo().catch(() => null),
    chrome.permissions.contains(ALL_SITES),
    hasManagement(),
  ]);
  const view = buildView({ tabs, s, now, focusedWindowId, isMac, memInfo, version: VERSION, sitesGranted, managementGranted, favicon });
  view.openScreen = s.popupScreen;
  if (s.popupScreen) await store.save({ popupScreen: null });
  return view;
}

function favicon(url) {
  // Chrome's own favicon cache, read locally: loading a site's icon from the web would be network use.
  const u = new URL(chrome.runtime.getURL('/_favicon/'));
  u.searchParams.set('pageUrl', url);
  u.searchParams.set('size', '32');
  return u.toString();
}

async function act(m) {
  const tab = m.tabId != null ? await chrome.tabs.get(m.tabId).catch(() => null) : null;
  switch (m.action) {
    case 'level': {
      if (!LEVELS.includes(m.level)) return W.DONE.failed;
      await store.change((s) => ({ level: m.level, levelChosen: true, rest: m.level === 'auto' ? s.rest : { ...s.rest, memory: false } }));
      cachedLevel = m.level;
      await wakeExtensionsIfDone();
      sweepSoon(0);
      return W.DONE.levelSet(m.level);
    }
    case 'keep': {
      if (!tab) return W.DONE.failed;
      await setKeep(m.tabId, m.on);
      await maybeReport();
      return m.on ? W.DONE.kept(tab.title) : W.DONE.unkept(tab.title);
    }
    case 'sleep': {
      if (!tab) return W.DONE.failed;
      // The person chose this tab, so sound and pinning don't stop it; the popup has already asked once about a
      // call or typing.
      const ids = await sleepMany([m.tabId], { force: true });
      await refreshBadge();
      return ids.length ? W.DONE.slept(tab.title) : W.DONE.failed;
    }
    case 'close': {
      if (!tab) return W.DONE.failed;
      await chrome.tabs.remove(m.tabId);
      return W.DONE.closed(tab.title);
    }
    case 'closeDuplicates':
      return W.DONE.closedDuplicates(await closeDuplicates());
    case 'startSession':
      return startSession(m.tabIds || []);
    case 'endSession':
      return endSession(Boolean(m.save), m.name);
    case 'keepAnswer': {
      await store.change((s) => {
        const q = s.keepQuestions[m.key];
        if (!q) return null;
        const keepQuestions = s.keepQuestions.filter((_, n) => n !== m.key);
        const kept = m.tabId != null ? [...s.kept, { ...q.record, tabId: m.tabId }] : s.kept;
        return { keepQuestions, kept };
      });
      if (m.tabId != null) await chrome.tabs.update(m.tabId, { autoDiscardable: false }).catch(() => {});
      await refreshKeptPositions();
      return '';
    }
    case 'leaveDelay':
      if (!LEAVE_DELAYS_MS.includes(m.ms)) return W.DONE.failed;
      await store.change(() => ({ leaveDelayMs: m.ms }));
      return '';
    case 'sites':
      // The popup asks Chrome for the permission itself (Chrome needs the person's click); this only follows it.
      if (!m.on) await chrome.permissions.remove(ALL_SITES).catch(() => {});
      await sites.ensure();
      await store.change(() => ({ setupDone: true }));
      return '';
    case 'restEnabled':
      await store.change(() => ({ restEnabled: Boolean(m.on) }));
      if (!m.on) {
        await store.change((s) => ({ rest: { ...s.rest, session: false, memory: false } }));
        await wakeExtensionsIfDone();
      }
      return '';
    case 'safeMove':
      await store.change((s) => ({ safeList: move(s.safeList, m.id, m.toAlwaysOn) }));
      return '';
    case 'openCoolHead':
      await chrome.tabs.create({ url: W.COOL_HEAD_URL });
      return '';
    default:
      return W.DONE.failed;
  }
}

async function safeColumns() {
  if (!(await hasManagement())) return null;
  const [exts, s] = await Promise.all([chrome.management.getAll(), store.load()]);
  return columns(exts, s.safeList, chrome.runtime.id);
}

chrome.runtime.onMessage.addListener((m, sender, reply) => {
  // The popup and the setup page are the extension's own pages; anything else in a tab is a content script.
  const ownPage = sender.id === chrome.runtime.id && typeof sender.url === 'string' && sender.url.startsWith(chrome.runtime.getURL(''));
  // From web pages: only the two content scripts' yes-or-no reports, keyed by the sender's own tab and frame.
  if (!ownPage && sender.tab && sender.id === chrome.runtime.id && (m?.type === 'typing' || m?.type === 'media')) {
    const tabId = sender.tab.id;
    const frame = String(sender.frameId ?? 0);
    const key = m.type;
    store.change((s) => {
      // Most pages report "nothing" when they start; with nothing on record, there is nothing to write.
      const off = key === 'typing' ? !m.dirty : !(m.call || m.screen);
      if (off && !s[key]?.[tabId]?.[frame]) return null;
      const byTab = { ...(s[key] || {}) };
      const frames = { ...(byTab[tabId] || {}) };
      if (key === 'typing') { if (m.dirty) frames[frame] = true; else delete frames[frame]; }
      else if (m.call || m.screen) frames[frame] = { call: Boolean(m.call), screen: Boolean(m.screen) };
      else delete frames[frame];
      if (Object.keys(frames).length) byTab[tabId] = frames; else delete byTab[tabId];
      return { [key]: byTab };
    }).then(() => maybeReport()).catch(console.error);
    return false;
  }
  if (!ownPage) return false;
  (async () => {
    switch (m?.type) {
      case 'view': return viewFor();
      case 'start': {
        const { tabs, s, now, focusedWindowId } = await gather();
        return buildStart({ tabs, s, now, focusedWindowId, favicon });
      }
      case 'safe': return safeColumns();
      case 'act': {
        const said = await act(m);
        await refreshBadge();
        await maybeReport();
        return { said, view: await viewFor() };
      }
      default: return null;
    }
  })().then(reply, (e) => reply({ error: String(e?.message || e) }));
  return true; // replies later
});

// ---------- Chrome's events ----------

chrome.tabs.onActivated.addListener(({ tabId, windowId }) => {
  const now = Date.now();
  store.change((s) => {
    const prev = s.activeByWindow[windowId];
    return {
      use: recordActivation(s.use, tabId, prev, now),
      activeByWindow: { ...s.activeByWindow, [windowId]: tabId },
      session: join(s.session, tabId),
      asleep: s.asleep.filter((id) => id !== tabId),
    };
  }).then(async (s) => {
    chrome.tabs.get(tabId).then(refreshMenu).catch(() => {});
    sweepSoon(s.leaveDelayMs + 250);
    await refreshBadge();
  }).catch(console.error);
});

chrome.tabs.onCreated.addListener((tab) => {
  const now = Date.now();
  store.change((s) => ({
    // A tab you open during a session joins it (design, "Sessions").
    session: s.session?.active ? join(s.session, tab.id) : s.session,
    // Opening a tab counts as using it, so one opened in the background isn't taken for long idle and put to
    // sleep while it is still loading.
    use: s.use[tab.id] ? s.use : { ...s.use, [tab.id]: { last: null, left: now, switches: [] } },
  })).catch(console.error);
});

chrome.tabs.onRemoved.addListener((tabId, info) => {
  store.change((s) => {
    const drop = (map) => { const n = { ...map }; delete n[tabId]; return n; };
    return {
      use: drop(s.use), audibleAt: drop(s.audibleAt), media: drop(s.media), typing: drop(s.typing),
      session: leave(s.session, tabId),
      asleep: s.asleep.filter((id) => id !== tabId),
      // A kept tab closing with its window may be Chrome quitting: keep the record so it can be found after the
      // restart. A kept tab closed on its own was closed on purpose.
      kept: info.isWindowClosing ? s.kept : s.kept.filter((r) => r.tabId !== tabId),
    };
  }).then(() => refreshBadge()).then(() => maybeReport()).catch(console.error);
});

// Chrome can swap a tab for a new one with a new ID (when it unloads or prerenders a page). Everything
// recorded about the old ID moves to the new one.
chrome.tabs.onReplaced.addListener((addedId, removedId) => {
  store.change((s) => {
    const swap = (id) => (id === removedId ? addedId : id);
    return {
      use: replaceId(s.use, removedId, addedId),
      audibleAt: replaceId(s.audibleAt, removedId, addedId),
      media: replaceId(s.media, removedId, addedId),
      typing: replaceId(s.typing, removedId, addedId),
      activeByWindow: Object.fromEntries(Object.entries(s.activeByWindow).map(([w, id]) => [w, swap(id)])),
      session: s.session ? { ...s.session, tabIds: s.session.tabIds.map(swap) } : null,
      asleep: [...new Set(s.asleep.map(swap))],
      kept: s.kept.map((r) => ({ ...r, tabId: swap(r.tabId) })),
    };
  }).catch(console.error);
});

chrome.tabs.onUpdated.addListener((tabId, change, tab) => {
  const now = Date.now();
  const touches = 'audible' in change || 'url' in change || 'discarded' in change;
  if (touches) {
    store.change((s) => {
      const patch = {};
      // When sound stops is what matters: a quiet call stays protected for 10 minutes after (logic/reasons.js).
      // Chrome can also say audible: false for a tab that never played anything; only a tab that played counts.
      if (change.audible === true || (change.audible === false && tabId in s.audibleAt)) {
        patch.audibleAt = { ...s.audibleAt, [tabId]: now };
      }
      if ('url' in change) {
        // Typing and calls are not cleared here: a page can change its address without reloading (Gmail, Slack),
        // keeping its draft or call. Each new document's content script reports its own state when it starts.
        patch.kept = s.kept.map((r) => (r.tabId === tabId ? { ...r, url: change.url, title: tab.title || r.title } : r));
      }
      if (change.discarded === true) {
        // An unloaded page has no typing or call left; holding on to them would keep the tab held after it wakes.
        const typing = { ...s.typing }; delete typing[tabId];
        const media = { ...s.media }; delete media[tabId];
        patch.typing = typing;
        patch.media = media;
      }
      if (change.discarded === false) patch.asleep = s.asleep.filter((id) => id !== tabId);
      return patch;
    }).then(() => refreshBadge()).then(() => maybeReport()).catch(console.error);
  }
  if ('pinned' in change && tab.active) refreshMenu(tab).catch(() => {});
});

chrome.tabs.onMoved.addListener(() => refreshKeptPositions().catch(console.error));
chrome.tabs.onAttached.addListener(() => refreshKeptPositions().catch(console.error));

chrome.contextMenus.onClicked.addListener((info, tab) => {
  if (info.menuItemId !== 'keep' || !tab) return;
  // From the stored state, not the menu's tick, which can be out of date after a switch between windows.
  store.load().then((s) => setKeep(tab.id, !s.kept.some((r) => r.tabId === tab.id))).then(() => maybeReport()).catch(console.error);
});

chrome.windows.onFocusChanged.addListener((windowId) => {
  if (windowId === chrome.windows.WINDOW_ID_NONE) return;
  chrome.tabs.query({ active: true, windowId }).then(([t]) => refreshMenu(t)).catch(() => {});
});

chrome.alarms.onAlarm.addListener((a) => {
  if (a.name === 'tick') {
    // Cool Head sends a reading every 10 seconds; if none has come for 35, act as if the link dropped.
    store.load().then(async (s) => {
      if (s.link.status === 'linked' && !autoAllowed(s.link, Date.now()) && s.auto.mode !== 'off') {
        await store.change((st) => ({ auto: AUTO_OFF, rest: { ...st.rest, memory: false } }));
        await wakeExtensionsIfDone();
      }
      await connectLink();
      await sweep();
    }).catch(console.error);
  } else if (a.name === 'sweep') {
    sweep().catch(console.error);
  } else if (a.name === 'find-kept') {
    findKeptAgain().catch(console.error);
  }
});

chrome.permissions.onAdded.addListener(() => sites.ensure().catch(console.error));
chrome.permissions.onRemoved.addListener(() => sites.ensure().catch(console.error));

chrome.runtime.onInstalled.addListener(async ({ reason }) => {
  ensureMenu();
  await sites.ensure();
  if (reason === 'install') {
    // Asked at setup, with the cost of saying no; never assumed.
    chrome.tabs.create({ url: chrome.runtime.getURL('setup/setup.html') });
  }
});

// Chrome itself started (not just this worker or the extension): tab IDs from the last run mean nothing now, and
// Chrome can hand the same numbers out again, so the last run's session and asleep list end here outright.
chrome.runtime.onStartup.addListener(() => {
  newBrowserRun()
    .then(() => store.change((s) => ({ session: null, asleep: [], rest: { ...s.rest, session: false, memory: false } })))
    .then(() => wakeExtensionsIfDone())
    .then(() => refreshBadge())
    .catch(console.error);
});

// ---------- every time the worker starts ----------

chrome.alarms.get('tick').then((a) => { if (!a) chrome.alarms.create('tick', { periodInMinutes: 1 }); });
store.load().then((s) => { cachedLevel = s.level; }).catch(() => {});
newBrowserRun().then(() => connectLink()).catch(console.error);

// For the browser tests (test/browser/run.mjs), which drive the worker through Chrome's debugging protocol.
globalThis.coolHead = { sweep, gather, act, store, link, viewFor };
