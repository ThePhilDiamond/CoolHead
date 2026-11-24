#!/usr/bin/env node
// Browser tests: loads the extension unpacked into Chrome for Testing on a throwaway profile, with the mock host
// standing in for Cool Head, and drives it through Chrome's debugging protocol. Never touches your own Chrome:
// it needs Chrome for Testing's path and a scratch folder, and puts the native messaging manifest inside that
// scratch profile only.
//   CFT="/path/to/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing" \
//   node tools/run-browser-tests.mjs <scratch folder>
// Two runs: A with the shipping manifest (no access to sites), B with a copy that has access to all sites, to
// check unsent typing and calls. Each run quits only the Chrome it started, by its own process.
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';

const EXT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const ID = 'idncmcjhcnoknfiomdkjidgmjkglmghl';
const CFT = process.env.CFT;
const SCRATCH = path.resolve(process.argv[2] || '');
if (!CFT || !process.argv[2]) {
  console.error('Usage: CFT=<Chrome for Testing binary> node tools/run-browser-tests.mjs <scratch folder>');
  process.exit(2);
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const results = [];
// Every Chrome this script starts, so each is quit even if the script is stopped early. A test Chrome left running
// would keep answering the mock host and spoil the next run.
const started = new Set();
function quitAll() { for (const c of started) { try { c.kill('SIGKILL'); } catch { /* already gone */ } } }
process.on('exit', quitAll);
for (const sig of ['SIGINT', 'SIGTERM']) process.on(sig, () => { quitAll(); process.exit(130); });
const RUN = `${process.pid}`;

// ---------- a local test site on 127.0.0.1, nothing leaves the machine ----------

function serve() {
  const pages = {
    // only letters, digits, and hyphens from the address go into the page, so nothing in it can run as script
    '/page': (q) => { const n = (q.get('n') || '').replace(/[^A-Za-z0-9-]/g, ''); return `<title>Page ${n}</title><p>Test page ${n}</p>`; },
    '/typing': () => '<title>Expense form</title><input id="t" type="text">',
    '/untitled': () => '<p>A page without a title</p>',
    '/busy': () => '<title>Busy</title><p>A page the test keeps busy</p>',
    '/call': () => '<title>Call</title><script>window.startCall = () => navigator.mediaDevices.getUserMedia({ audio: true, video: true }).then((s) => { window.stream = s; return s.getTracks().length; });</script>',
  };
  const server = http.createServer((req, res) => {
    const u = new URL(req.url, 'http://127.0.0.1');
    if (u.pathname === '/notes.txt') { res.writeHead(200, { 'content-type': 'text/plain; charset=utf-8' }); res.end('Made-up notes'); return; }
    if (u.pathname === '/download') { res.writeHead(200, { 'content-type': 'application/octet-stream', 'content-disposition': 'attachment; filename="probe.bin"' }); res.end('x'); return; }
    const page = pages[u.pathname];
    res.writeHead(page ? 200 : 404, { 'content-type': 'text/html; charset=utf-8' });
    res.end(page ? `<!doctype html><meta charset="utf-8">${page(u.searchParams)}` : 'not found');
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server)));
}

// ---------- Chrome's debugging protocol, over a WebSocket ----------

class CDP {
  static async open(url) {
    const ws = new WebSocket(url);
    await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
    return new CDP(ws);
  }

  constructor(ws) {
    this.ws = ws; this.n = 0; this.waiting = new Map(); this.events = [];
    ws.onmessage = (e) => {
      const m = JSON.parse(e.data);
      if (m.id && this.waiting.has(m.id)) {
        const { res, rej } = this.waiting.get(m.id);
        this.waiting.delete(m.id);
        if (m.error) rej(new Error(`${m.error.message} ${m.error.data || ''}`)); else res(m.result);
      } else if (m.method) this.events.push(m);
    };
  }

  send(method, params = {}, sessionId) {
    const id = ++this.n;
    this.ws.send(JSON.stringify({ id, method, params, sessionId }));
    return new Promise((res, rej) => this.waiting.set(id, { res, rej }));
  }

  close() { this.ws.close(); }
}

async function evaluate(cdp, sessionId, expression) {
  const r = await cdp.send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true }, sessionId);
  if (r.exceptionDetails) throw new Error(`${expression.slice(0, 80)}: ${r.exceptionDetails.exception?.description || r.exceptionDetails.text}`);
  return r.result.value;
}

async function waitFor(what, fn, ms = 20000) {
  const end = Date.now() + ms;
  let last;
  while (Date.now() < end) {
    last = await fn().catch((e) => { last = e; return null; });
    if (last) return last;
    await sleep(250);
  }
  throw new Error(`timed out waiting for ${what}`);
}

// ---------- one run ----------

