// Cool Head for Chrome's service worker. Chrome may stop it at any moment and start it again for the next event,
// so every handler reads its state from storage (store.js) and nothing depends on a variable surviving.
// The rules themselves are pure functions in logic/, tested in Node; this file only gathers, acts, and records.
import * as store from './store.js';
import * as W from './logic/words.js';
import { planSleep, planSleepHidden, nextDueAt, canSleepOnItsOwn, LEVELS, LEAVE_DELAYS_MS } from './logic/plan.js';
import { recordActivation, pruneUse, replaceId, lastUsed, tabToShowInstead } from './logic/usage.js';
import { nextAuto, autoAllowed, AUTO_OFF, currentMemory } from './logic/auto.js';
import { toolbarLevel, drawToolbarIcon, ICON_STYLES } from './logic/toolbar-icon.js';
import { findDuplicates, duplicateCount } from './logic/duplicates.js';
import { startPlan, join, leave, groupPlan } from './logic/session.js';
import { rematch, keepRecord, windowOrdinals } from './logic/keep.js';
import { restPlan, shouldWake, columns, move, withOpenTabs } from './logic/extensions.js';
import { migrationPlan, suspenders, suspendedAt } from './logic/migrate.js';
import { heldCounts, siteOf, siteRuleFor, heldReasons, risk } from './logic/reasons.js';
import { savable, defaultWords, cleanWords, folderTitle, dayText, splitParent, urlsIn, pagesIn } from './logic/windows.js';
import { report, sameReport, reportDue, REPORT_EVERY_MS } from './logic/protocol.js';
import { buildView, buildStart, contextFrom, asleepCount } from './logic/view.js';
import { LinkClient } from './link-client.js';
import * as sites from './sites.js';
import { log, oops, testBuild } from './log.js';
import { host, explainCheck, checkSentence, ago } from './logic/explain.js';
import { SLEEP_MARK, withRealTitle, markInPage, unmarkInPage } from './logic/mark.js';

const VERSION = chrome.runtime.getManifest().version;
const ALL_SITES = { origins: ['<all_urls>'] };
const MANAGEMENT = { permissions: ['management'] };
const BOOKMARKS = { permissions: ['bookmarks'] };

// ---------- gathering ----------

// Every tab this worker looks at comes through these two, with the page's own title: a sleeping tab's title starts with
// Cool Head's mark (logic/mark.js), which must never reach a bookmark, a list in the popup, or a kept tab's record.
function tabsNow(query) { return chrome.tabs.query(query).then((tabs) => tabs.map(withRealTitle)); }
function tabNow(tabId) { return chrome.tabs.get(tabId).then(withRealTitle); }

