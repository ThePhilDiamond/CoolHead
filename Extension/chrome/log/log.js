// The Log page for the test build: reads the log the worker keeps (src/log.js) and shows it newest first, with
// Copy, Save as a file, and Clear. It reads storage only; it never sends anything anywhere.
import { LOG_KEY } from '../src/log.js';
import { clock, day, logText } from '../src/logic/explain.js';

const rows = document.getElementById('rows');
const kindSelect = document.getElementById('kind');
const said = document.getElementById('said');
const empty = document.getElementById('empty');
let entries = [];

async function load() {
  const got = await chrome.storage.local.get(LOG_KEY);
  entries = Array.isArray(got[LOG_KEY]) ? got[LOG_KEY] : [];
  draw();
}

function cell(cls, text) {
  const td = document.createElement('td');
  td.className = cls;
  td.textContent = text;
  return td;
}

function draw() {
  const kinds = [...new Set(entries.map((e) => e.kind))].sort();
  const chosen = kindSelect.value;
  kindSelect.replaceChildren(new Option('everything', ''), ...kinds.map((k) => new Option(k, k)));
  kindSelect.value = kinds.includes(chosen) ? chosen : '';
  const shown = entries.filter((e) => !kindSelect.value || e.kind === kindSelect.value).slice().reverse();
  rows.replaceChildren(...shown.map((e) => {
    const tr = document.createElement('tr');
    if (e.kind === 'error') tr.className = 'error';
    const text = cell('text', e.text);
    if (e.data) {
      const data = document.createElement('span');
      data.className = 'data';
      data.textContent = JSON.stringify(e.data);
      text.append(data);
    }
    tr.append(cell('time', `${day(e.at)} ${clock(e.at)}`), cell('kind', e.kind), text);
    return tr;
  }));
  empty.hidden = entries.length > 0;
}

function header() {
  const m = chrome.runtime.getManifest();
  return `${m.name} ${m.version_name || m.version}, Chrome ${navigator.userAgent.match(/Chrome\/([\d.]+)/)?.[1] || ''}, ${entries.length} entries`;
}

document.getElementById('copy').addEventListener('click', async () => {
  await navigator.clipboard.writeText(logText(entries, header()));
  said.textContent = `Copied ${entries.length} entries.`;
});

document.getElementById('save').addEventListener('click', () => {
  const url = URL.createObjectURL(new Blob([logText(entries, header())], { type: 'text/plain' }));
  const a = document.createElement('a');
  a.href = url;
  a.download = `cool-head-for-chrome-log-${day(Date.now())}.txt`;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
  said.textContent = 'Saved where Chrome saves your downloads.';
});

document.getElementById('clear').addEventListener('click', async () => {
  await chrome.storage.local.remove(LOG_KEY);
  said.textContent = 'Cleared.';
});

kindSelect.addEventListener('change', draw);
chrome.storage.onChanged.addListener((changes, area) => { if (area === 'local' && LOG_KEY in changes) load(); });
load();