async function run(name, extDir, steps) {
  const data = path.join(SCRATCH, `cft-profile-${name}`);
  fs.rmSync(data, { recursive: true, force: true });
  fs.mkdirSync(path.join(data, 'NativeMessagingHosts'), { recursive: true });
  const scenarioFile = path.join(SCRATCH, `mock-${name}-${RUN}.json`);
  const log = path.join(SCRATCH, `mock-${name}-${RUN}.log`);
  fs.rmSync(log, { force: true });
  const scenario = (s) => fs.writeFileSync(scenarioFile, JSON.stringify({ log, everyMs: 1000, ...s }));
  scenario({ app: 'notRunning', memory: 'fine' });
  // Chrome finds the host through this manifest in the test profile's own folder, never in ~/Library.
  fs.writeFileSync(path.join(data, 'NativeMessagingHosts', 'io.github.thephildiamond.coolhead.json'), JSON.stringify({
    name: 'io.github.thephildiamond.coolhead', description: 'Mock Cool Head link host, for tests',
    path: path.join(EXT, 'tools/mock-host.mjs'), type: 'stdio', allowed_origins: [`chrome-extension://${ID}/`],
  }));
  const chrome = spawn(CFT, [
    `--user-data-dir=${data}`, `--load-extension=${extDir}`, `--disable-extensions-except=${extDir}`,
    '--remote-debugging-port=0', '--no-proxy-server', '--no-first-run', '--no-default-browser-check', '--headless=new',
    '--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream', '--autoplay-policy=no-user-gesture-required',
    'about:blank',
  ], { env: { ...process.env, COOLHEAD_MOCK_FILE: scenarioFile, PATH: `${path.dirname(process.execPath)}:${process.env.PATH}` }, stdio: 'ignore' });
  started.add(chrome);
  const logLines = () => (fs.existsSync(log) ? fs.readFileSync(log, 'utf8').trim().split('\n').filter(Boolean).map(JSON.parse) : []);
  let cdp;
  try {
    const port = await waitFor('DevToolsActivePort', async () => {
      const f = path.join(data, 'DevToolsActivePort');
      return fs.existsSync(f) ? fs.readFileSync(f, 'utf8').split('\n')[0] : null;
    });
    const version = await (await fetch(`http://127.0.0.1:${port}/json/version`)).json();
    cdp = await CDP.open(version.webSocketDebuggerUrl);
    const worker = await waitFor('the service worker', async () => {
      const { targetInfos } = await cdp.send('Target.getTargets');
      return targetInfos.find((t) => t.type === 'service_worker' && t.url === `chrome-extension://${ID}/src/worker.js`);
    });
    const { sessionId } = await cdp.send('Target.attachToTarget', { targetId: worker.targetId, flatten: true });
    const w = (expr) => evaluate(cdp, sessionId, expr);
    await waitFor('the worker to be ready', () => w('Boolean(globalThis.coolHead)'));
    const ctx = { cdp, w, scenario, logLines, browser: version.Browser };
    for (const [title, fn] of steps) {
      const started = Date.now();
      try {
        await fn(ctx);
        results.push({ run: name, title, ok: true, ms: Date.now() - started });
        console.log(`ok   ${name}: ${title}`);
      } catch (e) {
        results.push({ run: name, title, ok: false, error: e.message });
        console.log(`FAIL ${name}: ${title}\n     ${e.message}`);
      }
    }
  } finally {
    cdp?.close();
    // Only the Chrome this run started, by its own process.
    chrome.kill('SIGTERM');
    await Promise.race([new Promise((r) => chrome.once('exit', r)), sleep(5000)]);
    if (chrome.exitCode === null && chrome.signalCode === null) chrome.kill('SIGKILL');
    started.delete(chrome);
  }
}

// ---------- the steps ----------

const site = await serve();
const BASE = `http://127.0.0.1:${site.address().port}`;
console.log(`test site: ${BASE}, answers: ${(await (await fetch(`${BASE}/page?n=0`)).text()).slice(0, 60)}`);
const state = (w) => w('coolHead.store.load()');
const tabsNow = (w) => w('chrome.tabs.query({}).then((t) => t.map(({ id, url, title, active, discarded, pinned, audible, autoDiscardable, groupId }) => ({ id, url, title, active, discarded, pinned, audible, autoDiscardable, groupId })))');
const openTabs = (w, urls) => w(`Promise.all(${JSON.stringify(urls)}.map((url) => chrome.tabs.create({ url, active: false }))).then((t) => t.map((x) => x.id))`);
const act = (w, m) => w(`coolHead.act(${JSON.stringify(m)})`);
const loaded = async (w, ids) => {
  try {
    return await waitFor('tabs to load', async () => {
      const t = await w('chrome.tabs.query({})');
      // A tab may already be asleep (Focus sleeps a background tab at once); that counts as having loaded.
      return ids.every((id) => t.find((x) => x.id === id && (x.status === 'complete' || (x.discarded && x.title)))) ? t : null;
    });
  } catch (e) {
    const t = await w('chrome.tabs.query({})');
    throw new Error(`${e.message}: ${JSON.stringify(t.filter((x) => ids.includes(x.id)).map(({ id, url, pendingUrl, title, status }) => ({ id, url, pendingUrl, title, status })))}`);
  }
};

