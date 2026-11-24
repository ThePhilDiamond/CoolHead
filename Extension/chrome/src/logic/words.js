// Every word the extension shows, in one place, so the voice stays Cool Head's (docs/BRAND.md, "Voice"):
// plain words, US English, the Oxford comma, no em dashes, no exclamation marks, sentence case,
// and every "why" ends in what it means for the person. test/words.test.js checks the mechanical rules.

export function plural(n, one, many = one + 's') {
  return `${n} ${n === 1 ? one : many}`;
}

// "Inbox", "Inbox and Budget", "Inbox, Budget, and Wiki" (Oxford comma), "Inbox, Budget, and 3 others".
export function list(items, max = 3) {
  const shown = items.slice(0, items.length > max ? max - 1 : max);
  const rest = items.length - shown.length;
  const parts = rest > 0 ? [...shown, plural(rest, 'other')] : shown;
  if (parts.length <= 1) return parts.join('');
  if (parts.length === 2) return `${parts[0]} and ${parts[1]}`;
  return `${parts.slice(0, -1).join(', ')}, and ${parts[parts.length - 1]}`;
}

export function quoted(title) {
  const t = (title || 'Untitled tab').trim();
  return `"${t.length > 60 ? t.slice(0, 57) + '...' : t}"`;
}

// Cool Head's time format: 8:45am, 2pm, 4:15pm (no leading zero, lowercase, no space).
export function clock(date) {
  const h24 = date.getHours();
  const m = date.getMinutes();
  const h = h24 % 12 === 0 ? 12 : h24 % 12;
  const ap = h24 < 12 ? 'am' : 'pm';
  return m === 0 ? `${h}${ap}` : `${h}:${String(m).padStart(2, '0')}${ap}`;
}

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
export function day(date) {
  return `${MONTHS[date.getMonth()]} ${date.getDate()}`;
}

export function usedAgo(ms) {
  if (ms == null || !Number.isFinite(ms)) return 'Not used since Chrome started';
  const min = Math.floor(ms / 60000);
  if (min < 1) return 'Used less than a minute ago';
  if (min < 60) return `Used ${plural(min, 'minute')} ago`;
  const h = Math.floor(min / 60);
  if (h < 24) return `Used ${plural(h, 'hour')} ago`;
  return `Used ${plural(Math.floor(h / 24), 'day')} ago`;
}

export function gb(bytes) {
  const v = bytes / 1024 ** 3;
  return `${v >= 10 ? Math.round(v) : v.toFixed(1)} GB`;
}

export const NAME = 'Cool Head for Chrome';
export const COOL_HEAD_URL = 'https://github.com/ThePhilDiamond/CoolHead';

// ---- the top band ----
export const MEMORY_TITLE = {
  fine: 'Memory is fine',
  tight: 'Memory is tight',
  slowed: 'Memory is slowing your Mac',
  veryTight: 'Memory is very tight',
};
export const LINKED_WAITING_TITLE = 'Working with Cool Head';
export const ALONE_TITLE = 'Working on its own';
export const LINK_TEXT = {
  linked: 'Working with Cool Head',
  notRunning: "Cool Head isn't open",
  notLinked: 'Not linked to Cool Head',
};
export const ALONE_LINE_MAC = "It can't see your Mac's memory, so tabs sleep by the level you choose.";

export function asleepLine(n) {
  if (n === 0) return 'No tabs asleep right now.';
  if (n === 1) return '1 tab asleep. It wakes when you click it.';
  return `${n} tabs asleep. Each wakes when you click it.`;
}

export function freeLine(availableBytes, capacityBytes) {
  return `About ${gb(availableBytes)} of ${gb(capacityBytes)} free, by Chrome's count.`;
}

