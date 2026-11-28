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
    tonal: all.filter((e) => e.tagName === 'BUTTON' && e.className.split(/\s+/).includes('tonal')).map((e) => e.attrs['data-key']),
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

// Tonal: a card's main button that isn't the recommended one is tinted, the same size, never the plain gray that reads
// as switched off; every main button on home is one or the other.
test('every main button on home that is not blue is tonal', () => {
  const main = ['start', 'dups', 'extrec-allow'];
  const cases = [
    ['duplicates awake, extensions card', pair(), state()],
    ['duplicates asleep, extensions card', pair({ discarded: true }), state()],
    ['extensions card alone', [tab({ active: true })], state()],
    ['nothing', [tab({ active: true })], state({ extRecDismissed: true })],
  ];
  for (const [name, tabs, s] of cases) {
    const d = draw(tabs, s);
    const shown = [...d.blue, ...d.tonal];
    assert.equal(d.blue.length, 1, name);
    assert.ok(d.tonal.every((k) => main.includes(k)), name);
    assert.ok(!d.tonal.some((k) => d.blue.includes(k)), name);
    assert.ok(shown.includes('start'), name);
    if (name !== 'nothing') assert.ok(shown.includes('extrec-allow'), name);
    if (name.startsWith('duplicates')) assert.ok(shown.includes('dups'), name);
  }
});

// The pale blue button is the same size as the blue one wherever both can show: alone and in a row of buttons, where
// the recommended one is smaller (a tonal button bigger than the recommendation would undo the point of it).
test('a tonal button is the same size as a blue one, alone and in a row', async () => {
  const fs = await import('node:fs');
  const css = fs.readFileSync(new URL('../popup/popup.css', import.meta.url), 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');
  const rules = [...css.matchAll(/([^{}]+)\{([^}]*)\}/g)].map((m) => ({ sel: m[1].split(',').map((x) => x.trim()), body: m[2] }));
  const value = (selector, prop) => {
    let v = null;
    for (const r of rules) if (r.sel.includes(selector)) { const m = r.body.match(new RegExp(`(?:^|;)\\s*${prop}\\s*:\\s*([^;]+)`)); if (m) v = m[1].trim(); }
    return v;
  };
  for (const prop of ['min-height', 'font-size', 'border-radius']) {
    assert.equal(value('.btn.tonal', prop), value('.btn.primary', prop), `alone: ${prop}`);
    assert.equal(value('.row .btn.tonal', prop), value('.row .btn.primary', prop), `in a row: ${prop}`);
    assert.ok(value('.row .btn.primary', prop), `in a row: ${prop} set`);
  }
});