const A = [
  ['the extension loads with its fixed ID and opens the setup page once', async ({ w }) => {
    assert.equal(await w('chrome.runtime.id'), ID);
    const t = await waitFor('the setup tab', async () => (await tabsNow(w)).find((x) => x.url === `chrome-extension://${ID}/setup/setup.html`));
    assert.ok(t);
    const granted = await w("chrome.permissions.contains({ origins: ['<all_urls>'] })");
    assert.equal(granted, false, 'access to all sites is never assumed');
    assert.deepEqual(await w('chrome.scripting.getRegisteredContentScripts().then((s) => s.length)'), 0);
  }],
  ['alone: the host is there but Cool Head is not open', async ({ w }) => {
    const s = await waitFor('notRunning', async () => { const x = await state(w); return x.link.status === 'notRunning' ? x : null; });
    assert.equal(s.level, 'balanced');
  }],
  ['together: Cool Head opens, they link, say hello, and Auto becomes the level the person never chose', async ({ w, scenario, logLines }) => {
    scenario({ app: 'running', memory: 'fine' });
    const s = await waitFor('linked', async () => { const x = await state(w); return x.link.status === 'linked' && x.link.state ? x : null; });
    assert.equal(s.level, 'auto');
    const hello = await waitFor('hello in the host log', async () => logLines().find((m) => m.type === 'hello'));
    assert.deepEqual(Object.keys(hello).sort(), ['browser', 'extension', 'level', 'type', 'v']);
  }],
  ['together: when memory is very tight, Auto sleeps idle tabs one at a time, oldest first, and reports it', async ({ w, scenario, logLines }) => {
    const ids = await openTabs(w, [1, 2, 3, 4].map((n) => `${BASE}/page?n=${n}`));
    await loaded(w, ids);
    // Pretend these were last used 10 to 40 minutes ago.
    const now = Date.now();
    await w(`coolHead.store.save({ use: ${JSON.stringify(Object.fromEntries(ids.map((id, i) => [id, { last: now - (40 - i * 10) * 60000, left: now - (40 - i * 10) * 60000, switches: [] }])))} })`);
    scenario({ app: 'running', memory: 'veryTight' });
    const first = await waitFor('the first tab asleep', async () => ((await tabsNow(w)).find((t) => t.id === ids[0] && t.discarded) ? true : null));
    assert.ok(first);
    const all = await waitFor('all four asleep', async () => {
      const t = await tabsNow(w);
      return ids.every((id) => t.find((x) => x.id === id)?.discarded) ? t : null;
    });
    assert.ok(all);
    // no number on the toolbar icon any more (it shows memory's level); the count is in its title
    assert.equal(await w('chrome.action.getBadgeText({})'), '');
    assert.match(await w('chrome.action.getTitle({})'), /4 tabs asleep/);
    const r = await waitFor('a report with 4 asleep', async () => logLines().find((m) => m.type === 'report' && m.asleep === 4));
    assert.equal(JSON.stringify(r).includes('127.0.0.1'), false, 'no addresses cross the link');
  }],
  ['together: Cool Head\'s one-click request gets a result in its voice', async ({ w, scenario, logLines }) => {
    const dup = await openTabs(w, [`${BASE}/page?n=dup`, `${BASE}/page?n=dup`]);
    await loaded(w, dup);
    scenario({ app: 'running', memory: 'fine', requests: [{ id: 'r1', action: 'closeDuplicates' }] });
    const r = await waitFor('result r1', async () => logLines().find((m) => m.type === 'result' && m.id === 'r1'));
    assert.deepEqual([r.ok, r.count], [true, 1], JSON.stringify({ r, dup, tabs: (await tabsNow(w)).filter((t) => t.url.includes("dup") || dup.includes(t.id)) }));
    assert.match(r.done, /^Closed 1 duplicate tab\./);
  }],
  ['dropped: Cool Head closes; the extension carries on alone, a chosen Auto waits, nothing lost', async ({ w, scenario }) => {
    await act(w, { action: 'level', level: 'auto' }); // the person chooses Auto
    scenario({ app: 'notRunning', memory: 'fine' });
    const s = await waitFor('notRunning', async () => { const x = await state(w); return x.link.status === 'notRunning' ? x : null; });
    assert.equal(s.level, 'auto', 'the chosen level stays');
    assert.equal(s.auto.mode, 'off');
    assert.equal(s.link.state, null);
  }],
  ['dropped: the host itself ends; the extension says not linked, then links again', async ({ w, scenario }) => {
    scenario({ app: 'running', memory: 'fine' });
    await waitFor('linked', async () => ((await state(w)).link.status === 'linked' ? true : null));
    scenario({ app: 'running', memory: 'fine', exit: true });
    await waitFor('notLinked', async () => ((await state(w)).link.status === 'notLinked' ? true : null));
    scenario({ app: 'running', memory: 'fine' });
    await waitFor('linked again', async () => ((await state(w)).link.status === 'linked' ? true : null), 30000);
  }],
  ['Focus with "At once": leaving a tab sleeps it; a pinned and a kept tab stay loaded', async ({ w }) => {
    await act(w, { action: 'level', level: 'focus' });
    await act(w, { action: 'leaveDelay', ms: 0 });
    const ids = await openTabs(w, [`${BASE}/page?n=f1`, `${BASE}/page?n=f2`, `${BASE}/page?n=pinned`, `${BASE}/page?n=kept`]);
    await loaded(w, ids);
    await w(`chrome.tabs.update(${ids[2]}, { pinned: true })`);
    await act(w, { action: 'keep', tabId: ids[3], on: true });
    await w(`chrome.tabs.update(${ids[0]}, { active: true })`);
    await sleep(300);
    await w(`chrome.tabs.update(${ids[1]}, { active: true })`);
    const t = await waitFor('the left tab asleep', async () => { const x = await tabsNow(w); return x.find((y) => y.id === ids[0])?.discarded ? x : null; });
    const by = Object.fromEntries(t.map((x) => [x.id, x]));
    assert.equal(by[ids[1]].discarded, false, 'the tab in front');
    assert.equal(by[ids[2]].discarded, false, 'pinned');
    assert.equal(by[ids[3]].discarded, false, 'kept');
    assert.equal(by[ids[3]].autoDiscardable, false, 'Chrome told to leave the kept tab too');
    // without access to sites, a sleeping tab keeps its title as it was, with no mark
    assert.equal(by[ids[0]].title, 'Page f1');
  }],
  ['a session: unticked tabs sleep, a tab switched to joins, ending saves a named group without reloading', async ({ w }) => {
    await act(w, { action: 'level', level: 'balanced' });
    const ids = await openTabs(w, [`${BASE}/page?n=s1`, `${BASE}/page?n=s2`, `${BASE}/page?n=s3`]);
    await loaded(w, ids);
    await w(`chrome.tabs.update(${ids[0]}, { active: true })`);
    const said = await act(w, { action: 'startSession', tabIds: [ids[0]] });
    assert.match(said, /^Session started with 1 tab\./);
    let t = await tabsNow(w);
    assert.equal(t.find((x) => x.id === ids[1]).discarded, true);
    await w(`chrome.tabs.update(${ids[1]}, { active: true })`);
    await waitFor('the switched-to tab in the session', async () => ((await state(w)).session.tabIds.includes(ids[1]) ? true : null));
    const ended = await act(w, { action: 'endSession', save: true, name: 'Harbor & Pine meeting' });
    assert.match(ended, /Saved 2 tabs as "Harbor & Pine meeting"\./);
    const groups = await w("chrome.tabGroups.query({ title: 'Harbor & Pine meeting' })");
    assert.equal(groups.length, 1);
    t = await tabsNow(w);
    assert.equal(t.find((x) => x.id === ids[2]).discarded, true, 'the asleep tab stays asleep');
    assert.equal((await state(w)).session, null);
  }],
  ['the popup opens, draws, and logs no errors (content security policy included)', async ({ cdp }) => {
    const { targetId } = await cdp.send('Target.createTarget', { url: `chrome-extension://${ID}/popup/popup.html` });
    const { sessionId } = await cdp.send('Target.attachToTarget', { targetId, flatten: true });
    await cdp.send('Runtime.enable', {}, sessionId);
    await cdp.send('Log.enable', {}, sessionId);
    const text = await waitFor('the popup to draw', async () => {
      const v = await evaluate(cdp, sessionId, "document.querySelector('#app')?.innerText || ''");
      return v.includes('Start a session') ? v : null;
    });
    assert.match(text, /Effort/i);
    // Open Protected, then Settings, to draw the other screens.
    await evaluate(cdp, sessionId, "document.querySelector('[data-key=protected]').click()");
    await sleep(300);
    await evaluate(cdp, sessionId, "document.querySelector('[data-key=settings]').click()");
    await waitFor('settings', async () => ((await evaluate(cdp, sessionId, "document.querySelector('#app').innerText")).includes('How soon a tab you leave sleeps') ? true : null));
    const errors = cdp.events.filter((e) => e.sessionId === sessionId && (e.method === 'Runtime.exceptionThrown'
      || (e.method === 'Log.entryAdded' && e.params.entry.level === 'error')
      || (e.method === 'Runtime.consoleAPICalled' && e.params.type === 'error')));
    assert.deepEqual(errors.map((e) => JSON.stringify(e.params).slice(0, 300)), []);
    await cdp.send('Target.closeTarget', { targetId });
  }],
  ['a quick look: a sleeping tab opened and left within 10 seconds sleeps again at once', async ({ w }) => {
    await act(w, { action: 'level', level: 'light' });
    const ids = await openTabs(w, [`${BASE}/page?n=g1`, `${BASE}/page?n=g2`]);
    await loaded(w, ids);
    await act(w, { action: 'sleep', tabId: ids[0] });
    await waitFor('the tab asleep', async () => ((await tabsNow(w)).find((x) => x.id === ids[0])?.discarded ? true : null));
    await w(`chrome.tabs.update(${ids[0]}, { active: true })`);
    await sleep(1500);
    await w(`chrome.tabs.update(${ids[1]}, { active: true })`);
    await waitFor('the glanced tab asleep again', async () => ((await tabsNow(w)).find((x) => x.id === ids[0])?.discarded ? true : null), 8000);
    await w(`chrome.tabs.remove(${JSON.stringify(ids)})`);
  }],
  ['Protected: Show brings a listed tab to the front', async ({ w, cdp }) => {
    const [id] = await openTabs(w, [`${BASE}/page?n=show`]);
    await loaded(w, [id]);
    await act(w, { action: 'keep', tabId: id, on: true });
    const { targetId } = await cdp.send('Target.createTarget', { url: `chrome-extension://${ID}/popup/popup.html` });
    const { sessionId } = await cdp.send('Target.attachToTarget', { targetId, flatten: true });
    await cdp.send('Runtime.enable', {}, sessionId);
    await waitFor('the popup to draw', async () => ((await evaluate(cdp, sessionId, "document.querySelector('#app')?.innerText || ''")).includes('Effort') ? true : null));
    await evaluate(cdp, sessionId, "document.querySelector('[data-key=protected]').click()");
    await waitFor('the Show button', async () => (await evaluate(cdp, sessionId, `Boolean(document.querySelector('[data-key="show-${id}"]'))`) ? true : null));
    await evaluate(cdp, sessionId, `document.querySelector('[data-key="show-${id}"]').click()`);
    await waitFor('the tab in front', async () => ((await tabsNow(w)).find((x) => x.id === id)?.active ? true : null));
    await act(w, { action: 'keep', tabId: id, on: false });
    await cdp.send('Target.closeTarget', { targetId }).catch(() => {});
  }],
  ['moving tabs: one whose address downloads a file moves to a page of the extension\'s own, so the suspender can go', async ({ w }) => {
    const fake = 'abcdefghijklmnopabcdefghijklmnop';
    const ids = await openTabs(w, [`chrome-extension://${fake}/suspended.html#ttl=Q3%20pack&pos=0&uri=${BASE}/download`,
      `chrome-extension://${fake}/suspended.html#ttl=Web&pos=0&uri=${BASE}/page?n=web`]);
    await sleep(1000);
    await act(w, { action: 'migrate' });
    const done = await waitFor('the move to finish', async () => { const s = await state(w); return s.migrated && !s.migrating ? s.migrated : null; }, 60000);
    assert.equal(done.moved, 1, 'the page moved');
    assert.equal(done.stuck, 1, 'the download is reported apart');
    const t = await tabsNow(w);
    assert.match(t.find((x) => x.id === ids[1]).url, /\/page\?n=web$/);
    const parked = t.find((x) => x.id === ids[0]).url;
    assert.ok(parked.startsWith(`chrome-extension://${ID}/parked/parked.html#`), parked);
    assert.match(decodeURIComponent(parked), /\/download/);
    assert.equal((await w('coolHead.viewFor()')).migrate.count, 0, 'nothing is left on the suspender, so its removal can be offered');
    await w(`chrome.tabs.remove(${JSON.stringify(ids)})`);
    await act(w, { action: 'migrateClose' });
  }],
];