export const NOTICE_NOT_LINKED = 'With Cool Head, a free Mac app, tabs sleep only when memory is short, so they reload less.';
export const NOTICE_NOT_RUNNING = 'Open Cool Head from your Applications folder, and tabs sleep only when memory is short, so they reload less.';
export const GET_COOL_HEAD = 'Get Cool Head';
export const GET_COOL_HEAD_LABEL = 'Get Cool Head, opens its website in a new tab';

// ---- levels ----
export const LEVEL_NAME = { auto: 'Auto', light: 'Light', balanced: 'Balanced', focus: 'Focus' };
export const LEVEL_LABEL = 'Effort';
// One line each, under its name in the Effort choices.
export const LEVEL_SHORT = {
  auto: 'Tabs sleep only when Cool Head says memory is slowing your Mac.',
  light: 'Your 5 most used tabs stay loaded; others sleep after you leave them.',
  balanced: 'Your 3 most used tabs stay loaded; others sleep after you leave them.',
  focus: "Only the tab you're on stays loaded; others sleep after you leave them.",
};
export function levelSetTo(level) { return `Set to ${LEVEL_NAME[level]}`; }

function leaving(delayMs) {
  return delayMs > 0
    ? `Others sleep ${plural(Math.round(delayMs / 1000), 'second')} after you leave them and reload when you click them.`
    : 'Others sleep as soon as you leave them and reload when you click them.';
}

export function levelLine(level, o = {}) {
  const { delayMs = 30000, autoMode = 'off', linked = true, coolHeadAuto = true, session = false } = o;
  if (session) {
    return `Paused while a session runs: only the session's tabs stay loaded. ${LEVEL_NAME[level]} carries on when it ends.`;
  }
  switch (level) {
    case 'auto':
      if (!linked) return 'Auto is waiting for Cool Head, so nothing sleeps on its own for now. Choose another level to sleep tabs without it.';
      if (!coolHeadAuto) return "Auto is off in Cool Head's settings, so nothing sleeps on its own. Turn it on there, or choose another level here.";
      if (autoMode === 'slowed') return "Auto: memory is slowing your Mac, so tabs you haven't used for 30 minutes are going to sleep, oldest first.";
      if (autoMode === 'veryTight') return "Auto: memory is very tight, so tabs you haven't used for 5 minutes are going to sleep, oldest first.";
      return "Auto: nothing sleeps while memory is fine. When memory slows your Mac, tabs you haven't used for 30 minutes sleep, oldest first.";
    case 'light': return `Light: your 5 most used tabs stay loaded. ${leaving(delayMs)}`;
    case 'balanced': return `Balanced: your 3 most used tabs stay loaded. ${leaving(delayMs)}`;
    case 'focus': return `Focus: only the tab you're on stays loaded. ${leaving(delayMs)}`;
    default: return '';
  }
}
export const AUTO_NEEDS = 'Auto needs Cool Head, which knows when memory is short.';

// ---- held in memory ----
export const PROTECTED = 'Protected';
export const PROTECTED_TABS = 'Tabs';
export const PAUSE_OFF = 'Pausing extensions is off, so they all stay on. Turn it on in Settings to choose which pause when memory is tight.';
export const PAUSE_ALLOW = 'Allow';
export const OPEN_SETTINGS = 'Open Settings';
// The pill under the band's title that goes back home from a tool, saying what waits there, as Cool Head's does.
export function backTo({ suggestions = 0, session = false } = {}) {
  if (suggestions > 0) return plural(suggestions, 'suggestion');
  return session ? 'Your session' : 'Start a session';
}
export const PROTECTED_LEDE = 'Each stays awake while the reason shown lasts. Keep awake keeps one awake after that too.';
export const PROTECTED_EMPTY = 'None right now. Tabs on a call, playing sound, pinned, with unsent typing, or kept by you show here.';
export const REASON_TEXT = {
  call: 'On a call',
  screen: 'Sharing your screen',
  sound: 'Playing sound',
  soundRecent: 'Played sound recently',
  typing: 'Unsent typing',
  kept: 'Kept by you',
  site: 'Site kept awake',
  pinned: 'Pinned',
  session: 'In the session',
};
// Keep makes a tab stay awake for good, not only while its reason lasts (a call, sound), so the button says so.
export const KEEP = 'Keep awake';
export const KEPT = 'Kept awake';
export const KEEP_TIP = 'Keeps this tab awake even after its reason ends, until you press it again.';
export const KEPT_TIP = 'Kept awake until you press this again.';
export const SLEEP = 'Sleep';
export const CLOSE = 'Close';
export const SHOW = 'Show';

