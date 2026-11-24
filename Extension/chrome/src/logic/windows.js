// Saved windows: a window saved as a bookmark folder and closed, then reopened with every tab asleep (decided 24
// November 2026). The folders live in one parent folder, "Cool Head windows", under Other bookmarks, so they work
// with Chrome's own Open all in new window even without this extension. Reopening one removes it, so they never pile
// up. Pure functions here; the worker does the bookmark and tab calls (src/worker.js).
import { windowFolderName } from './words.js';

const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

// "24 November 2026", the way dates read everywhere else in Cool Head.
export function dayText(at) {
  const d = new Date(at);
  return `${d.getDate()} ${MONTHS[d.getMonth()]} ${d.getFullYear()}`;
}

// Only pages that open again from a bookmark: no blank new tabs, and nothing without an address.
export function savable(url) {
  if (!url) return false;
  if (/^chrome:\/\/(newtab|new-tab-page)\b/.test(url) || url === 'about:blank') return false;
  return /^(https?|file|ftp|chrome|chrome-extension):/.test(url);
}

function hostOf(url) {
  try { return new URL(url).hostname.replace(/^www\./, '') || url; } catch { return url; }
}

// The folder's words when none are given: the window's main site, and how many others ("mail.example.com and 4
// more"), so no folder is ever named by its date alone.
export function defaultWords(urls) {
  const counts = new Map();
  for (const u of urls) { const host = hostOf(u); counts.set(host, (counts.get(host) || 0) + 1); }
  const hosts = [...counts.entries()].sort((a, b) => b[1] - a[1]).map(([host]) => host);
  if (!hosts.length) return 'Saved window';
  return hosts.length === 1 ? hosts[0] : `${hosts[0]} and ${hosts.length - 1} more`;
}

// At most 40 characters of the person's words, on one line.
export function cleanWords(words) {
  return String(words || '').replace(/\s+/g, ' ').trim().slice(0, 40).trim();
}

export function folderTitle(words, n, at) {
  return windowFolderName(words, n, dayText(at));
}

// The folder's own words: its title up to the first " · ", so a folder the person renamed still shows their name.
export function wordsOf(title) {
  return String(title || '').split(' · ')[0] || title;
}

// "today", "yesterday", "3 days ago", "a week ago", "3 weeks ago", "2 months ago".
export function savedAgo(at, now) {
  const days = Math.floor(Math.max(0, now - at) / 86400000);
  if (days < 1) return 'today';
  if (days < 2) return 'yesterday';
  if (days < 7) return `${days} days ago`;
  const weeks = Math.floor(days / 7);
  if (days < 31) return weeks === 1 ? 'a week ago' : `${weeks} weeks ago`;
  const months = Math.floor(days / 30);
  return months <= 1 ? 'a month ago' : `${months} months ago`;
}

// Every address in a saved folder, in order, including any in folders inside it, so links the person added
// anywhere in it come back too.
export function urlsIn(node) {
  return pagesIn(node).map((p) => p.url);
}

// Each saved page's address and title, in order: reopening puts each to sleep before it has loaded, so its title
// comes from the bookmark.
export function pagesIn(node) {
  const out = [];
  const walk = (n) => { if (n.url) out.push({ url: n.url, title: n.title || '' }); for (const c of n.children || []) walk(c); };
  for (const c of node.children || []) walk(c);
  return out;
}

// The parent folder's children, split: folders Cool Head saved (by the IDs it remembers), newest first, and anything
// else, which Tidy moves out and nothing ever deletes. `records` is [{ id, savedAt }].
export function splitParent(children, records, now) {
  const byId = new Map(records.map((r) => [r.id, r]));
  const saved = [];
  const others = [];
  for (const c of children || []) {
    const r = byId.get(c.id);
    if (r && !c.url) {
      saved.push({ id: c.id, name: c.title, words: wordsOf(c.title), n: urlsIn(c).length, savedAt: r.savedAt, ago: savedAgo(r.savedAt, now) });
    } else {
      others.push({ id: c.id, title: c.title || c.url || 'Untitled' });
    }
  }
  saved.sort((a, b) => b.savedAt - a.savedAt);
  return { saved, others };
}
