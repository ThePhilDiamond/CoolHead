// Draws home with the real render.js through a small stand-in for the page, and counts the blue buttons: one at a
// time, whatever shows (option cues), with the recommendation's line tied to its button.
import { test } from 'node:test';
import assert from 'node:assert/strict';

class El {
  constructor(tag) { this.tagName = tag.toUpperCase(); this.children = []; this.attrs = {}; this.dataset = {}; this.style = {}; this._text = ''; this.className = ''; this.listeners = {}; }
  setAttribute(k, v) { if (k === 'class') this.className = String(v); else this.attrs[k] = String(v); if (k.startsWith('data-')) this.dataset[k.slice(5).replace(/-./g, (m) => m[1].toUpperCase())] = String(v); }
  getAttribute(k) { return k === 'class' ? this.className : this.attrs[k] ?? null; }
  addEventListener(n, f) { this.listeners[n] = f; }
  append(...k) { for (const c of k) this.children.push(typeof c === 'string' ? Object.assign(new El('#text'), { _text: c }) : c); }
  appendChild(c) { this.append(c); return c; }
  replaceChildren(...k) { this.children = []; this.append(...k); }
  set textContent(v) { this._text = String(v); this.children = []; }
  get textContent() { return this._text + this.children.map((c) => c.textContent).join(''); }
  get id() { return this.attrs.id; }
  get classList() { const el = this; return { toggle() {}, contains: (c) => el.className.split(/\s+/).includes(c) }; }
  get childNodes() { return this.children; }
  focus() {}
  *walk() { yield this; for (const c of this.children) yield* c.walk(); }
  querySelectorAll(sel) {
    const m = sel.match(/^\[data-key="(.*)"\]$/);
    return [...this.walk()].filter((e) => e !== this && (m ? e.attrs['data-key'] === m[1] : sel.split(/[ ,]/).some((s) => s === e.tagName.toLowerCase() || (s.startsWith('.') && e.className.split(/\s+/).includes(s.slice(1))))));
  }
  querySelector(sel) { return this.querySelectorAll(sel)[0] || null; }
  get scrollTop() { return 0; } set scrollTop(v) {}
}
globalThis.document = { createElement: (t) => new El(t), createElementNS: (_, t) => new El(t), importNode: (n) => n, activeElement: null, body: {} };
globalThis.DOMParser = class { parseFromString() { return { documentElement: { childNodes: [] } }; } };
globalThis.getComputedStyle = () => ({ color: 'rgb(0,0,0)' });
globalThis.CSS = { escape: (s) => s };

const { render } = await import('../popup/render.js');
const { buildView } = await import('../src/logic/view.js');
const { LOCAL_DEFAULTS, SESSION_DEFAULTS } = await import('../src/store.js');
const { tab, NOW, MIN } = await import('./helpers.js');
function state(over = {}) { return { ...structuredClone(LOCAL_DEFAULTS), ...structuredClone(SESSION_DEFAULTS), ...over }; }
let k = 0;
const pair = (o = {}) => { const u = `https://x.example/${k++}`; return [tab({ url: u, title: 'A', lastAccessed: NOW - MIN }), tab({ url: u, title: 'A', ...o })]; };
const on = new Proxy({}, { get: () => () => {} });

function draw(tabs, s, ui = {}) {
  const v = buildView({ tabs, s, now: NOW, focusedWindowId: 1, isMac: true, memInfo: null, version: '1.0.0' });
  const root = new El('div');
  render(root, v, { screen: 'home', ticked: new Set(), ...ui }, on);
  const all = [...root.walk()];
  return {
    blue: all.filter((e) => e.tagName === 'BUTTON' && e.className.split(/\s+/).includes('primary')).map((e) => e.attrs['data-key']),
    described: all.filter((e) => e.attrs['aria-describedby']).every((e) => all.some((x) => x.attrs.id === e.attrs['aria-describedby'])),
    lines: all.filter((e) => e.className === 'recline').length,
    live: all.filter((e) => ['alert', 'status'].includes(e.attrs.role)).length,
  };
}
const session = { active: true, tabIds: [], startedAt: NOW - MIN };

test('one blue button on home, whatever shows, and its line tied to it', () => {
  const cases = [
    ['duplicates awake, extensions card', pair(), state(), ['dups']],
    ['duplicates asleep, extensions card', pair({ discarded: true }), state(), ['extrec-allow']],
    ['extensions card alone', [tab({ active: true })], state(), ['extrec-allow']],
    ['nothing', [tab({ active: true })], state({ extRecDismissed: true }), ['start']],
    ['a session running, nothing', [tab({ active: true })], state({ extRecDismissed: true, session }), []],
  ];
  for (const [name, tabs, s, blue] of cases) {
    const d = draw(tabs, s);
    assert.deepEqual(d.blue, blue, name);
    assert.ok(d.described, name);
    assert.ok(d.lines <= 1, name);
  }
});

test('the Save form of a session is the one blue button: no card is blue then', () => {
  const d = draw(pair(), state({ session }), { ending: true });
  assert.deepEqual(d.blue, ['save']);
  assert.equal(d.lines, 0);
});

test('a duplicates result or failure is not a live region rebuilt on each redraw', () => {
  assert.equal(draw([tab({ active: true })], state({ closedDups: { at: NOW - 1000, groups: [{ title: 'A', n: 1 }] } })).live, 0);
  assert.equal(draw(pair(), state({ closedDups: { at: NOW - 1000, failed: true } })).live, 0);
});