// Sleep or Close on a call or unsent typing would end the call or lose the typing, so it's asked once: the second
// press does it.
export function warning(action, risk) {
  const verb = action === 'close' ? 'Closing' : 'Sleeping';
  const again = action === 'close' ? 'Press Close again to close it anyway.' : 'Press Sleep again to sleep it anyway.';
  const what = {
    typing: action === 'close' ? 'loses what you typed in this tab.' : 'loses what you typed in this tab when it reloads.',
    call: 'ends the call in this tab.',
    screen: 'stops sharing your screen from this tab.',
  }[risk];
  return `${verb} ${what} ${again}`;
}

// ---- duplicates ----
export function duplicatesCard(groups) {
  const pages = groups.length;
  const extra = groups.reduce((n, g) => n + g.closeIds.length, 0);
  const allTwice = groups.every((g) => g.closeIds.length === 1);
  const title = pages === 1
    ? (allTwice ? 'A page is open twice' : `A page is open ${groups[0].closeIds.length + 1} times`)
    : (allTwice ? `${pages} pages are open twice` : `${pages} pages are open more than once`);
  const names = list(groups.map((g) => g.title || 'Untitled tab'));
  let has;
  if (pages === 1) has = allTwice ? `${names} has a second copy.` : `${names} has ${plural(extra, 'extra copy', 'extra copies')}.`;
  else has = allTwice ? `${names} each have a second copy.` : `${names} have extra copies.`;
  return {
    title,
    line: `${has} Closing keeps the copy you used last, so you keep your place.`,
    button: `Close ${plural(extra, 'duplicate')}`,
    // each page, to see a copy that would close before closing them
    items: groups.map((g) => ({ title: g.title || 'Untitled tab', showId: g.closeIds[0], extra: g.closeIds.length })),
  };
}
export function dupExtra(n) { return n === 1 ? '1 extra copy' : `${n} extra copies`; }
export function closedDupsTitle(n) { return `Closed ${plural(n, 'duplicate tab')}`; }
export const CLOSED_DUPS_NOTE = "Each page's copy you used last is still open. Chrome's History menu can reopen the ones closed.";
export const CLOSED_DUPS_DONE = 'Done';