async function gather() {
  const [tabs, s, win] = await Promise.all([
    tabsNow({}),
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
// since the plan was made. Every sleep is chrome.tabs.discard, never a stand-in page, so a tab keeps its place and
// icon, and its title with "zzZ" before it (logic/mark.js), and still works if this extension is removed. Extensions that swap in a page of their own, as The
// Marvellous Suspender does, leave tabs pointing at a page that's gone once the extension is removed or broken.
// Tabs this worker is unloading right now, so the test log can tell its own sleeps from Chrome's.
const unloading = new Set();

// shown: the page's title when Chrome doesn't know it yet (a tab put to sleep as it opens).
async function sleepTab(tabId, { force = false, shown = '' } = {}) {
  const t = await tabNow(tabId).catch(() => null);
  if (!t) return { why: 'it closed meanwhile' };
  if (t.active) return { why: 'it came to the front', t };
  if (t.discarded) return { why: 'it was already asleep', t };
  if (!force && t.audible) return { why: 'it started playing sound', t };
  marking.add(tabId);
  try {
    await titleMark(tabId, true, shown || t.title);
    // Marking can take up to a second on a busy page, and Chrome unloads even the tab in front, so the checks above
    // are made again; a tab that stays awake gets its own title back.
    const now = await tabNow(tabId).catch(() => null);
    const why = !now ? 'it closed meanwhile' : now.discarded ? 'it was already asleep' : now.active ? 'it came to the front'
      : (!force && now.audible) ? 'it started playing sound' : null;
    if (why) {
      if (now && !now.discarded) await titleMark(tabId, false);
      return { why, t };
    }
    unloading.add(tabId);
    setTimeout(() => unloading.delete(tabId), 5000);
    const d = await chrome.tabs.discard(tabId).catch(() => null);
    if (d && d.discarded !== false) return { id: d.id, t };
    // still awake, so its title goes back to the page's own
    await titleMark(tabId, false);
    return { why: 'Chrome refused', t };
  } finally {
    marking.delete(tabId);
  }
}

// Tabs being marked and put to sleep right now, so the start-up check below leaves their mark alone.
const marking = new Set();

// A mark on a tab that's awake: left by a worker that stopped between marking a tab and putting it to sleep (an
// update, or Chrome ending the worker). It comes off each time the worker starts.
async function unmarkAwake() {
  const awake = await chrome.tabs.query({ discarded: false });
  for (const t of awake) {
    if (t.title?.includes(SLEEP_MARK) && !marking.has(t.id)) await titleMark(t.id, false);
  }
}

// Puts Cool Head's mark before the title of a tab about to sleep, or takes it off one that didn't (logic/mark.js).
// It needs access to the site, which the person gives for typing and calls; without it, or on a page no extension may
// change (Chrome's own pages, the Web Store), the tab sleeps unmarked. A page that doesn't answer within a second
// sleeps unmarked too, so a stuck page never holds up sleeping.
// `shown` is the title Chrome shows now, for a page with no title of its own.
async function titleMark(tabId, on, shown = '') {
  const run = chrome.scripting.executeScript({ target: { tabId }, injectImmediately: true, func: on ? markInPage : unmarkInPage, args: on ? [SLEEP_MARK, shown] : [SLEEP_MARK] })
    .then((r) => r?.[0]?.result === true).catch(() => false);
  return Promise.race([run, new Promise((res) => setTimeout(() => res(false), 1000))]);
}

// opts.why(tab): the test log's reason for each sleep.
async function sleepMany(ids, opts = {}) {
  const slept = [];
  for (const id of ids) {
    const r = await sleepTab(id, opts);
    const site = r.t ? host(r.t.url) : 'a tab';
    if (r.id != null) {
      slept.push(r.id);
      log('slept', `Slept ${site}: ${opts.why ? opts.why(r.t) : 'asked'}`, { tab: r.id });
    } else {
      log('spared', `Didn't sleep ${site}: ${r.why}`, { tab: id });
    }
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
  sweepTimer = setTimeout(() => sweep().catch(oops), Math.max(0, ms));
  chrome.alarms.create('sweep', { when: Date.now() + Math.max(ms, 30000) });
}

// The last check's sentence in the test log, so an unchanged check isn't written again every minute.
let lastCheck = '';

async function sweep() {
  const { tabs, s, now, ctx } = await gather();
  const pc = planCtx(s, ctx, now);
  if (testBuild) {
    const sentence = checkSentence(explainCheck(tabs, pc), pc);
    if (sentence !== lastCheck) { lastCheck = sentence; log('check', sentence); }
  }
  // While Chrome is offline a sleeping tab couldn't reload, so nothing sleeps on its own (Settings, Offline).
  const held = s.offlineHold !== false && self.navigator.onLine === false;
  const ids = held ? [] : planSleep(tabs, pc);
  if (ids.length) await sleepMany(ids, { why: (t) => sleepWhy(pc, t, now) });
  const due = nextDueAt(tabs, pc);
  if (due != null) sweepSoon(due - Date.now() + 500);
  await refreshBadge();
  await maybeReport();
}

function sleepWhy(pc, t, now) {
  const used = `last used ${ago(lastUsed(t, pc.use), now)}`;
  if (pc.sessionIds) return `outside the session, ${used}`;
  if (pc.level === 'auto') return `Auto with memory ${pc.autoMode}, ${used}`;
  return `${pc.level}, not among the most used, ${used}`;
}

// ---------- the badge and the right-click item ----------

// The toolbar icon, like Cool Head's menu bar icon: the melting snowflake with a badge for memory's level (see
// logic/toolbar-icon.js), redrawn only when the level or the toolbar's light or dark changes. No number on it: a count
// of tabs asleep says nothing about whether to act, so it's in the title and the popup instead.
let iconKey = null;
async function refreshBadge() {
  const [tabs, s] = await Promise.all([tabsNow({}), store.load()]);
  const n = asleepCount(tabs, s.asleep);
  const memory = currentMemory(s.link, Date.now());
  const level = toolbarLevel(memory);
  const style = ICON_STYLES.includes(s.iconStyle) ? s.iconStyle : 'badge';
  const key = `${level}|${s.toolbarDark ? 'dark' : 'light'}|${style}`;
  if (key !== iconKey && typeof OffscreenCanvas === 'function') {
    const imageData = {};
    for (const size of [16, 32]) {
      const c = new OffscreenCanvas(size, size);
      const ctx = c.getContext('2d');
      drawToolbarIcon(ctx, size, level, Boolean(s.toolbarDark), style);
      imageData[size] = ctx.getImageData(0, 0, size, size);
    }
    await chrome.action.setIcon({ imageData }).then(() => { iconKey = key; }, () => {});
  }
  await chrome.action.setBadgeText({ text: '' });
  // The badge is a picture; the title is what a screen reader says for the toolbar button.
  await chrome.action.setTitle({ title: `${W.NAME}. ${memory ? `${W.MEMORY_TITLE[memory]}. ` : ''}${W.asleepLine(n)}` });
}

function ensureMenu() {
  chrome.contextMenus.removeAll(() => {
    // Install and a new run of Chrome can both ask for the menu at once; the second create is then a duplicate,
    // which is harmless, so its error is read and dropped.
    chrome.contextMenus.create({ id: 'keep', title: W.MENU_KEEP, type: 'checkbox', contexts: ['page', 'frame', 'action'] }, () => void chrome.runtime.lastError);
    chrome.contextMenus.create({ id: 'site', title: W.menuSite('this site'), type: 'checkbox', contexts: ['page', 'frame', 'action'] }, () => void chrome.runtime.lastError);
    // The test build only: the Log page, from the toolbar button's right-click menu.
    if (testBuild) chrome.contextMenus.create({ id: 'log', title: 'Open the test log', contexts: ['action'] }, () => void chrome.runtime.lastError);
  });
}

async function refreshMenu(tab) {
  if (!tab) return;
  const s = await store.load();
  const kept = s.kept.some((r) => r.tabId === tab.id);
  // Hidden for a pinned tab, as in the popup: pinned tabs stay loaded already.
  chrome.contextMenus.update('keep', { checked: kept, visible: !tab.pinned }, () => void chrome.runtime.lastError);
  // The site's own name in the item, for web pages only.
  const host = siteOf(tab.url);
  chrome.contextMenus.update('site', { title: W.menuSite(host || 'this site'), checked: Boolean(siteRuleFor(tab.url, s.keepSites)), visible: Boolean(host) }, () => void chrome.runtime.lastError);
}

// ---------- keep ----------

async function setKeep(tabId, on) {
  const tab = await tabNow(tabId).catch(() => null);
  if (!tab) return null;
  const all = await tabsNow({});
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
  const tabs = await tabsNow({});
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
  const tabs = await tabsNow({});
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
  const slept = await sleepMany(plan.sleep, { why: () => 'outside the session you started' });
  log('you', `Started a session with ${plan.sessionIds.length} tabs; ${slept.length} slept`);
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
    const tabs = await tabsNow({});
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
  log('you', save ? `Ended the session and saved it as a group` : 'Ended the session');
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
  const [exts, tabs] = await Promise.all([chrome.management.getAll(), tabsNow({})]);
  const open = withOpenTabs(tabs);
  const ids = restPlan(exts, s.safeList, chrome.runtime.id, open);
  const spared = restPlan(exts, s.safeList, chrome.runtime.id).filter((id) => !ids.includes(id));
  if (spared.length) log('rest', `Left on ${exts.filter((e) => spared.includes(e.id)).map((e) => e.name).join(', ')}: its tabs are open`);
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
  const names = exts.filter((e) => rested.includes(e.id)).map((e) => e.name);
  log('rest', `Turned off ${rested.length} of ${ids.length} extensions (${reason === 'session' ? 'a session' : 'memory'})${names.length ? `: ${names.join(', ')}` : ''}`);
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
  if (woken.length) log('rest', `Turned ${woken.length} extensions back on`);
  // Only the ones turned back on leave the list: a rest that started meanwhile keeps its own.
  await store.change((st) => ({ rest: { ...st.rest, ids: st.rest.ids.filter((id) => !woken.includes(id)) } }));
  await maybeReport();
}

// ---------- the link to Cool Head ----------

const link = new LinkClient({
  connect: (name) => chrome.runtime.connectNative(name),
  lastError: () => chrome.runtime.lastError?.message,
  helloInfo: () => ({ version: VERSION, level: cachedLevel }),
  onStatus: (status, app) => onLinkStatus(status, app).catch(oops),
  onState: (state) => onLinkState(state),
  onRequest: (req) => onLinkRequest(req),
});
let cachedLevel = 'balanced';

async function onLinkStatus(status, app) {
  const s = await store.change((st) => {
    if (st.link.status !== status) log('link', `Link to Cool Head: ${status}${app ? ` (${app})` : ''}`);
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
    if (st.link.state?.memory !== state.memory || st.link.state?.auto !== state.auto) {
      log('memory', `Cool Head says memory is ${state.memory}${state.auto === false ? ', and Auto may not follow it' : ''}`, state);
    }
    return { link: { ...st.link, state, stateAt: now }, auto: nextAuto(st.auto, state.memory, now) };
  });
  await refreshBadge();
  const after = s.auto.mode;
  if (after !== before) {
    log('memory', `Auto went from ${before} to ${after}`);
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

async function onLinkRequest(req) {
  log('coolHead', `Cool Head asked: ${req.action}`);
  const r = await answerLinkRequest(req);
  log('coolHead', `Answered ${req.action}: ${r.ok ? 'done' : 'not done'}, ${r.count}${r.done ? `. ${r.done}` : ''}`);
  return r;
}

async function answerLinkRequest({ action }) {
  const { tabs, s, now, ctx } = await gather();
  switch (action) {
    case 'sleepHidden': {
      const slept = await sleepMany(planSleepHidden(tabs, planCtx(s, ctx, now)), { why: () => "Cool Head's card asked to sleep tabs you aren't looking at" });
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
  const slept = await sleepMany(toSleep, { why: () => 'in a group not used today' });
  await refreshBadge();
  return { ok: true, count: slept.length, done: W.DONE.foldedGroups(folded, slept.length) };
}

async function closeDuplicates() {
  const { tabs, ctx } = await gather();
  const groups = findDuplicates(tabs, ctx);
  const ids = groups.flatMap((g) => g.closeIds);
  if (ids.length) await chrome.tabs.remove(ids).catch(() => {});
  // what closed, listed in the popup until the person presses Done
  if (ids.length) await store.save({ closedDups: groups.map((g) => ({ title: g.title || 'Untitled tab', n: g.closeIds.length })) });
  if (ids.length) log('closed', `Closed ${ids.length} duplicate tabs`);
  return ids.length;
}

function scheduleReconnect(ms) {
  setTimeout(() => connectLink().catch(oops), ms);
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
    reportTimer = setTimeout(() => maybeReport().catch(oops), REPORT_EVERY_MS - (now - s.lastReportAt));
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
  const tabs = await tabsNow({});
  const live = new Set(tabs.map((t) => t.id));
  await store.change((st) => ({
    session: st.session?.active && st.session.tabIds.some((id) => live.has(id)) ? st.session : null,
    asleep: st.asleep.filter((id) => live.has(id)),
    rest: { ...st.rest, memory: false, session: Boolean(st.session?.active && st.session.tabIds.some((id) => live.has(id))) },
  }));
  await findKeptAgain();
  const after = await store.load();
  log('chrome', `A new run of Chrome: ${tabs.length} tabs, ${after.kept.length} kept tabs found again, ${after.keepQuestions.length} to ask about`);
  chrome.alarms.create('find-kept', { delayInMinutes: 1 });
  await wakeExtensionsIfDone();
  await sites.ensure({ injectOpenPages: true });
  ensureMenu();
  await refreshBadge();
}

// ---------- saved windows ----------

// A window saved as a bookmark folder and closed, then reopened asleep (logic/windows.js). Bookmarks is an optional
// permission, asked for in the popup the first time a window is saved.
async function hasBookmarks() {
  return chrome.permissions.contains(BOOKMARKS);
}

async function otherBookmarksId() {
  const [root] = await chrome.bookmarks.getTree();
  const kids = root.children || [];
  return (kids.find((n) => n.folderType === 'other') || kids[1] || kids[0]).id;
}

// The "Cool Head windows" folder, made under Other bookmarks when first needed, and again if it was deleted.
async function windowsParent(s, make) {
  if (s.windowsFolderId) {
    const [got] = await chrome.bookmarks.get(s.windowsFolderId).catch(() => []);
    if (got && !got.url) return got.id;
  }
  if (!make) return null;
  const made = await chrome.bookmarks.create({ parentId: await otherBookmarksId(), title: W.WINDOWS_FOLDER });
  await store.save({ windowsFolderId: made.id });
  return made.id;
}

// The window to save: the last one used, never a popup or an app window.
async function windowToSave() {
  const win = await chrome.windows.getLastFocused({ windowTypes: ['normal'], populate: true }).catch(() => null);
  return win ? { id: win.id, tabs: (win.tabs || []).map(withRealTitle).sort((a, b) => a.index - b.index) } : null;
}

async function windowsView(tabs, s, now) {
  const win = await windowToSave();
  const here = win ? win.tabs : [];
  const urls = here.map((t) => t.url || t.pendingUrl).filter(savable);
  const ctx = contextFrom(s, tabs, win?.id ?? null, now);
  const risky = here.filter((t) => risk(heldReasons(t, { ...ctx, sessionIds: null }))).map((t) => t.title || host(t.url));
  const granted = await hasBookmarks();
  let saved = [];
  let others = [];
  if (granted) {
    const parent = await windowsParent(s, false);
    const [tree] = parent ? await chrome.bookmarks.getSubTree(parent).catch(() => []) : [];
    if (tree) ({ saved, others } = splitParent(tree.children, s.savedWindows || [], now));
  }
  return { tabsHere: urls.length, defaultWords: defaultWords(urls), day: dayText(now), granted, risky, saved, others };
}

// Saves every page in the window to a new folder, checks they're all there, and only then closes the window. When
// it's the only window, a new one opens first, so Chrome stays open.
// Answers { said, saved }: saved only once the folder holds every page and the window is closing.
async function saveWindow(m) {
  const no = (said) => ({ said, saved: false });
  if (!(await hasBookmarks())) return no(W.WINDOWS_ASKS);
  const s = await store.load();
  const now = Date.now();
  const win = await windowToSave();
  if (!win) return no(W.WINDOWS_NOTHING);
  const pages = win.tabs.map((t) => ({ url: t.url || t.pendingUrl, title: t.title })).filter((p) => savable(p.url));
  if (!pages.length) return no(W.WINDOWS_NOTHING);
  const ctx = contextFrom(s, await tabsNow({}), win.id, now);
  const risky = win.tabs.filter((t) => risk(heldReasons(t, { ...ctx, sessionIds: null })));
  if (risky.length && !m.anyway) return no(W.windowsRisky(risky.map((t) => t.title || host(t.url))));
  const words = cleanWords(m.words) || defaultWords(pages.map((p) => p.url));
  const parent = await windowsParent(s, true);
  const folder = await chrome.bookmarks.create({ parentId: parent, index: 0, title: folderTitle(words, pages.length, now) });
  for (const p of pages) await chrome.bookmarks.create({ parentId: folder.id, title: p.title || host(p.url), url: p.url }).catch(() => null);
  const inFolder = await chrome.bookmarks.getChildren(folder.id).catch(() => []);
  if (inFolder.length !== pages.length) {
    log('windows', `Saved ${inFolder.length} of ${pages.length} tabs, so the window stays open`);
    return no(W.WINDOWS_FAILED);
  }
  await store.change((st) => ({ savedWindows: [...(st.savedWindows || []), { id: folder.id, savedAt: now }] }));
  const normal = await chrome.windows.getAll({ windowTypes: ['normal'] }).catch(() => []);
  if (normal.length <= 1) await chrome.windows.create({ focused: true }).catch(() => {});
  await chrome.windows.remove(win.id).catch(() => {});
  log('windows', `Saved a window of ${pages.length} tabs as a bookmark folder and closed it`);
  return { said: W.windowsSaved(words, pages.length), saved: true };
}

// Opens a saved folder in a new window: its first page in front, the rest asleep until clicked. The folder is
// removed only once every page is open, so a failure halfway leaves it in the bookmarks.
async function reopenWindow(id) {
  const [node] = await chrome.bookmarks.getSubTree(id).catch(() => []);
  if (!node) { await forgetWindow(id); return W.WINDOWS_GONE; }
  const pages = pagesIn(node);
  const urls = pages.map((p) => p.url);
  if (!urls.length) { await chrome.bookmarks.removeTree(id).catch(() => {}); await forgetWindow(id); return W.WINDOWS_REMOVED; }
  const win = await chrome.windows.create({ url: urls[0], focused: true });
  const asleep = [];
  let failed = 0;
  // Each tab sleeps once its page has loaded, as Moving tabs does: one put to sleep before its page answers keeps no
  // address or title, and shows as Untitled. They open together and each sleeps as soon as it's ready; one that
  // hasn't an address after 15 seconds stays awake and loads, rather than sleeping blank.
  const opened = [];
  for (const p of pages.slice(1)) {
    const t = await chrome.tabs.create({ windowId: win.id, url: p.url, active: false }).catch(() => null);
    if (!t) failed++;
    else opened.push({ t, p });
  }
  await Promise.all(opened.map(async ({ t, p }) => {
    await loaded(t.id, 15000);
    const now = await tabNow(t.id).catch(() => null);
    if (!now?.url) return;
    const r = await sleepTab(t.id, { force: true, shown: p.title });
    if (r.id != null) asleep.push(r.id);
  }));
  if (asleep.length) await store.change((st) => ({ asleep: [...new Set([...st.asleep, ...asleep])] }));
  if (failed) {
    log('windows', `Reopened ${urls.length - failed} of ${urls.length} tabs; the folder stays`);
    return W.WINDOWS_REOPEN_FAILED;
  }
  await chrome.bookmarks.removeTree(id).catch(() => {});
  await forgetWindow(id);
  log('windows', `Reopened a saved window of ${urls.length} tabs, ${asleep.length} asleep, and removed its folder`);
  return W.windowsReopened(urls.length);
}

async function removeWindow(id) {
  await chrome.bookmarks.removeTree(id).catch(() => {});
  await forgetWindow(id);
  log('windows', 'Removed a saved window');
  return W.WINDOWS_REMOVED;
}

async function forgetWindow(id) {
  await store.change((st) => ({ savedWindows: (st.savedWindows || []).filter((r) => r.id !== id) }));
}

// Moves what Cool Head didn't save out of its folder, to Other bookmarks; it never deletes them.
async function tidyWindows() {
  const s = await store.load();
  const parent = await windowsParent(s, false);
  const [tree] = parent ? await chrome.bookmarks.getSubTree(parent).catch(() => []) : [];
  if (!tree) return W.windowsTidied(0);
  const { others } = splitParent(tree.children, s.savedWindows || [], Date.now());
  const other = await otherBookmarksId();
  for (const o of others) await chrome.bookmarks.move(o.id, { parentId: other }).catch(() => {});
  log('windows', `Moved ${others.length} bookmarks out of the saved windows folder`);
  return W.windowsTidied(others.length);
}

// ---------- popup messages ----------

async function viewFor() {
  const { tabs, s, now, focusedWindowId } = await gather();
  const [isMac, memInfo, sitesGranted, managementGranted, shortcuts] = await Promise.all([
    chrome.runtime.getPlatformInfo().then((p) => p.os === 'mac'),
    chrome.system.memory.getInfo().catch(() => null),
    chrome.permissions.contains(ALL_SITES),
    hasManagement(),
    chrome.commands.getAll().then((cs) => ({ tab: cs.find((c) => c.name === 'sleep-tab')?.shortcut || '', others: cs.find((c) => c.name === 'sleep-others')?.shortcut || '', window: cs.find((c) => c.name === 'save-window')?.shortcut || '' })).catch(() => ({ tab: '', others: '', window: '' })),
  ]);
  const view = buildView({ tabs, s, now, focusedWindowId, isMac, memInfo, version: VERSION, sitesGranted, managementGranted, favicon, shortcuts, online: self.navigator.onLine !== false });
  view.migrate = await migrateView(tabs, s, managementGranted);
  view.windows = await windowsView(tabs, s, now);
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
  const tab = m.tabId != null ? await tabNow(m.tabId).catch(() => null) : null;
  log('you', actLine(m, tab));
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
    case 'closedDupsSeen':
      await store.save({ closedDups: null });
      return '';
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
    case 'glanceSleep':
      await store.save({ glanceSleep: Boolean(m.on) });
      return '';
    case 'iconStyle':
      await store.save({ iconStyle: ICON_STYLES.includes(m.style) ? m.style : 'badge' });
      await refreshBadge();
      return '';
    case 'theme':
      await store.save({ toolbarDark: Boolean(m.dark) });
      await refreshBadge();
      return '';
    case 'sites':
      // The popup asks Chrome for the permission itself (Chrome needs the person's click); this only follows it.
      if (!m.on) await chrome.permissions.remove(ALL_SITES).catch(() => {});
      await sites.ensure();
      await store.change(() => ({ setupDone: true }));
      return '';
    case 'extRecLater':
      await store.save({ extRecDismissed: true });
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
    case 'keepSite': {
      const host = String(m.host || '').toLowerCase();
      if (!host) return W.DONE.failed;
      await store.change((s) => ({ keepSites: m.on ? [...new Set([...(s.keepSites || []), host])] : (s.keepSites || []).filter((x) => x !== host) }));
      sweepSoon(0);
      return '';
    }
    case 'offlineHold':
      await store.change(() => ({ offlineHold: Boolean(m.on) }));
      sweepSoon(0);
      return '';
    case 'migrate':
      // Minutes for many tabs, so it runs on after this answer; the popup follows it through storage.
      runMigration().catch(oops);
      return '';
    case 'migrateLater':
      await store.change(() => ({ migrateLater: true }));
      return '';
    case 'migrateClose':
      await store.change(() => ({ migrated: null }));
      return '';
    case 'saveWindow': return saveWindow(m);
    case 'reopenWindow': return reopenWindow(m.id);
    case 'removeWindow': return removeWindow(m.id);
    case 'tidyWindows': return tidyWindows();
    case 'openCoolHead':
      await chrome.tabs.create({ url: W.COOL_HEAD_URL });
      return '';
    default:
      return W.DONE.failed;
  }
}

function actLine(m, tab) {
  const site = tab ? host(tab.url) : 'a tab';
  switch (m.action) {
    case 'level': return `Chose ${m.level}`;
    case 'keep': return `${m.on ? 'Kept' : 'Stopped keeping'} ${site}`;
    case 'sleep': return `Slept ${site} from the popup`;
    case 'close': return `Closed ${site} from the popup`;
    case 'leaveDelay': return `Set the delay after leaving a tab to ${m.ms / 1000} seconds`;
    case 'keepSite': return `${m.on ? 'Kept' : 'Stopped keeping'} the site ${m.host}`;
    case 'offlineHold': return `Don't sleep while offline: ${m.on ? 'on' : 'off'}`;
    case 'sites': return `Access to all sites: ${m.on ? 'on' : 'off'}`;
    case 'restEnabled': return `Rest extensions: ${m.on ? 'on' : 'off'}`;
    default: return `Pressed ${m.action}`;
  }
}

async function safeColumns() {
  if (!(await hasManagement())) return null;
  const [exts, s, tabs] = await Promise.all([chrome.management.getAll(), store.load(), tabsNow({})]);
  return columns(exts, s.safeList, chrome.runtime.id, withOpenTabs(tabs));
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
      const was = s[key]?.[tabId]?.[frame];
      const now = key === 'typing' ? Boolean(m.dirty) : (m.call || m.screen ? { call: Boolean(m.call), screen: Boolean(m.screen) } : undefined);
      if (JSON.stringify(was) !== JSON.stringify(now)) {
        const what = key === 'typing' ? (m.dirty ? 'unsent typing seen' : 'typing sent or cleared')
          : (m.call || m.screen ? `${m.call ? 'call' : ''}${m.call && m.screen ? ' and ' : ''}${m.screen ? 'screen sharing' : ''} seen` : 'call ended');
        log('page', `${host(sender.tab.url)}: ${what}`, { tab: tabId, frame });
      }
      const byTab = { ...(s[key] || {}) };
      const frames = { ...(byTab[tabId] || {}) };
      if (key === 'typing') { if (m.dirty) frames[frame] = true; else delete frames[frame]; }
      else if (m.call || m.screen) frames[frame] = { call: Boolean(m.call), screen: Boolean(m.screen) };
      else delete frames[frame];
      if (Object.keys(frames).length) byTab[tabId] = frames; else delete byTab[tabId];
      return { [key]: byTab };
    }).then(() => maybeReport()).catch(oops);
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
        // most actions answer with words; Save this window also says whether it saved
        const r = await act(m);
        await refreshBadge();
        await maybeReport();
        return r && typeof r === 'object' ? { ...r, view: await viewFor() } : { said: r, view: await viewFor() };
      }
      default: return null;
    }
  })().then(reply, (e) => reply({ error: String(e?.message || e) }));
  return true; // replies later
});

