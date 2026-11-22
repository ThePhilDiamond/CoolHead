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
export const LEVEL_LABEL = 'How hard it works';

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
export const PROTECTED_LEDE = "These tabs stay awake, so they hold memory. Each says why; choose what happens to it.";
export const PROTECTED_EMPTY = 'No tabs are protected right now. A tab playing sound, on a call, with unsent typing, pinned, or kept by you would show here.';
export const REASON_TEXT = {
  call: 'On a call',
  screen: 'Sharing your screen',
  sound: 'Playing sound',
  soundRecent: 'Played sound recently',
  typing: 'Unsent typing',
  kept: 'Kept by you',
  pinned: 'Pinned',
  session: 'In the session',
};
export const KEEP = 'Keep';
export const KEPT = 'Kept';
export const SLEEP = 'Sleep';
export const CLOSE = 'Close';

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
  };
}

// ---- sessions ----
export const START = 'Start a session';
export const START_NOTE = 'Choose the tabs a task needs, like a meeting. The rest sleep, and reload only if you click them.';
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
  if (resting) parts.push('Extensions not on your safe list rest until it ends.');
  return parts.join(' ');
}
// What keeps an unticked tab loaded, said of one tab and of several.
const STAY_WHY = {
  call: ['is on a call', 'are on calls'],
  screen: ['is sharing your screen', 'are sharing your screen'],
  sound: ['is playing sound', 'are playing sound'],
  typing: ['has unsent typing', 'have unsent typing'],
  kept: ['is kept by you', 'are kept by you'],
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
  rested: (n) => (n === 0 ? 'No extensions to turn off: the rest are on your safe list.' : `Turned off ${plural(n, 'extension')} until memory clears.`),
  restNeedsYes: 'Cool Head for Chrome needs your yes before it can turn extensions off. Open it from the toolbar to allow that.',
  started: (n, s) => `Session started with ${plural(n, 'tab')}. ${s === 0 ? 'No other tabs needed to sleep.' : `${plural(s, 'other tab')} ${s === 1 ? 'is' : 'are'} asleep.`}`,
  ended: 'Session ended. Nothing reloaded.',
  saved: (n, name, already) => `Session ended. Saved ${plural(n, 'tab')} as ${quoted(name)}.${already > 0 ? ` ${plural(already, 'tab was', 'tabs were')} already in a group, so ${already === 1 ? 'it stays' : 'they stay'} there.` : ''}`,
  levelSet: (l) => `${LEVEL_NAME[l]} chosen.`,
  failed: "That didn't work: Chrome refused it. Nothing changed.",
};

// ---- settings ----
export const SETTINGS = 'Settings';
export const BACK = 'Back';
export const LEAVE_TITLE = 'When you leave a tab';
export const LEAVE_30 = 'After 30 seconds';
export const LEAVE_30_WHY = 'Going back and forth within half a minute never reloads.';
export const LEAVE_0 = 'At once';
export const LEAVE_0_WHY = 'Frees memory sooner, but a tab you go back to reloads.';
export const LEAVE_NOTE = 'Applies to Light, Balanced, and Focus.';

export const SITES_TITLE = 'Unsent typing and calls';
export const SITES_ON = "On: tabs with unsent typing, or using the camera, microphone, or screen sharing, don't sleep on their own, so you don't lose what you typed or drop out of a call.";
export const SITES_OFF = 'Off: a tab with unsent typing can sleep, and what you typed is lost when it reloads. A call that has been quiet for 10 minutes can sleep too, which ends it.';
export const SITES_HOW = 'Turning it on lets Cool Head for Chrome check, on each site, whether a text box has been typed in and whether the camera, microphone, or screen sharing is on. It never reads what you type, and nothing leaves your computer. Chrome will ask you to allow it to "read and change all your data on all websites", which is how Chrome words any access to every site.';
export const TURN_ON = 'Turn on';
export const TURN_OFF = 'Turn off';

export const REST_TITLE = 'Rest extensions';
export const REST_TOGGLE = 'Rest extensions during a session and when memory is very tight';
export const REST_WHY = 'Extensions not on your safe list turn off, and back on when the session ends or memory clears. Turning one off closes its open pages and stops what it is doing until then.';
export const REST_NEEDS = 'Chrome asks you to allow "Manage your apps, extensions, and themes" the first time, since that is what turning extensions off needs.';
export const REST_SET_UP = 'Choose the safe list';
export const SAFE_TITLE = 'Your extensions safe list';
export const SAFE_LEDE = "Resting turns an extension off until the session ends or memory clears, which closes its pages and stops what it's doing. So password managers, blockers, VPNs, and security tools start as Always on: resting them would lock your passwords, let ads and trackers through, or drop your VPN.";
export const SAFE_ON = 'Always on';
export const SAFE_REST = 'Rest when memory is tight';
export const MOVE_TO_REST = 'Rest it';
export const MOVE_TO_ON = 'Keep on';
export const SAFE_ADMIN = 'Installed by your organization, so Chrome keeps it on.';
export const SAFE_DONE = 'Done';
export const SAFE_EMPTY = 'You have no other extensions, so there is nothing to rest.';
export const EXT_WHY = {
  admin: 'Installed by your organization',
  password: 'Password manager',
  blocker: 'Blocks ads or trackers',
  vpn: 'VPN or proxy',
  security: 'Security tool',
  other: '',
};
export function restingNow(n) { return n === 0 ? '' : `${plural(n, 'extension is', 'extensions are')} resting now.`; }

export const ABOUT_TITLE = 'About';
export function about(version) {
  return `Version ${version}. Free and open source under the AGPL. Nothing leaves your computer: no network use and no analytics.`;
}

// ---- setup page ----
export const SETUP_TITLE = 'Cool Head for Chrome is ready';
export const SETUP_LEDE = "Tabs you aren't using will sleep: they stay in your tab bar and reload when you click them, which frees memory for what you're doing.";
export const SETUP_ASK = 'One choice first: protect unsent typing and calls?';
export const SETUP_WHY = "Then a tab with unsent typing, or using the camera, microphone, or screen sharing, doesn't sleep on its own, so you don't lose what you typed or drop out of a call.";
export const SETUP_YES = 'Protect them';
export const SETUP_NO = 'Not now';
export const SETUP_NO_COST = 'If you choose Not now, a tab with unsent typing can sleep, and what you typed is lost when it reloads; a call that has been quiet for 10 minutes can sleep too, which ends it. You can turn this on later in Settings.';
export const SETUP_DONE_YES = 'Done. Tabs with unsent typing or on a call stay loaded. You can close this tab.';
export const SETUP_DONE_NO = 'Done. You can turn this on later in Settings. You can close this tab.';
export const SETUP_REFUSED = "Chrome didn't allow it, so this stays off. You can try again later in Settings.";
export const SETUP_NEXT = 'Open Cool Head for Chrome from the puzzle piece in the toolbar; pin it there to see how many tabs are asleep.';

// ---- the right-click menu ----
export const MENU_KEEP = 'Keep this tab loaded';