// ---- sessions ----
export const START = 'Start a session';
export const START_NOTE = "For one task, like a meeting or a report: tick the tabs it needs, and the others sleep until you end the session, so the task gets the memory. Ending it can save those tabs as a named group to come back to.";
export const START_LEDE = 'Tick the tabs this task needs. The others sleep: they stay in your tab bar and reload when you click them. A tab you open during the session joins it.';
export const WINDOW_ONLY = 'This window only';
export function windowOnlyWhy(n) {
  return `Ticks this window's ${plural(n, 'tab')} and unticks the rest`;
}
export const SUGGESTED = 'Suggested for this task';
export const OTHERS = 'Your other tabs';
export function showMore(n) { return `Show ${n} more`; }
export const SHOW_FEWER = 'Show fewer';
export const WHY = {
  active: "The tab you're on",
  call: 'On a call',
  screen: 'Sharing your screen',
  sound: 'Playing sound',
  kept: 'Kept by you',
};
export function startButton(n) {
  return n === 0 ? 'Tick a tab to start' : `Start with ${plural(n, 'tab')}`;
}
export function startNote(sleepCount, stayLoaded, resting) {
  const parts = [];
  parts.push(sleepCount === 0 ? 'No tabs need to sleep. Nothing closes.' : `${plural(sleepCount, 'tab')} ${sleepCount === 1 ? 'sleeps' : 'sleep'}. Nothing closes.`);
  const n = stayLoaded.length;
  if (n > 0) {
    const counts = new Map();
    for (const s of stayLoaded) counts.set(s.reason, (counts.get(s.reason) || 0) + 1);
    const head = `${plural(n, 'unticked tab')} ${n === 1 ? 'stays' : 'stay'} loaded`;
    if (counts.size === 1) {
      const [reason] = counts.keys();
      parts.push(`${head} because ${n === 1 ? 'it' : 'they'} ${STAY_WHY[reason][n === 1 ? 0 : 1]}.`);
    } else {
      parts.push(`${head}: ${list([...counts].map(([reason, k]) => `${k} ${STAY_WHY[reason][k === 1 ? 0 : 1]}`), 9)}.`);
    }
  }
  if (resting) parts.push("Extensions that aren't protected pause until it ends.");
  return parts.join(' ');
}
// What keeps an unticked tab loaded, said of one tab and of several.
const STAY_WHY = {
  call: ['is on a call', 'are on calls'],
  screen: ['is sharing your screen', 'are sharing your screen'],
  sound: ['is playing sound', 'are playing sound'],
  typing: ['has unsent typing', 'have unsent typing'],
  kept: ['is kept by you', 'are kept by you'],
  site: ['is on a site you keep awake', 'are on sites you keep awake'],
  pinned: ['is pinned', 'are pinned'],
  active: ['is in front in another window', 'are in front in other windows'],
};
export const CLOSE_START = 'Close Start a session';

export function sessionTitle(inSession, asleep) {
  return `In session: ${plural(inSession, 'tab')}. ${asleep} ${asleep === 1 ? 'other' : 'others'} asleep.`;
}
export const SESSION_NOTE = 'A tab you open or switch to joins the session. Switching among these never reloads them.';
export const END_SESSION = 'End session';
export function saveQuestion(n) { return `Save ${n === 1 ? 'this tab' : `these ${n} tabs`} as a group?`; }
export const SAVE_WHY = 'They stay open together under one name in your tab bar, so you can find them for the next meeting. Nothing reloads.';
export const GROUP_NAME = 'Group name';
export const SAVE = 'Save as a group';
export const END_WITHOUT = 'End without saving';
export function endNote(asleep) {
  return asleep === 0 ? 'Nothing reloads when the session ends.' : `The ${asleep} asleep ${asleep === 1 ? 'tab stays' : 'tabs stay'} asleep until you click them.`;
}
export function defaultGroupName(date) { return `Session at ${clock(date)}, ${day(date)}`; }

// ---- keep, found again after a restart ----
export function keepQuestion(title, n) {
  return { title: 'Which tab did you keep?', line: `Chrome restarted, and ${quoted(title)} is open in ${n} tabs. Choose the one to keep loaded.` };
}
export function whereIs(windowNumber, tabNumber) { return `Window ${windowNumber}, tab ${tabNumber}`; }
export const KEEP_THIS = 'Keep this one';
export const KEEP_NEITHER = 'Neither';

