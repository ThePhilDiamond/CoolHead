// The words rule on contractions, as GOV.UK's style guide has it: positive ones (it's, you're, you'll) are fine;
// negative ones (can't, don't) are spelled out, since many readers misread them as the opposite, and so are
// conditional ones (should've, would've), which are hard to read. Checked on every line of the extension's code that
// isn't a comment, so a string anywhere (words, log lines, the setup page) keeps the rule.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
// an apostrophe as it may be written in code or HTML: straight or curly, escaped (\' or \u2019), or an entity
const Q = String.raw`(?:\\?['’]|\\u2019|&rsquo;|&#0?39;|&#x27;|&apos;)`;
const banned = new RegExp(String.raw`\b[A-Za-z]*n${Q}t\b|\b(?:should|could|would|might|must)${Q}ve\b`, 'i');

function files(dir) {
  return readdirSync(dir).flatMap((n) => {
    const p = join(dir, n);
    return statSync(p).isDirectory() ? files(p) : /\.(js|mjs|html|json)$/.test(n) ? [p] : [];
  });
}

// a line's code, without comments: whole-line comments, /* … */ inside it, and // after a space (not in a URL)
function code(line) {
  if (/^\s*(\/\/|\*|\/\*)/.test(line)) return '';
  return line.replace(/\/\*.*?\*\//g, '').replace(/\s\/\/\s.*$/, '');
}

export function offenders(text) {
  return text.split('\n').map((l, i) => [i + 1, code(l)]).filter(([, c]) => banned.test(c)).map(([n, c]) => `${n}: ${c.trim().slice(0, 100)}`);
}

test('no negative or conditional contraction in the extension\'s words', () => {
  // the folders the store package ships, and the manifest, whose summary and shortcut names show in Chrome
  const found = [...['src', 'popup', 'setup', 'parked', 'content'].flatMap((d) => files(join(root, d))), join(root, 'manifest.json')]
    .flatMap((f) => offenders(readFileSync(f, 'utf8')).map((o) => `${f.slice(root.length + 1)}:${o}`));
  assert.deepEqual(found, []);
});

test('the check finds them, and leaves positive ones and comments alone', () => {
  assert.equal(offenders('const A = "It can\'t reload.";').length, 1);
  assert.equal(offenders('const A = `Chrome didn’t allow it`;').length, 1);
  assert.equal(offenders('const A = "You should\'ve saved it";').length, 1);
  assert.equal(offenders('const A = "It\'s asleep, and you\'re offline.";').length, 0);
  assert.equal(offenders('// a tab that can\'t reload').length, 0);
  assert.equal(offenders('x(); // it doesn\'t count').length, 0);
  const bs = String.fromCharCode(92);
  assert.equal(offenders("const A = 'Chrome didn" + bs + "'t allow it';").length, 1);
  assert.equal(offenders('const A = "It can' + bs + 'u2019t";').length, 1);
  assert.equal(offenders('<p>It can&rsquo;t reload.</p>').length, 1);
  assert.equal(offenders('<p>It can&#39;t reload.</p>').length, 1);
  assert.equal(offenders('const A = "DON\'T CLOSE";').length, 1);
  assert.equal(offenders("const A = `${n === 1 ? 'is' : 'are'}n't`;").length, 1);
  assert.equal(offenders("const A = 'the tab' + bs + \"'s title\";").length, 0);
});

// Not caught: a contraction joined from parts ("didn" + "'t"); none is written that way.

test('the store summary fits the 132 characters the Chrome Web Store allows', () => {
  const m = JSON.parse(readFileSync(join(root, 'manifest.json'), 'utf8'));
  assert.ok(m.description.length <= 132, `${m.description.length} characters`);
});
