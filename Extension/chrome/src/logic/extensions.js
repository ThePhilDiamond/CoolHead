// Rest extensions (Phil, 21 November 2026: "Have we got a "temporarily disable extensions not in use" option,
// whether as part of a session or more broadly? Again we can have a safe list for this."). Chrome tells an
// extension nothing about when another was last used or what memory it holds, so "not in use" means "not on
// your safe list" (design, "Rest extensions").

const BLOCKER_PERMS = ['declarativeNetRequest', 'declarativeNetRequestWithHostAccess', 'declarativeNetRequestFeedback', 'webRequestBlocking'];
const VPN_PERMS = ['proxy', 'vpnProvider'];
// Chrome's permissions can't tell a password manager or an antivirus from other extensions that ask for the
// same things, so the name helps here. It is only a starting guess, and it errs toward Always on: resting a
// password manager locks it, which costs the person more than leaving one extra extension on.
const PASSWORD_NAMES = /password|passkey|bitwarden|lastpass|dashlane|keeper|enpass|roboform|nordpass|proton pass|keychain/i;
const SECURITY_NAMES = /security|antivirus|anti-virus|malware|phishing|norton|mcafee|avast|kaspersky|bitdefender|sophos|trend micro/i;

// Returns 'admin' | 'password' | 'vpn' | 'blocker' | 'security' | 'other'.
export function kindOf(ext) {
  const perms = ext.permissions || [];
  if (ext.installType === 'admin' || ext.mayDisable === false) return 'admin';
  if (PASSWORD_NAMES.test(ext.name || '')) return 'password';
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

export function columns(exts, safeList, selfId) {
  const on = [];
  const rest = [];
  for (const e of exts) {
    if (!restable(e, selfId)) continue;
    const row = { id: e.id, name: e.name, kind: kindOf(e), enabled: e.enabled };
    (isAlwaysOn(e, safeList) ? on : rest).push(row);
  }
  const byName = (a, b) => a.name.localeCompare(b.name);
  return { alwaysOn: on.sort(byName), rest: rest.sort(byName) };
}

export function move(safeList, id, toAlwaysOn) {
  const alwaysOn = (safeList?.alwaysOn || []).filter((x) => x !== id);
  const rest = (safeList?.rest || []).filter((x) => x !== id);
  (toAlwaysOn ? alwaysOn : rest).push(id);
  return { decided: true, alwaysOn, rest };
}

// Which extensions to turn off now: on, not on the safe list, and ones Chrome lets the person turn off.
export function restPlan(exts, safeList, selfId) {
  return exts.filter((e) => restable(e, selfId) && e.enabled && !isAlwaysOn(e, safeList)).map((e) => e.id);
}

// Rested extensions come back when no reason to rest is left. reasons: { session, memory }.
export function shouldWake(rest) {
  return (rest?.ids?.length ?? 0) > 0 && !rest.session && !rest.memory;
}