// ---- results, said in the live region and sent to Cool Head ----
export const DONE = {
  slept: (t) => `Put ${quoted(t)} to sleep. It reloads when you click it.`,
  closed: (t) => `Closed ${quoted(t)}. Chrome's History menu can reopen it.`,
  kept: (t) => `Keeping ${quoted(t)} loaded until you press Kept again.`,
  unkept: (t) => `${quoted(t)} can sleep again.`,
  sleptMany: (n) => (n === 0 ? 'No tabs needed to sleep: the rest are in use or held for a reason.' : `Put ${plural(n, 'tab')} to sleep.`),
  closedDuplicates: (n) => (n === 0 ? 'No duplicates to close.' : `Closed ${plural(n, 'duplicate tab')}. Chrome's History menu can reopen them.`),
  foldedGroups: (g, t) => (g === 0
    ? "No tab groups to fold: you've used each one today."
    : `Folded ${plural(g, 'tab group')} you haven't used today and put ${plural(t, 'tab')} in them to sleep.`),
  rested: (n) => (n === 0 ? 'No extensions to pause: the rest are protected.' : `Paused ${plural(n, 'extension')} until memory clears.`),
  restNeedsYes: 'Cool Head for Chrome needs your yes before it can pause extensions. Open it from the toolbar to allow that.',
  started: (n, s) => `Session started with ${plural(n, 'tab')}. ${s === 0 ? 'No other tabs needed to sleep.' : `${plural(s, 'other tab')} ${s === 1 ? 'is' : 'are'} asleep.`}`,
  ended: 'Session ended. Nothing reloaded.',
  saved: (n, name, already) => `Session ended. Saved ${plural(n, 'tab')} as ${quoted(name)}.${already > 0 ? ` ${plural(already, 'tab was', 'tabs were')} already in a group, so ${already === 1 ? 'it stays' : 'they stay'} there.` : ''}`,
  levelSet: (l) => `${LEVEL_NAME[l]} chosen.`,
  failed: "That didn't work: Chrome refused it. Nothing changed.",
};

// ---- settings ----
export const SETTINGS = 'Settings';
export const BACK = 'Back';
export const LEAVE_TITLE = 'How soon a tab you leave sleeps';
export const LEAVE_30 = '30 seconds after you leave';
export const LEAVE_30_WHY = 'No reload if you come back quickly.';
export const LEAVE_0 = 'As soon as you leave';
export const LEAVE_0_WHY = 'Frees memory sooner.';
export const LEAVE_NOTE = 'For Light, Balanced, and Focus.';
export const ICON_TITLE = 'Toolbar icon';
export const ICON_LEVELS = ['Memory fine', 'Tight', 'Very tight'];
export const ICON_STYLES = [['badge', 'Status badge', 'Shapes and colors'], ['melting', 'Melting snowflake', 'Color-blind friendly']];
export const GLANCE_TITLE = 'Back to sleep after a quick look';
export const GLANCE_WHY = "A sleeping tab you open and leave within 10 seconds sleeps again at once, and doesn't count as one you use. Not one with a call, typing, or sound.";

export const SITES_TITLE = 'Typing and calls';
export const SITES_ON = "On: tabs with unsent typing, or using the camera, microphone, or screen sharing, don't sleep on their own, so you don't lose what you typed or drop out of a call.";
export const SITES_OFF = 'Off: a tab with unsent typing can sleep, and what you typed is lost when it reloads. A call that has been quiet for 10 minutes can sleep too, which ends it.';
export const SITES_HOW = 'Chrome will ask to "read and change all your data on all websites". It only checks for unsent typing and calls; it never reads what you type, and nothing leaves your computer.';
export const SITES_TOGGLE = 'Keep tabs with unsent typing or a call awake';
export const SITES_TOGGLE_WHY = 'Checks each site for typing and calls; never reads what you type.';
export const SITES_ASKS = 'Chrome will ask to "read and change all your data on all websites", its words for any access to every site.';
export const CLOSE_TOOL = 'Close';
export const SITES_ON_HOW = 'To notice them, it checks each site for a text box with typing in it and for the camera, microphone, or screen sharing. It never reads what you type, and nothing leaves your computer.';
export const TURN_ON = 'Turn on';
export const TURN_OFF = 'Turn off';