// ---------- moving a suspender's tabs ----------

async function extensionNames(ids) {
  if (!ids.length || !(await hasManagement())) return {};
  const all = await chrome.management.getAll().catch(() => []);
  return Object.fromEntries(all.filter((e) => ids.includes(e.id)).map((e) => [e.id, e.name]));
}

async function migrateView(tabs, s, managementGranted) {
  const plan = migrationPlan(tabs, chrome.runtime.id);
  const from = suspenders(plan);
  const doneFrom = s.migrated?.extIds || [];
  const names = await extensionNames([...new Set([...from, ...doneFrom])]);
  // A suspender still installed after the move, which could suspend the tabs again; known only with the permission.
  const installed = managementGranted ? doneFrom.filter((id) => names[id]) : doneFrom;
  return {
    count: plan.length, from: from[0] ? names[from[0]] || null : null, later: Boolean(s.migrateLater),
    running: Boolean(s.migrating?.running), done: s.migrating?.done || 0, total: s.migrating?.total || 0,
    result: s.migrated ? { moved: s.migrated.moved, failed: s.migrated.failed, stuck: s.migrated.stuck || 0, removeId: installed[0] || null, removeName: names[installed[0]] || null } : null,
  };
}

// Resolves when the tab has finished loading, is closed, or after the time given.
function loaded(tabId, ms) {
  return new Promise((done) => {
    const finish = () => { clearTimeout(timer); chrome.tabs.onUpdated.removeListener(upd); chrome.tabs.onRemoved.removeListener(rem); done(); };
    const upd = (id, change) => { if (id === tabId && change.status === 'complete') finish(); };
    const rem = (id) => { if (id === tabId) finish(); };
    const timer = setTimeout(finish, ms);
    chrome.tabs.onUpdated.addListener(upd);
    chrome.tabs.onRemoved.addListener(rem);
  });
}

