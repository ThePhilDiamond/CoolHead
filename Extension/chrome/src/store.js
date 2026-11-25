// All state lives in chrome.storage, never only in the worker's memory: Chrome stops a Manifest V3 service
// worker after about 30 seconds idle (test T13), and anything held only in a variable is gone with it.
// - local: what must outlast Chrome itself (the level, the keep list, the session, the extensions kept on).
// - session: what belongs to this run of Chrome (tab use, sound, typing, the link). Tab IDs end when Chrome quits,
//   and session storage clears then too, which is also how a restart is noticed (see worker.js, newBrowserRun).
import { AUTO_OFF } from './logic/auto.js';

export const LOCAL_DEFAULTS = {
  level: 'balanced',
  levelChosen: false,        // whether the person picked a level; if not, Auto becomes the level once linked
  leaveDelayMs: 30000,
  glanceSleep: true,         // a tab woken and left within GLANCE_MS sleeps again at once and doesn't count as used
  kept: [],                  // keep records (logic/keep.js)
  keepQuestions: [],         // kept tabs that matched two restored tabs: { record, candidates }
  session: null,             // { active, tabIds, startedAt }
  asleep: [],                // tab IDs this extension put to sleep
  safeList: { decided: false, alwaysOn: [], rest: [] },
  restEnabled: false,
  extRecDismissed: false,    // the person chose Not now on the recommendation to turn off extensions (Settings still has it)
  rest: { ids: [], session: false, memory: false },
  setupDone: false,
  keepSites: [],            // sites whose every tab stays awake, as host names without www (logic/reasons.js)
  offlineHold: true,         // no tab sleeps on its own while Chrome is offline, since a sleeping tab can't reload then
  iconStyle: 'badge',        // the toolbar icon: 'badge' (shapes and colors) or 'melting' (no color needed)
  toolbarDark: false,        // whether Chrome's toolbar is dark, as the popup last saw, for the toolbar icon's color
  migrateLater: false,       // the person chose "Do it later" for moving a suspender's tabs (Settings still has it)
  savedWindows: [],          // [{ id, savedAt }]: bookmark folders Saved windows made (logic/windows.js)
  windowsFolderId: null,     // the "Cool Head windows" folder they live in
};

export const SESSION_DEFAULTS = {
  closedDups: null,          // [{ title, n }]: duplicates just closed, listed until the person presses Done
  run: false,                // set once per run of Chrome
  runStartedAt: null,
  use: {},
  woke: {},                  // { tabId: when }: a tab asleep that you switched to, for re-sleeping a quick glance
  audibleAt: {},
  media: {},                 // { tabId: { frameId: { call, screen } } }
  typing: {},                // { tabId: { frameId: true } }
  activeByWindow: {},
  minimizedAt: {},           // { windowId: when it was first seen minimized } (logic/minimized.js)
  frontAsleep: {},           // { tabId: { inPlace } }: minimized windows' front tabs this worker slept, to wake when back
  link: { status: 'connecting', app: '', state: null, stateAt: null, attemptAt: null },
  auto: AUTO_OFF,
  lastReport: null,
  lastReportAt: null,
  popupScreen: null,         // a screen for the popup to open on, set by Cool Head's "openExtensionsList"
  migrating: null,           // { running, total, done, failed }: moving a suspender's tabs (logic/migrate.js)
  migrated: null,            // { moved, failed, stuck, extIds }: the last move, until the person closes its result
};

const LOCAL_KEYS = Object.keys(LOCAL_DEFAULTS);
const SESSION_KEYS = Object.keys(SESSION_DEFAULTS);

export async function load() {
  const [local, session] = await Promise.all([
    chrome.storage.local.get(LOCAL_KEYS),
    chrome.storage.session.get(SESSION_KEYS),
  ]);
  return { ...structuredClone(LOCAL_DEFAULTS), ...local, ...structuredClone(SESSION_DEFAULTS), ...session };
}

export async function save(patch) {
  const local = {};
  const session = {};
  for (const [k, v] of Object.entries(patch)) {
    if (LOCAL_KEYS.includes(k)) local[k] = v;
    else if (SESSION_KEYS.includes(k)) session[k] = v;
    else throw new Error(`unknown state key ${k}`);
  }
  await Promise.all([
    Object.keys(local).length ? chrome.storage.local.set(local) : null,
    Object.keys(session).length ? chrome.storage.session.set(session) : null,
  ]);
}

// Chrome runs event handlers side by side, so two that read, change, and write the same state could undo each
// other. Every change goes through this one queue: fn(state) returns a patch (or nothing), which is saved before
// the next change reads.
let queue = Promise.resolve();
export function change(fn) {
  const run = queue.then(async () => {
    const s = await load();
    const patch = await fn(s);
    if (patch && Object.keys(patch).length) await save(patch);
    return { ...s, ...(patch || {}) };
  });
  queue = run.catch(() => {});
  return run;
}