export const REST_TITLE = 'Pause extensions';
export const REST_TOGGLE = 'Pause extensions when memory is very tight or a session runs';
export const REST_WHY = 'They turn back on afterward. One with tabs open stays on.';
export const REST_NEEDS = 'Chrome asks you to allow this once.';
export const PAUSE_REFUSED = "Pausing extensions stays off, since Chrome's permission wasn't given.";
export const REST_SET_UP = 'Choose which stay on';
export const SAFE_TITLE = 'Extensions';
export const SAFE_LEDE = "Pausing turns an extension off until the session ends or memory clears, which closes its pages and stops what it's doing. So password managers, blockers, VPNs, and security tools start as Always on: pausing them would lock your passwords, let ads and trackers through, or drop your VPN.";
export const SAFE_ON = 'Always on';
export const SAFE_REST = 'Pause when needed';
export const MOVE_TO_REST = 'Let it pause';
export const MOVE_TO_ON = 'Keep on';
export const SAFE_ADMIN = 'Installed by your organization, so Chrome keeps it on.';
export const SAFE_DONE = 'Done';
export const SAFE_EMPTY = 'You have no other extensions to pause.';
export const EXT_WHY = {
  admin: 'Installed by your organization',
  password: 'Password manager',
  bank: 'Banking or payments',
  signin: 'Signs you in to work',
  access: 'Helps you read or use the screen',
  blocker: 'Blocks ads or trackers',
  vpn: 'VPN or proxy',
  security: 'Security tool',
  other: '',
};
export const EXT_EVERY_SITE = 'Runs on every site you open, adding memory to every tab';
export const EXT_REC_TITLE = 'Turn off extensions you don\'t need';
export const EXT_REC_LINE = "Extensions use memory all the time, and one that runs on every site adds to every tab. Cool Head for Chrome can turn off the ones you choose while memory is very tight or a session runs, and back on afterward. Password managers, banking, security, VPN, and work sign-in tools stay on.";
export const EXT_REC_ALLOW = 'Allow and choose';
export const EXT_REC_NOTE = "Chrome asks once, in words that sound broader than this: it only lets Cool Head for Chrome see your extensions and turn them off and on.";
export const EXT_REC_LATER = 'Not now';
export const SETUP_EXT_DONE = "Done. Choose which stay on: click Cool Head for Chrome's icon, then Protected.";
export function restingNow(n) { return n === 0 ? '' : `${plural(n, 'extension is', 'extensions are')} paused now.`; }

export const ABOUT_TITLE = 'About';
export const EXT_OPEN = 'Has tabs open, so it stays on';
export const SHORTCUT_COMMAND = 'Put this tab to sleep';
export const SHORTCUT_TITLE = 'Keyboard shortcut';
export const SHORTCUT_WHAT = "The tab you're on gives way to the one you used before it. Other tabs keep their protections.";
export const SHORTCUT_NONE = 'Not set';
export const SHORTCUT_SET = 'Choose a key';
export const SHORTCUT_CHANGE = 'Change or remove';
export const SHORTCUT_PAGE = "Keys are set on Chrome's shortcuts page.";

export const MIGRATE_TITLE = 'Move suspended tabs';
export const MIGRATE_SETTINGS = 'Tabs from a tab suspender';
export function migrateRunning(done, total) { return `Moving them now: ${done} of ${total} done.`; }
export function migrateHead(n, name) { return `${plural(n, 'tab is', 'tabs are')} suspended by ${name || 'another extension'}`; }
export const MIGRATE_HOW = 'Cool Head can take them over. Each opens once and goes straight to sleep, one at a time, so memory never jumps.';
export const MIGRATE_WARN = 'Move them before you remove the suspender: removing it first closes these tabs.';
export function migrateGo(n) { return `Move ${plural(n, 'tab')}`; }
export const MIGRATE_LATER = 'Do it later';
export const MIGRATE_LATER_NOTE = 'You can move your suspended tabs any time from Settings.';
export function migrateProgress(done, total) { return `Moving ${done} of ${total}`; }
export const MIGRATE_KEEP_GOING = 'You can close this; it keeps going.';
export function migrateDone(n) { return `${plural(n, 'tab')} moved. Each is asleep and wakes when you click it.`; }
export function migrateFailed(n) { return `${plural(n, "tab couldn't", "tabs couldn't")} be moved and ${n === 1 ? 'stays' : 'stay'} with the suspender.`; }
export function migrateParked(n) {
  return n === 1 ? "1 tab's address downloads a file instead of opening a page, so it now shows a page of Cool Head for Chrome's with its address. Nothing needs the suspender any more."
    : `${n} tabs' addresses download a file instead of opening a page, so they now show a page of Cool Head for Chrome's with their address. Nothing needs the suspender any more.`;
}
export const PARKED_UNTITLED = 'A download';
export const PARKED_WHY = "This tab's address downloads a file instead of opening a page, so Cool Head for Chrome keeps it here: the tab suspender that held it can be removed without losing it.";
export const PARKED_ADDRESS = 'Its address:';
export const PARKED_DOWNLOAD = 'Download it again';
export const PARKED_CLOSE = 'Close this tab';
export function migrateRemove(name) { return `Remove ${name || 'the suspender'} now, so it can't suspend them again.`; }
export const MIGRATE_REMOVE = 'Remove it';
export const MIGRATE_NOT_NOW = 'Not now';
export function about(version) {
  return `Version ${version}. Free and open source under the AGPL. Nothing leaves your computer: no network use and no analytics.`;
}

