// The link to Cool Head, version 1: the extension's side of PROTOCOL.md.
// Unknown message types and fields are ignored, so either side can be newer. Only counts and the person's
// level cross the link: no addresses, titles, or extension names.
import { PROTOCOL_REASONS } from './reasons.js';
import { MEMORY_STATES } from './auto.js';

export const HOST_NAME = 'io.github.thephildiamond.coolhead';
export const VERSION = 1;
export const LEVELS = ['auto', 'light', 'balanced', 'focus'];
export const ACTIONS = ['sleepHidden', 'closeDuplicates', 'hideUnusedGroups', 'restExtensions', 'openExtensionsList', 'openPopup'];
export const REPORT_EVERY_MS = 10 * 1000;

const int = (n) => (Number.isFinite(n) && n >= 0 ? Math.floor(n) : 0);

export function hello(extensionVersion, level) {
  return { v: VERSION, type: 'hello', extension: String(extensionVersion), browser: 'chrome', level: LEVELS.includes(level) ? level : 'balanced' };
}

export function report({ asleep, held, session, duplicates, extensionsResting, level }) {
  return {
    v: VERSION,
    type: 'report',
    asleep: int(asleep),
    held: Object.fromEntries(PROTOCOL_REASONS.map((r) => [r, int(held?.[r])])),
    session: { active: Boolean(session?.active), tabs: int(session?.tabs) },
    duplicates: int(duplicates),
    extensionsResting: int(extensionsResting),
    level: LEVELS.includes(level) ? level : 'balanced',
  };
}

export function result(id, ok, done, count) {
  return { v: VERSION, type: 'result', id: String(id ?? ''), ok: Boolean(ok), done: String(done || ''), count: int(count) };
}

// Normalizes what arrives from the host into one of:
// { kind: 'link', app: 'running' | 'notRunning' } | { kind: 'hello', app } | { kind: 'state', state } |
// { kind: 'request', id, action } | { kind: 'ignore', why }
export function parseIncoming(msg) {
  if (!msg || typeof msg !== 'object' || Array.isArray(msg)) return { kind: 'ignore', why: 'not an object' };
  // The host's own "link" message is written without "v" in the spec; accept a missing v, refuse an older one.
  if (msg.v !== undefined && !(Number.isInteger(msg.v) && msg.v >= VERSION)) return { kind: 'ignore', why: 'version' };
  switch (msg.type) {
    case 'link':
      if (msg.app === 'running' || msg.app === 'notRunning') return { kind: 'link', app: msg.app };
      return { kind: 'ignore', why: 'link app' };
    case 'hello':
      return { kind: 'hello', app: typeof msg.app === 'string' ? msg.app : '' };
    case 'state': {
      if (!MEMORY_STATES.includes(msg.memory)) return { kind: 'ignore', why: 'memory' };
      const num = (x) => (typeof x === 'number' && Number.isFinite(x) ? x : null);
      return {
        kind: 'state',
        state: {
          memory: msg.memory,
          freeMB: num(msg.freeMB),
          chromeMB: num(msg.chromeMB),
          hiddenTabsMB: num(msg.hiddenTabsMB),
          extensionsMB: num(msg.extensionsMB),
          auto: msg.auto !== false,
        },
      };
    }
    case 'request':
      if (!ACTIONS.includes(msg.action)) return { kind: 'ignore', why: 'action' };
      return { kind: 'request', id: msg.id == null ? '' : String(msg.id), action: msg.action };
    default:
      return { kind: 'ignore', why: 'type' };
  }
}

// Reports go out on change, at most every 10 seconds.
export function sameReport(a, b) {
  return JSON.stringify(a) === JSON.stringify(b);
}

export function reportDue(lastSentAt, now) {
  return lastSentAt == null || now - lastSentAt >= REPORT_EVERY_MS;
}