// One tab at a time: open its real address, wait for it to load (so it keeps its title and icon), then unload it.
// The tab in front only opens. Picked up again by the alarm if Chrome stops the worker partway.
let migrating = false;
async function runMigration() {
  if (migrating) return;
  migrating = true;
  try {
    const first = migrationPlan(await tabsNow({}), chrome.runtime.id);
    const extIds = suspenders(first);
    const s0 = await store.load();
    const resumed = s0.migrating?.running ? s0.migrating : null;
    let { total, done, failed } = resumed || { total: first.length, done: 0, failed: 0 };
    await store.save({ migrating: { running: true, total, done, failed }, migrated: null });
    log('migrate', `Moving ${first.length} tabs from ${extIds.length} suspender(s)`);
    const moved = [];
    const stuckAt = [];
    for (const p of first) {
      const ok = await chrome.tabs.update(p.tabId, { url: p.url }).then(() => true, () => false);
      // checked after opening: an address that downloads a file leaves the tab on the suspender's page, so it isn't
      // counted as moved, and it's remembered so the next move doesn't download the file again
      let stayed = false;
      if (ok) {
        await loaded(p.tabId, 15000);
        const now = await tabNow(p.tabId).catch(() => null);
        stayed = Boolean(now && suspendedAt(now.url || now.pendingUrl, chrome.runtime.id));
        // a page of this extension's own takes it over, holding its title and address, so the suspender can go
        if (stayed) {
          const title = (now.title && !now.title.startsWith('chrome-extension://')) ? now.title : '';
          await chrome.tabs.update(p.tabId, { url: chrome.runtime.getURL(`parked/parked.html#${new URLSearchParams({ title, url: p.url })}`) }).catch(() => {});
          stuckAt.push(p.at);
        } else if (!p.active) {
          const r = await sleepTab(p.tabId, { force: true });
          if (r.id != null) moved.push(r.id);
        }
      }
      if (ok && !stayed) done++; else if (!stayed) failed++;
      await store.save({ migrating: { running: true, total, done: done + failed + stuckAt.length, failed } });
    }
    if (moved.length) await store.change((s) => ({ asleep: [...new Set([...s.asleep, ...moved])] }));
    const doneFrom = [...new Set([...(s0.migrated?.extIds || []), ...extIds])];
    await store.save({ migrating: null, migrated: { moved: done, failed, stuck: stuckAt.length, extIds: doneFrom } });
    log('migrate', `Moved ${done} tabs${failed ? `; ${failed} couldn't be moved` : ''}${stuckAt.length ? `; ${stuckAt.length} open a download, now on a page of this extension's` : ''}`);
    await refreshBadge();
  } finally {
    migrating = false;
  }
}