// ---- setup page ----
export const SETUP_TITLE = 'Cool Head for Chrome is installed';
export const SETUP_LEDE = "Tabs you aren't using will sleep: they stay in your tab bar and reload when you click them, which frees memory for what you're doing.";
export const SETUP_HOW = 'How to use it';
// each step is [title, what to do]; the Mac app's step shows only on a Mac
export const SETUP_STEPS = [
  ['Pin it', "Click the puzzle piece in Chrome's toolbar, then the pin beside Cool Head for Chrome."],
  ['Review your tabs', 'Click its icon to see which tabs are asleep, wake one, or keep one awake.'],
  ['Set the effort', 'Balanced, where it starts, keeps your 3 most used tabs loaded; the rest sleep 30 seconds after you leave them.'],
];
export const SETUP_STEP_MAC = ['Link to the Mac app', 'With Cool Head, the free Mac app, open, choose Auto: tabs sleep only when memory is short.'];
export const setupStep = (n) => `Step ${n}`;
export const SETUP_OPTIONAL = 'optional';
export const SETUP_OPTIONAL_TAG = 'Optional';
export const SETUP_NOTHING_ELSE = "There's nothing else to set up. It works by itself from now on.";
export const SETUP_ASK = 'Protect unsent typing and calls?';
export const SETUP_WHY = "A tab with unsent typing, or on a call, won't sleep on its own, so you don't lose what you typed or drop out of the call.";
export const SETUP_YES = 'Protect them';
export const SETUP_NO = 'Not now';
export const SETUP_NO_COST = 'Not now: a sleeping tab loses unsent typing when it reloads, and a call quiet for 10 minutes can end. You can turn this on later in Settings.';
// the extensions card, shorter than the popup's (EXT_REC_LINE, EXT_REC_NOTE) so the welcome fits one screen
export const SETUP_EXT_LINE = 'Extensions use memory in every tab. While memory is very tight or a session runs, it turns off the ones you choose, then back on. Password managers, banking, security, VPN, and work sign-in tools stay on.';
export const SETUP_EXT_NOTE = "Chrome's question sounds broader: this only lets it see your extensions and turn them off and on.";
export const SETUP_ASKING = 'Answer Chrome…';
export const SETUP_ASKING_NOTE = 'Chrome is asking whether to allow it, in a box near the top of the window.';
export const SETUP_DONE_YES_TITLE = 'Protected';
export const SETUP_DONE_YES = 'Tabs with unsent typing or on a call stay loaded.';
export const SETUP_DONE_NO_TITLE = 'Not protected for now';
export const SETUP_DONE_NO = 'You can turn this on later in Settings.';
export const SETUP_REFUSED_TITLE = "Chrome didn't allow it";
export const SETUP_CLOSE = 'You can close this tab.';
export const SETUP_REFUSED = "Chrome didn't allow it, so this stays off. You can try again later in Settings.";
export const SETUP_NEXT = "Open Cool Head for Chrome from the puzzle piece in the toolbar; pin it there to see at a glance how tight your computer's memory is.";

