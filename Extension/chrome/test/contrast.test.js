// Every color pair the popup uses, measured from popup.css in light and dark against WCAG 2.2 AA:
// 4.5:1 for text, 3:1 for icons, control edges, and the focus ring (docs/BRAND.md, "Accessibility").
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const css = fs.readFileSync(new URL('../popup/popup.css', import.meta.url), 'utf8');
const tokens = {};
for (const m of css.matchAll(/--([a-z-]+):\s*light-dark\((#[0-9A-Fa-f]{6}),\s*(#[0-9A-Fa-f]{6})\)/g)) tokens[m[1]] = { light: m[2], dark: m[3] };

function luminance(hex) {
  const [r, g, b] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255)
    .map((c) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4));
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
export function ratio(a, b) {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}

const WASHES = ['wash-warn', 'wash-good', 'wash-bad', 'wash-none'];
const TEXT = [
  ['text', 'bg'], ['muted', 'bg'], ['text', 'card'], ['muted', 'card'], ['text', 'group'], ['muted', 'group'],
  ['text', 'chip'], ['text', 'fill'], ['muted', 'fill'], ['danger', 'fill'], ['danger', 'bg'], ['danger', 'card'],
  ['accent', 'bg'], ['accent', 'card'], ['on-accent', 'accent'], ['text', 'accent-soft'], ['muted', 'accent-soft'], ['text', 'tint'], ['text', 'tint-hover'],
  ...WASHES.flatMap((w) => [['text', w], ['muted', w]]),
];
const EDGES = [
  ['control', 'bg'], ['control', 'card'], ['control', 'accent-soft'], ...WASHES.map((w) => ['control', w]),
  ['accent', 'bg'], ['accent', 'fill'], ['accent', 'accent-soft'], ['accent', 'card'], ...WASHES.map((w) => ['accent', w]),
  ['tint-edge', 'bg'], ['tint-edge', 'card'],
  ['danger', 'bg'], ['danger', 'card'], ...WASHES.map((w) => ['linked', w]), ...WASHES.map((w) => ['muted', w]),
];

test('the popup defines both modes for every color token', () => {
  for (const name of ['bg', 'text', 'muted', 'card', 'accent', 'on-accent', 'control', 'danger', 'linked', ...WASHES]) {
    assert.ok(tokens[name], `missing --${name}`);
  }
});

test('Cool Head blue is the brand guide\'s: #1769D1 in light, #4A9EFF in dark, with white and near-black on it', () => {
  assert.deepEqual(tokens.accent, { light: '#1769D1', dark: '#4A9EFF' });
  assert.deepEqual(tokens['on-accent'], { light: '#FFFFFF', dark: '#1A1A1A' });
});

for (const mode of ['light', 'dark']) {
  test(`text is at least 4.5:1 in ${mode}`, () => {
    for (const [fg, bg] of TEXT) {
      const r = ratio(tokens[fg][mode], tokens[bg][mode]);
      assert.ok(r >= 4.5, `${fg} on ${bg}: ${r.toFixed(2)}:1`);
    }
  });
  test(`icons, control edges, and focus are at least 3:1 in ${mode}`, () => {
    for (const [fg, bg] of EDGES) {
      const r = ratio(tokens[fg][mode], tokens[bg][mode]);
      assert.ok(r >= 3, `${fg} against ${bg}: ${r.toFixed(2)}:1`);
    }
  });
}
