// The test log: what the extension did and why, kept in this computer's Chrome storage so a test run can be read back
// afterward on the Log page (log/log.html). Only the test build writes it (build.js); in the store build every call
// returns at once and nothing is kept.
//
// Sites appear by host name only (logic/explain.js, host), never a full address, a page title, or anything typed.
import { TEST_BUILD } from './build.js';

export const LOG_KEY = 'testLog';
export const LOG_MAX = 2000;

let queue = Promise.resolve();

// kind: a short word the Log page can filter on (slept, check, link, memory, coolHead, you, rest, page, chrome, error).
export function log(kind, text, data) {
  if (!TEST_BUILD) return Promise.resolve();
  const entry = { at: Date.now(), kind, text, ...(data ? { data } : {}) };
  // One write at a time, so two events at once can't drop each other.
  queue = queue.then(async () => {
    const got = await chrome.storage.local.get(LOG_KEY);
    const all = Array.isArray(got[LOG_KEY]) ? got[LOG_KEY] : [];
    all.push(entry);
    await chrome.storage.local.set({ [LOG_KEY]: all.slice(-LOG_MAX) });
  }).catch(() => {});
  return queue;
}

// For promise chains: logs the error as well as printing it, so a failure in a test shows up on the Log page.
export function oops(e) {
  console.error(e);
  const where = String(e?.stack || '').split('\n').slice(1, 2).join('').trim();
  log('error', String(e?.message || e), where ? { where } : null);
}

export const testBuild = TEST_BUILD;