// ---- the right-click menu ----
export const MENU_KEEP = 'Keep this tab loaded';
export function menuSite(host) { return `Keep every ${host} tab loaded`; }

export const SITES_PART = 'Sites';
export const SITES_LEDE = 'Every tab from these sites stays awake.';
export const SITES_NONE = 'None yet.';
export function siteAdd(host) { return `Keep ${host} awake`; }
export const SITE_REMOVE = 'Remove';

export const OFFLINE_TITLE = 'Offline';
export const OFFLINE_TOGGLE = "Don't sleep tabs while you're offline";
export const OFFLINE_WHY = "A sleeping tab can't reload until you're back online.";
export const OFFLINE_CARD_TITLE = "You're offline, so tabs aren't sleeping";
export const OFFLINE_CARD_LINE = "Memory is low. Sleeping tabs would free it, but they couldn't reload until you're back online. You can let them sleep anyway in Settings.";
export const OFFLINE_CARD_BUTTON = 'Open Settings';

export const SHORTCUT_THIS = 'This tab';
export const SHORTCUT_OTHERS = 'Other tabs in this window';

// Saved windows: a window saved as a bookmark folder and closed, then reopened with every tab asleep. A folder is
// named from a few words the person gives, how many tabs it holds, and the day; reopening it removes it, so saved
// windows never pile up (decided 24 November 2026).
export const WINDOWS = 'Saved windows';
export const WINDOWS_TOOL = 'Windows';
export const WINDOWS_FOLDER = 'Cool Head windows';
export const WINDOWS_SAVE_TITLE = 'Save this window and close it';
export const WINDOWS_SAVE_WHY = "Its tabs go into a bookmark folder, so you can open them again later, here or with Chrome's own Open all in new window.";
export const WINDOWS_DESCRIBE = 'Describe it (optional)';
export const WINDOWS_DESCRIBE_HINT = 'Trip planning';
export const windowFolderName = (words, n, day) => `${words} · ${n} ${n === 1 ? 'tab' : 'tabs'} · ${day}`;
export const windowsSavedAs = (name) => `Saved as "${name}"`;
export const WINDOWS_SAVE = 'Save and close';
export const WINDOWS_SAVE_NOTE = 'A tab with unsent typing or a call asks first. The window closes only once its folder is saved.';
export const WINDOWS_SAVED = 'Saved';
export const windowsLine = (n, ago) => `${n} ${n === 1 ? 'tab' : 'tabs'} · saved ${ago}`;
export const WINDOWS_REOPEN = 'Reopen';
export const WINDOWS_REMOVE = 'Remove';
export const windowsReopenAsk = (n) => `Reopen ${n === 1 ? 'this tab' : `these ${n} tabs`} in a new window? ${n === 1 ? 'It opens' : 'They open'} asleep and load when you click them, and the folder leaves your bookmarks.`;
export const windowsRemoveAsk = (n) => `Remove this folder and its ${n} ${n === 1 ? 'bookmark' : 'bookmarks'}? This can't be undone.`;
export const WINDOWS_CANCEL = 'Cancel';
export const WINDOWS_EMPTY = "No saved windows yet. Save a window above when you're done with it for now.";
export const WINDOWS_OTHERS = 'Not saved by Cool Head';
export const WINDOWS_OTHERS_WHY = `These are in the ${WINDOWS_FOLDER} folder, but Cool Head for Chrome didn't put them there. Tidy moves them to Other bookmarks; it never deletes them.`;
export const WINDOWS_TIDY = 'Tidy';
export const WINDOWS_ASKS = 'The first time, Chrome asks to let Cool Head for Chrome change your bookmarks.';