// Run B: a copy of the extension that already has access to all sites, as if the person said yes at setup.
const B = [
  ['with access to all sites, the two content scripts are registered', async ({ w }) => {
    assert.equal(await w("chrome.permissions.contains({ origins: ['<all_urls>'] })"), true);
    const ids = await waitFor('registered scripts', async () => {
      const s = await w('chrome.scripting.getRegisteredContentScripts().then((s) => s.map((x) => x.id).sort())');
      return s.length === 2 ? s : null;
    });
    assert.deepEqual(ids, ['coolhead-media', 'coolhead-typing']);
  }],
  ['unsent typing keeps a tab loaded through an in-place address change, is listed as held, and a real reload clears it', async ({ w, cdp }) => {
    await act(w, { action: 'level', level: 'focus' });
    await act(w, { action: 'leaveDelay', ms: 0 });
    const { targetId } = await cdp.send('Target.createTarget', { url: `${BASE}/typing` });
    const { sessionId } = await cdp.send('Target.attachToTarget', { targetId, flatten: true });
    await waitFor('the typing page', async () => ((await evaluate(cdp, sessionId, "document.readyState === 'complete' && !!document.getElementById('t')")) ? true : null));
    await evaluate(cdp, sessionId, "document.getElementById('t').focus()");
    await cdp.send('Input.insertText', { text: 'Taxi to the airport, 42 dollars' }, sessionId);
    const typingTab = await waitFor('typing recorded', async () => {
      const s = await state(w);
      const id = Object.keys(s.typing)[0];
      return id ? Number(id) : null;
    });
    // A page that changes its address without reloading (as Gmail does) keeps its draft, and stays held.
    await evaluate(cdp, sessionId, "history.pushState({}, '', '/typing?view=draft')");
    await sleep(1000);
    assert.ok((await state(w)).typing[typingTab], 'typing still recorded after the address changed in place');
    const other = (await openTabs(w, [`${BASE}/page?n=b1`]))[0];
    await loaded(w, [other]);
    await w(`chrome.tabs.update(${other}, { active: true })`);
    await sleep(1500);
    await w('coolHead.sweep()');
    const t = await tabsNow(w);
    assert.equal(t.find((x) => x.id === typingTab).discarded, false, 'the tab with unsent typing stayed loaded');
    const view = await w('coolHead.viewFor()');
    const row = view.held.tabs.find((r) => r.id === typingTab);
    assert.deepEqual([row?.reason, row?.reasonText, row?.risk], ['typing', 'Unsent typing', 'typing']);
    // A real reload starts a new page with nothing typed: the tab is no longer held for typing.
    await cdp.send('Page.reload', {}, sessionId).catch(() => evaluate(cdp, sessionId, 'location.reload()'));
    await waitFor('typing cleared by the new page', async () => ((await state(w)).typing[typingTab] ? null : true), 15000);
  }],
  ['a page using the camera and microphone is seen as on a call and kept awake', async ({ w, cdp }) => {
    const { targetId } = await cdp.send('Target.createTarget', { url: `${BASE}/call` });
    const { sessionId } = await cdp.send('Target.attachToTarget', { targetId, flatten: true });
    await waitFor('the call page', async () => ((await evaluate(cdp, sessionId, "document.readyState === 'complete' && typeof startCall === 'function'")) ? true : null));
    const tracks = await evaluate(cdp, sessionId, 'startCall()');
    assert.ok(tracks >= 1, 'the fake camera gave tracks');
    const callTab = await waitFor('the call recorded', async () => {
      const s = await state(w);
      const id = Object.entries(s.media).find(([, f]) => Object.values(f).some((x) => x.call))?.[0];
      return id ? Number(id) : null;
    });
    const other = (await openTabs(w, [`${BASE}/page?n=b2`]))[0];
    await loaded(w, [other]);
    await w(`chrome.tabs.update(${other}, { active: true })`);
    await sleep(1500);
    await w('coolHead.sweep()');
    assert.equal((await tabsNow(w)).find((x) => x.id === callTab).discarded, false, 'the call stayed loaded');
    // Hanging up: the tracks stop, and within about 5 seconds the tab is no longer held for a call.
    await evaluate(cdp, sessionId, 'window.stream.getTracks().forEach((t) => t.stop())');
    await waitFor('the call to end', async () => {
      const s = await state(w);
      return Object.values(s.media[callTab] || {}).some((x) => x.call) ? null : true;
    }, 15000);
  }],
  ['pausing extensions: a session turns off an extension not kept on, and ending it turns it back on', async ({ w }) => {
    const dummy = await waitFor('the second extension', async () => (await w('chrome.management.getAll()')).find((e) => e.name === 'Test helper extension'));
    assert.equal(dummy.enabled, true);
    const cols = await w(`chrome.management.getAll().then((all) => all.filter((e) => e.id !== chrome.runtime.id).map((e) => e.name))`);
    assert.ok(cols.includes('Test helper extension'));
    await act(w, { action: 'restEnabled', on: true });
    const front = (await openTabs(w, [`${BASE}/page?n=r1`]))[0];
    await loaded(w, [front]);
    await act(w, { action: 'startSession', tabIds: [front] });
    await waitFor('the helper resting', async () => ((await w(`chrome.management.get(${JSON.stringify(dummy.id)})`)).enabled === false ? true : null));
    assert.deepEqual((await state(w)).rest.ids, [dummy.id]);
    await act(w, { action: 'endSession', save: false });
    await waitFor('the helper back on', async () => ((await w(`chrome.management.get(${JSON.stringify(dummy.id)})`)).enabled === true ? true : null));
    assert.deepEqual((await state(w)).rest.ids, []);
  }],
  ['saved windows: a window saves to a folder and closes, then reopens asleep at its addresses, and the folder goes', async ({ w }) => {
    const urls = [1, 2, 3].map((n) => `${BASE}/page?n=sw${n}`);
    const win = await w(`chrome.windows.create({ url: ${JSON.stringify(urls)}, focused: true }).then((x) => x.id)`);
    await waitFor('the window to load', async () => {
      const t = await w(`chrome.tabs.query({ windowId: ${win} })`);
      return t.length === 3 && t.every((x) => x.status === 'complete') ? t : null;
    });
    await w(`chrome.windows.update(${win}, { focused: true })`);
    const before = await w('coolHead.viewFor()');
    assert.equal(before.windows.tabsHere, 3);
    const said = await act(w, { action: 'saveWindow', words: 'Test trip' });
    assert.match(said, /Saved 3 tabs as "Test trip"/);
    await waitFor('the window to close', async () => ((await w('chrome.windows.getAll()')).some((x) => x.id === win) ? null : true));
    const view = await w('coolHead.viewFor()');
    assert.equal(view.windows.saved.length, 1);
    const f = view.windows.saved[0];
    assert.deepEqual([f.words, f.n, f.ago], ['Test trip', 3, 'today']);
    assert.match(f.name, /^Test trip · 3 tabs · \d+ [A-Z][a-z]+ \d{4}$/);
    // something the person put in the folder by hand is listed apart, and Tidy moves it out without deleting it
    const parent = (await state(w)).windowsFolderId;
    const own = await w(`chrome.bookmarks.create({ parentId: ${JSON.stringify(parent)}, title: 'Recipe ideas', url: '${BASE}/page?n=recipes' }).then((b) => b.id)`);
    assert.deepEqual((await w('coolHead.viewFor()')).windows.others.map((o) => o.title), ['Recipe ideas']);
    await act(w, { action: 'tidyWindows' });
    const moved = (await w(`chrome.bookmarks.get(${JSON.stringify(own)})`))[0];
    assert.notEqual(moved.parentId, parent, 'moved out of the folder');
    assert.deepEqual((await w('coolHead.viewFor()')).windows.others, []);
    // reopening: a new window with every page, all but the first asleep at its own address; then the folder goes
    await act(w, { action: 'reopenWindow', id: f.id });
    const back = await waitFor('the reopened tabs', async () => {
      const t = await tabsNow(w);
      const mine = t.filter((x) => urls.includes(x.url) || urls.includes(x.pendingUrl));
      return mine.length === 3 ? mine : null;
    });
    const asleep = back.filter((x) => x.discarded);
    assert.equal(asleep.length, 2, `two asleep: ${JSON.stringify(back)}`);
    assert.deepEqual(back.map((x) => x.url).sort(), [...urls].sort(), 'every page at its own address');
    assert.deepEqual(await w(`chrome.bookmarks.get(${JSON.stringify(f.id)}).then(() => 'still there', () => 'gone')`), 'gone');
    assert.deepEqual((await state(w)).savedWindows, []);
  }],
  ['the zzZ mark: a sleeping tab\'s title starts with it, never a bookmark or a kept record, and waking brings the page\'s own back', async ({ w }) => {
    const MARK = 'zzZ\u2002';
    const urls = [`${BASE}/page?n=z1`, `${BASE}/untitled`, `${BASE}/page?n=z3`, `${BASE}/page?n=z4`];
    // each opens pinned, so the level earlier tests leave can't sleep it on its own before the test does
    const pinned = (u) => w(`chrome.tabs.create({ url: ${JSON.stringify(u)}, active: false, pinned: true }).then((x) => x.id)`);
    const ids = [];
    for (const u of urls) ids.push(await pinned(u));
    await loaded(w, ids);
    const at = async (u) => (await tabsNow(w)).find((x) => x.url === u);
    // a page with a title, and one without, whose tab showed its address, so the site's name follows the mark
    const untitledShown = (await at(urls[1])).title;
    await act(w, { action: 'sleep', tabId: ids[0] });
    await act(w, { action: 'sleep', tabId: ids[1] });
    const a = await at(urls[0]);
    const b = await at(urls[1]);
    assert.deepEqual([a.discarded, a.title], [true, `${MARK}Page z1`]);
    assert.deepEqual([b.discarded, b.title], [true, `${MARK}${untitledShown}`], 'what Chrome showed, its address, keeps its place after the mark');
    // a text file has no title of its own either
    const txt = await pinned(`${BASE}/notes.txt`);
    await loaded(w, [txt]);
    const txtShown = (await at(`${BASE}/notes.txt`)).title;
    await act(w, { action: 'sleep', tabId: txt });
    const tx = await at(`${BASE}/notes.txt`);
    assert.deepEqual([tx.discarded, tx.title], [true, `${MARK}${txtShown}`]);
    assert.equal((await w('coolHead.gather()')).tabs.find((x) => x.url === `${BASE}/notes.txt`).title, txtShown);
    // Chrome refusing to unload a tab leaves it awake, so the mark comes off again
    assert.equal((await at(urls[2])).discarded, false, 'awake before');
    await w('globalThis.realDiscard = chrome.tabs.discard; chrome.tabs.discard = () => Promise.resolve(null); true');
    try {
      await act(w, { action: 'sleep', tabId: ids[2] });
    } finally {
      await w('chrome.tabs.discard = globalThis.realDiscard; true');
    }
    const c = await waitFor('the refused tab\'s own title', async () => { const x = await at(urls[2]); return x.title === 'Page z3' ? x : null; });
    assert.equal(c.discarded, false);
    // a mark left on an awake tab (a worker stopped between marking and sleeping) comes off when the worker starts
    await w(`chrome.scripting.executeScript({ target: { tabId: ${ids[2]} }, func: (m) => { document.title = m + document.title; }, args: [${JSON.stringify(MARK)}] }).then(() => true)`);
    await waitFor('the stray mark', async () => ((await at(urls[2])).title.startsWith(MARK) ? true : null));
    await w('coolHead.unmarkAwake().then(() => true)');
    await waitFor('the stray mark gone', async () => ((await at(urls[2])).title === 'Page z3' ? true : null));
    // a busy page brought to the front while it's being marked stays awake, with its own title
    // (Chrome would unload it even in front, and reload it at once, losing what was on the page)
    const busy = await pinned(`${BASE}/busy`);
    await loaded(w, [busy]);
    const page = (func) => w(`chrome.scripting.executeScript({ target: { tabId: ${busy} }, func: ${func} }).then((r) => r[0].result)`);
    await page('() => { window.stillHere = true; return true; }');
    // busy at once for 1.5 seconds (a timer in a background tab can wait up to a second, since Chrome slows them there);
    // the loop runs in the extension's own script, which shares the page's one thread, so the page can't answer meanwhile
    await w(`chrome.scripting.executeScript({ target: { tabId: ${busy} }, func: () => { const end = Date.now() + 1500; while (Date.now() < end); } }); true`);
    await sleep(100);
    const asking = act(w, { action: 'sleep', tabId: busy });
    await sleep(400);
    await w(`chrome.tabs.update(${busy}, { active: true }).then(() => true)`);
    assert.doesNotMatch(await asking, /to sleep/);
    await waitFor('the busy tab awake with its own title', async () => { const x = await at(`${BASE}/busy`); return x && !x.discarded && x.title === 'Busy' ? x : null; }, 8000);
    assert.equal(await page('() => window.stillHere === true'), true, 'never reloaded');
    // everything Cool Head works from, the popup's lists and its plans, has the page's own title
    const seen = (await w('coolHead.gather()')).tabs;
    assert.equal(seen.find((x) => x.url === urls[0]).title, 'Page z1');
    // and what it says back about a sleeping tab names the page, not the mark
    const said = await act(w, { action: 'keep', tabId: a.id, on: true });
    assert.match(said, /Page z1/);
    assert.doesNotMatch(said, /zzZ/);
    await act(w, { action: 'keep', tabId: a.id, on: false });
    // a kept tab put to sleep: its record keeps the page's own title when kept tabs are noted again (a tab moved)
    await act(w, { action: 'keep', tabId: ids[3], on: true });
    await act(w, { action: 'sleep', tabId: ids[3] });
    const d = await at(urls[3]);
    assert.equal(d.title, `${MARK}Page z4`);
    const was = (await state(w)).kept.find((x) => x.url === urls[3]);
    await w(`chrome.tabs.move(${d.id}, { index: 0 }).then(() => true)`);
    const rec = await waitFor('the kept record noted again', async () => { const r = (await state(w)).kept.find((x) => x.url === urls[3]); return r && r.index !== was.index ? r : null; });
    assert.equal(rec.title, 'Page z4');
    await act(w, { action: 'keep', tabId: d.id, on: false });
    // Saved windows: a window with a sleeping tab saves the page's own title into its bookmark
    const swUrls = [`${BASE}/page?n=zs1`, `${BASE}/page?n=zs2`];
    const win = await w(`chrome.windows.create({ url: ${JSON.stringify(swUrls)}, focused: true }).then((x) => x.id)`);
    const inWin = await waitFor('the window to load', async () => {
      const t = await w(`chrome.tabs.query({ windowId: ${win} })`);
      return t.length === 2 && t.every((x) => x.status === 'complete') ? t : null;
    });
    await act(w, { action: 'sleep', tabId: inWin.find((x) => !x.active).id });
    assert.ok((await w(`chrome.tabs.query({ windowId: ${win} })`)).some((x) => x.title.startsWith(MARK)), 'one tab asleep and marked');
    await w(`chrome.windows.update(${win}, { focused: true })`);
    await act(w, { action: 'saveWindow', words: 'Marked' });
    const f = (await w('coolHead.viewFor()')).windows.saved.find((x) => x.words === 'Marked');
    const marks = (await w(`chrome.bookmarks.getChildren(${JSON.stringify(f.id)})`)).map((x) => x.title).sort();
    assert.deepEqual(marks, ['Page zs1', 'Page zs2']);
    await act(w, { action: 'removeWindow', id: f.id });
    // waking: the page reloads with its own title (pinned, so it isn't put back to sleep before it's read)
    await w(`chrome.tabs.update(${a.id}, { pinned: true }).then(() => chrome.tabs.reload(${a.id})).then(() => true)`);
    const woke = await waitFor('the woken tab\'s own title', async () => { const x = await at(urls[0]); return x && !x.discarded && x.title === 'Page z1' ? x : null; });
    assert.equal(woke.title, 'Page z1');
  }],
];