// ---------- Chrome's events ----------

// A quick glance: a tab that was asleep, switched to and left again within this long, is taken as looked at, not used.
const GLANCE_MS = 10000;

chrome.tabs.onActivated.addListener(({ tabId, windowId }) => {
  const now = Date.now();
  let glanced = null;
  store.change((s) => {
    const prev = s.activeByWindow[windowId];
    const woke = { ...(s.woke || {}) };
    if (prev != null && prev !== tabId && s.glanceSleep !== false && woke[prev] && now - woke[prev] < GLANCE_MS) glanced = prev;
    if (prev != null && prev !== tabId) delete woke[prev];
    // Chrome may say the tab woke before saying it was switched to, or after; either way it's noted as woken now
    if (s.asleep.includes(tabId) && !woke[tabId]) woke[tabId] = now;
    let use = recordActivation(s.use, tabId, prev, now);
    // a glance doesn't count toward a tab's use, so it doesn't climb into the tabs kept loaded
    if (glanced && use[glanced]) use = { ...use, [glanced]: { ...use[glanced], switches: use[glanced].switches.slice(0, -1) } };
    return {
      use,
      woke,
      activeByWindow: { ...s.activeByWindow, [windowId]: tabId },
      session: join(s.session, tabId),
      asleep: s.asleep.filter((id) => id !== tabId),
    };
  }).then(async (s) => {
    tabNow(tabId).then(refreshMenu).catch(() => {});
    if (glanced != null) await sleepGlanced(glanced);
    sweepSoon(s.leaveDelayMs + 250);
    await refreshBadge();
  }).catch(oops);
});

