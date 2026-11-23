// Pausing extensions: turns off extensions not in use, during a session or more broadly, sparing those kept on (README,
// "What it does"). Chrome tells an extension nothing about when another was last used or what memory it holds, so
// "not in use" means "not kept on".

const BLOCKER_PERMS = ['declarativeNetRequest', 'declarativeNetRequestWithHostAccess', 'declarativeNetRequestFeedback', 'webRequestBlocking'];
const VPN_PERMS = ['proxy', 'vpnProvider'];
// Chrome's permissions can't tell a password manager or an antivirus from other extensions that ask for the
// same things, so the name helps here. It is only a starting guess, and it errs toward Always on: resting a
// password manager locks it, which costs the person more than leaving one extra extension on.
const PASSWORD_NAMES = /password|passkey|bitwarden|lastpass|dashlane|keeper|enpass|roboform|nordpass|proton pass|keychain/i;
const SECURITY_NAMES = /security|antivirus|anti-virus|malware|phishing|norton|mcafee|avast|kaspersky|bitdefender|sophos|trend micro/i;
// Banking and payments (a bank's own protection, a payment wallet), signing in to work, and accessibility: turning
// one off can lock a payment, end a sign-in, or take away what someone needs to read the screen.
const BANK_NAMES = /\bbank|banking|trusteer|rapport|credit union|paypal|wallet|metamask|coinbase/i;
const SIGNIN_NAMES = /\bsso\b|single sign|okta|duo\b|authenticator|yubi|jumpcloud|onelogin|endpoint verification|microsoft single sign|enterprise sign/i;
const ACCESS_NAMES = /screen reader|chromevox|read aloud|text.to.speech|dyslexi|high contrast|color enhancer|colorblind|accessib/i;

// Whether it runs on every site you open: its scripts then load in every tab, adding memory to each. Chrome tells
// an extension nothing about another's memory, so this is the best sign of one that costs the most.
export function everySite(ext) {
  return (ext.hostPermissions || []).some((p) => p === '<all_urls>' || /^(\*|https?):\/\/\*\//.test(p));
}

// Returns 'admin' | 'password' | 'bank' | 'signin' | 'access' | 'vpn' | 'blocker' | 'security' | 'other'.
export function kindOf(ext) {
  const perms = ext.permissions || [];
  if (ext.installType === 'admin' || ext.mayDisable === false) return 'admin';
  if (PASSWORD_NAMES.test(ext.name || '')) return 'password';
  if (BANK_NAMES.test(ext.name || '')) return 'bank';
  if (SIGNIN_NAMES.test(ext.name || '')) return 'signin';
  if (ACCESS_NAMES.test(ext.name || '')) return 'access';
  if (perms.some((p) => VPN_PERMS.includes(p))) return 'vpn';
  if (perms.some((p) => BLOCKER_PERMS.includes(p))) return 'blocker';
  if (perms.includes('privacy') || SECURITY_NAMES.test(ext.name || '')) return 'security';
  return 'other';
}

export function restable(ext, selfId) {
  return ext.type === 'extension' && ext.id !== selfId;
}

// safeList: { decided: bool, alwaysOn: [id], rest: [id] }; an extension in neither (installed later) gets the guess.
export function isAlwaysOn(ext, safeList) {
  const kind = kindOf(ext);
  if (kind === 'admin') return true;
  if (safeList?.alwaysOn?.includes(ext.id)) return true;
  if (safeList?.rest?.includes(ext.id)) return false;
  return kind !== 'other';
}

// Extensions with a tab open on one of their own pages, such as a tab another extension has suspended, a saved
// list of tabs, or a vault. Chrome closes those tabs when the extension is turned off, so such an extension is never
// paused while any is open: the tabs, and anything in them, would be gone.
export function withOpenTabs(tabs) {
  const ids = new Set();
  for (const t of tabs) {
    const m = /^chrome-extension:\/\/([a-p]{32})\//.exec(t.url || t.pendingUrl || '');
    if (m) ids.add(m[1]);
  }
  return ids;
}

export function columns(exts, safeList, selfId, open = new Set()) {
  const on = [];
  const rest = [];
  for (const e of exts) {
    if (!restable(e, selfId)) continue;
    const row = { id: e.id, name: e.name, kind: kindOf(e), enabled: e.enabled, open: open.has(e.id), everySite: everySite(e) };
    (isAlwaysOn(e, safeList) ? on : rest).push(row);
  }
  const byName = (a, b) => a.name.localeCompare(b.name);
  // the ones that run on every site first among those that pause, as they cost the most
  const heavyFirst = (a, b) => Number(b.everySite) - Number(a.everySite) || byName(a, b);
  return { alwaysOn: on.sort(byName), rest: rest.sort(heavyFirst) };
}

export function move(safeList, id, toAlwaysOn) {
  const alwaysOn = (safeList?.alwaysOn || []).filter((x) => x !== id);
  const rest = (safeList?.rest || []).filter((x) => x !== id);
  (toAlwaysOn ? alwaysOn : rest).push(id);
  return { decided: true, alwaysOn, rest };
}

// Which extensions to turn off now: on, not kept on, ones Chrome lets the person turn off, and none with
// its own tabs open (withOpenTabs).
export function restPlan(exts, safeList, selfId, open = new Set()) {
  return exts.filter((e) => restable(e, selfId) && e.enabled && !isAlwaysOn(e, safeList) && !open.has(e.id)).map((e) => e.id);
}

// Rested extensions come back when no reason to rest is left. reasons: { session, memory }.
export function shouldWake(rest) {
  return (rest?.ids?.length ?? 0) > 0 && !rest.session && !rest.memory;
}