function copyWithAllSites() {
  const dir = path.join(SCRATCH, 'extension-all-sites');
  fs.rmSync(dir, { recursive: true, force: true });
  fs.cpSync(EXT, dir, { recursive: true, filter: (src) => !src.includes(`${path.sep}tools${path.sep}`) });
  const m = JSON.parse(fs.readFileSync(path.join(dir, 'manifest.json'), 'utf8'));
  m.host_permissions = ['<all_urls>'];
  // As if the person had also said yes to "Manage your apps, extensions, and themes".
  m.permissions = [...m.permissions, 'management', 'bookmarks'];
  fs.writeFileSync(path.join(dir, 'manifest.json'), JSON.stringify(m, null, 2));
  return dir;
}

// A second, do-nothing extension for resting to turn off and on.
function helperExtension() {
  const dir = path.join(SCRATCH, 'helper-extension');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'manifest.json'), JSON.stringify({ manifest_version: 3, name: 'Test helper extension', version: '1.0' }));
  return dir;
}

try {
  await run('A', EXT, A);
  await run('B', `${copyWithAllSites()},${helperExtension()}`, B);
} finally {
  site.close();
}
const failed = results.filter((r) => !r.ok);
fs.writeFileSync(path.join(SCRATCH, 'browser-results.json'), JSON.stringify(results, null, 2));
console.log(`\n${results.length - failed.length} of ${results.length} passed`);
process.exit(failed.length ? 1 : 0);