// Puts a glanced-at tab straight back to sleep, unless something now holds it awake (a call, typing, sound, kept).
async function sleepGlanced(tabId) {
  const { tabs, ctx } = await gather();
  const t = tabs.find((x) => x.id === tabId);
  if (!t || !canSleepOnItsOwn(t, ctx)) return;
  const r = await sleepTab(tabId);
  if (r.id == null) return;
  await store.change((s) => ({ asleep: [...new Set([...s.asleep, r.id])] }));
  log('slept', `Slept ${host(t.url)}: looked at for under ${GLANCE_MS / 1000} seconds`, { tab: r.id });
}

chrome.tabs.onCreated.addListener((tab) => {
  const now = Date.now();
  store.change((s) => ({
    // A tab you open during a session joins it (design, "Sessions").
    session: s.session?.active ? join(s.session, tab.id) : s.session,
    // Opening a tab counts as using it, so one opened in the background isn't taken for long idle and put to
    // sleep while it is still loading.
    use: s.use[tab.id] ? s.use : { ...s.use, [tab.id]: { last: null, left: now, switches: [] } },
  })).catch(oops);
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
  }).then(() => refreshBadge()).then(() => maybeReport()).catch(oops);
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
  }).catch(oops);
});

chrome.tabs.onUpdated.addListener((tabId, change, tab) => {
  tab = withRealTitle(tab);
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
      if (change.discarded === true && !unloading.has(tabId)) log('chrome', `${host(tab.url)} was unloaded by Chrome or another extension`, { tab: tabId });
      if (change.discarded === false && s.asleep.includes(tabId)) log('woke', `${host(tab.url)} woke`, { tab: tabId });
      if (change.discarded === true) {
        // An unloaded page has no typing or call left; holding on to them would keep the tab held after it wakes.
        const typing = { ...s.typing }; delete typing[tabId];
        const media = { ...s.media }; delete media[tabId];
        patch.typing = typing;
        patch.media = media;
      }
      if (change.discarded === false) {
        patch.asleep = s.asleep.filter((id) => id !== tabId);
        // woken from this extension's sleep: noted, so leaving it again within GLANCE_MS puts it back (onActivated)
        if (s.asleep.includes(tabId)) patch.woke = { ...(s.woke || {}), [tabId]: Date.now() };
      }
      return patch;
    }).then(() => refreshBadge()).then(() => maybeReport()).catch(oops);
  }
  if ('pinned' in change && tab.active) refreshMenu(tab).catch(() => {});
});

chrome.tabs.onMoved.addListener(() => refreshKeptPositions().catch(oops));
chrome.tabs.onAttached.addListener(() => refreshKeptPositions().catch(oops));

chrome.contextMenus.onClicked.addListener((info, tab) => {
  if (info.menuItemId === 'log') { chrome.tabs.create({ url: chrome.runtime.getURL('log/log.html') }); return; }
  if (info.menuItemId === 'site' && tab) {
    const host = siteOf(tab.url);
    if (!host) return;
    store.load().then((s) => { const rule = siteRuleFor(tab.url, s.keepSites); return act({ action: 'keepSite', host: rule || host, on: !rule }); }).then(() => refreshMenu(tab)).then(() => maybeReport()).catch(oops);
    return;
  }
  if (info.menuItemId !== 'keep' || !tab) return;
  // From the stored state, not the menu's tick, which can be out of date after a switch between windows.
  store.load().then((s) => setKeep(tab.id, !s.kept.some((r) => r.tabId === tab.id))).then(() => maybeReport()).catch(oops);
});

// The keyboard shortcut (no key until the person picks one in Chrome's shortcuts page): the tab in front sleeps
// whatever keeps it awake otherwise, since the person asked while looking at it. Chrome can't unload the tab in
// front, so the next awake tab to its right comes to the front first, and pressing it again sleeps tab after tab.
async function sleepFrontTab(tab) {
  if (!tab || tab.discarded) return;
  const tabs = await tabsNow({ windowId: tab.windowId });
  const show = tabToShowInstead(tabs, tab.id);
  if (show == null) { log('spared', `Didn't sleep ${host(tab.url)}: it's the only tab in its window`, { tab: tab.id }); return; }
  await chrome.tabs.update(show, { active: true });
  await sleepMany([tab.id], { force: true, why: () => 'the keyboard shortcut' });
  await refreshBadge();
}

// The other shortcut: every other tab in this window that could sleep on its own, keeping their protections.
async function sleepOtherTabs(tab) {
  if (!tab) return;
  const { tabs, s, now, ctx } = await gather();
  const ids = planSleepHidden(tabs.filter((t) => t.windowId === tab.windowId && t.id !== tab.id), planCtx(s, ctx, now));
  await sleepMany(ids, { why: () => 'the keyboard shortcut for other tabs' });
  await refreshBadge();
}

chrome.commands.onCommand.addListener((command, tab) => {
  // Save this window opens the popup at Saved windows with its save dialog open, for its few words and, the first
  // time, Chrome's question about bookmarks, which only a page can ask
  if (command === 'save-window') {
    store.save({ popupScreen: 'windows' }).then(() => chrome.action.openPopup()).catch(oops);
    return;
  }
  const run = { 'sleep-tab': sleepFrontTab, 'sleep-others': sleepOtherTabs }[command];
  if (!run) return;
  const front = tab ? Promise.resolve(tab) : tabsNow({ active: true, lastFocusedWindow: true }).then(([t]) => t);
  front.then(run).catch(oops);
});

self.addEventListener('online', () => sweepSoon(0));

chrome.windows.onFocusChanged.addListener((windowId) => {
  if (windowId === chrome.windows.WINDOW_ID_NONE) return;
  tabsNow({ active: true, windowId }).then(([t]) => refreshMenu(t)).catch(() => {});
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
      if (s.migrating?.running) runMigration().catch(oops);
    }).catch(oops);
  } else if (a.name === 'sweep') {
    sweep().catch(oops);
  } else if (a.name === 'find-kept') {
    findKeptAgain().catch(oops);
  }
});

chrome.permissions.onAdded.addListener(() => sites.ensure().catch(oops));
chrome.permissions.onRemoved.addListener(() => sites.ensure().catch(oops));

chrome.runtime.onInstalled.addListener(async ({ reason, previousVersion }) => {
  log('chrome', reason === 'update' ? `Updated from ${previousVersion} to ${VERSION}` : `${reason}: version ${VERSION}`);
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
    .catch(oops);
});

// ---------- every time the worker starts ----------

// Anything that fails without a catch of its own still reaches the test log.
self.addEventListener('unhandledrejection', (e) => oops(e.reason));

chrome.alarms.get('tick').then((a) => { if (!a) chrome.alarms.create('tick', { periodInMinutes: 1 }); });
store.load().then((s) => { cachedLevel = s.level; }).catch(() => {});
newBrowserRun().then(() => connectLink()).catch(oops);
unmarkAwake().catch(oops);

// For the browser tests (test/browser/run.mjs), which drive the worker through Chrome's debugging protocol.
globalThis.coolHead = { sweep, gather, act, store, link, viewFor, unmarkAwake };
