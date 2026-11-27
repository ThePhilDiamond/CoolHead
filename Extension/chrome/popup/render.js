// Draws the popup from a view (src/logic/view.js) and the popup's own state (ui). No chrome.* calls, so
// dev/preview.html draws the same popup from made-up data. Tab titles come from web pages, so they only ever
// go in as text (textContent), never as markup.
import * as W from '../src/logic/words.js';
import { icon, flake, REASON_ICON } from './icons.js';
import { drawToolbarIcon } from '../src/logic/toolbar-icon.js';

export function h(tag, props = {}, ...kids) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) {
    if (v == null || v === false) continue;
    if (k === 'class') el.className = v;
    else if (k === 'text') el.textContent = v;
    // Through the style object, which the popup's content security policy allows, unlike a style attribute.
    else if (k === 'style') el.style.cssText = v;
    else if (k.startsWith('on')) el.addEventListener(k.slice(2).toLowerCase(), v);
    else if (k === 'checked' || k === 'value' || k === 'disabled') el[k] = v;
    else el.setAttribute(k, v === true ? '' : v);
  }
  for (const kid of kids.flat()) if (kid != null && kid !== false) el.append(kid);
  return el;
}

function fav(row) {
  if (row.favicon) {
    const box = h('span', { class: 'fav img', 'aria-hidden': 'true' });
    const img = h('img', { src: row.favicon, alt: '' });
    img.addEventListener('error', () => {
      box.className = 'fav';
      box.style.background = row.color;
      box.textContent = row.letter;
    });
    box.append(img);
    return box;
  }
  const tile = h('span', { class: 'fav', 'aria-hidden': 'true', text: row.letter });
  tile.style.background = row.color;
  return tile;
}

// ---------- the top band ----------

function band(view, ui, on) {
  const b = view.band;
  const brand = h('div', { class: 'brand' }, h('b', { text: W.NAME }));
  if (b.link) {
    brand.append(h('span', { class: `link${b.link.state === 'linked' ? '' : ' off'}` },
      icon(b.link.state === 'linked' ? 'sync' : 'syncOff'), h('span', { text: b.link.text })));
  }
  // With a tool open (Effort, Protected, or Settings), a pill under the title goes back home, saying what waits there, and the
  // whole band goes back on a click, as in Cool Head.
  const toolOpen = ['effort', 'protected', 'windows', 'settings'].includes(ui.screen);
  const pill = toolOpen ? h('button', { class: `pill tone-${b.tone}`, 'data-key': 'home', onclick: on.home },
    icon('chevLeft'), W.backTo({ suggestions: view.questions.length + (view.duplicates ? 1 : 0), session: Boolean(view.session) })) : null;
  return h('header', { class: `band tone-${b.tone}${toolOpen ? ' goes-home' : ''}`, onclick: toolOpen ? on.home : null }, brand,
    // Not a live region itself: it is redrawn often, and a fresh live region is not reliably read. popup.js says a
    // change in memory through the one lasting live region instead.
    h('div', { class: 'status' }, flake(b.melting),
      h('div', {}, h('h1', { text: b.title }), h('p', { text: b.line }), pill)));
}

// ---------- home ----------

function notice(view, on) {
  const n = view.notice;
  if (!n) return null;
  const box = h('div', {}, h('p', { class: 'lede strong', text: n.text }));
  if (n.link) {
    box.append(h('button', { class: 'btn quiet', style: 'margin:4px 0 0 -6px', 'aria-label': n.link.aria, 'data-key': 'get', onclick: on.getCoolHead },
      n.link.label, icon('external')));
  }
  return box;
}

function questions(view, on) {
  return view.questions.map((q) => h('section', { class: 'card', 'aria-labelledby': `q${q.key}` },
    h('div', { class: 'head' }, h('h2', { id: `q${q.key}`, text: q.title })),
    h('p', { text: q.line }),
    h('div', { class: 'row' },
      ...q.options.map((o) => h('button', { class: 'btn tall', 'aria-label': `${W.KEEP_THIS}: ${o.label}`, 'data-key': `q${q.key}-${o.tabId}`, onclick: () => on.keepAnswer(q.key, o.tabId) }, o.label)),
      h('button', { class: 'btn tall', 'data-key': `q${q.key}-none`, onclick: () => on.keepAnswer(q.key, null) }, W.KEEP_NEITHER))));
}

// Blue only when no card on home is recommended (src/logic/view.js, recommend), so one button at a time is blue.
function startBlock(view, on) {
  const rec = view.recommended?.id === 'start';
  return h('div', {},
    h('button', { class: rec ? 'btn primary wide' : 'btn tall wide', 'data-key': 'start', onclick: on.openStart }, view.start.label),
    h('p', { class: 'note', text: view.start.note }));
}

// ---------- option cues ----------

// What a card's main option does about the problem, as Cool Head's options show it: a small label in capitals with
// an icon, in the text color, since the status colors never mean "click here". Only on the cards' main buttons: the
// tab rows' Keep, Sleep, and Close stay as they are.
const IMPACT_ICON = { [W.IMPACT_HELPS]: 'helps', [W.IMPACT_LATER]: 'later' };
function impactTag(words) {
  return h('span', { class: 'impact' }, icon(IMPACT_ICON[words] || 'helps'), h('span', { text: words }));
}

// The recommended option's line, under a thin rule: "Cool Head for Chrome recommends this", with the reason where
// the facts give one. Tied to the button by aria-describedby, so it is heard with it.
function recLine(view, id) {
  const r = view.recommended;
  return r?.id === id && r.why ? h('p', { class: 'recline', id: `rec-${id}`, text: r.why }) : null;
}
function recProps(view, id) {
  const rec = view.recommended?.id === id;
  return { rec, describedBy: rec && view.recommended.why ? `rec-${id}` : null };
}

function sessionCard(view, ui, on) {
  const s = view.session;
  const rows = s.tabs.map((t) => h('li', { class: 'tab slim' }, fav(t), h('div', { class: 'tabmain' }, h('span', { class: 'tabtitle', title: t.title, text: t.title }))));
  const card = h('section', { class: 'card session', 'aria-labelledby': 'ses-h' },
    h('div', { class: 'head' }, h('h2', { id: 'ses-h', text: s.title })),
    h('ul', { class: 'tabs', style: 'margin-top:6px', 'aria-label': 'Tabs in this session' }, rows));
  if (!ui.ending) {
    card.append(h('p', { class: 'note', text: s.note }),
      h('div', { class: 'row' }, h('button', { class: 'btn tall', 'data-key': 'end', onclick: on.endSession }, W.END_SESSION)));
  } else {
    const input = h('input', { type: 'text', value: ui.groupName ?? s.defaultName, 'data-key': 'group-name', oninput: (e) => on.groupName(e.target.value) });
    card.append(h('div', { class: 'divider' },
      h('h2', { id: 'save-h', text: s.saveQuestion }),
      h('p', { style: 'margin:4px 0 0', text: W.SAVE_WHY }),
      h('label', { class: 'field' }, W.GROUP_NAME, input),
      h('div', { class: 'row' },
        h('button', { class: 'btn primary', 'data-key': 'save', onclick: () => on.save(input.value) }, W.SAVE),
        h('button', { class: 'btn tall', 'data-key': 'end-without', onclick: on.endWithout }, W.END_WITHOUT)),
      h('p', { class: 'note', text: s.endNote })));
  }
  return card;
}

function heldRow(row, ui, on) {
  const confirming = ui.confirm && ui.confirm.tabId === row.id ? ui.confirm.action : null;
  const warnId = `warn-${row.id}`;
  const acts = h('span', { class: 'acts', role: 'group', 'aria-label': row.title });
  // Keep is hidden on a pinned tab: pinned tabs stay loaded already, so it would add nothing.
  if (!row.pinned) {
    acts.append(h('button', {
      class: row.kept ? 'btn pressed' : 'btn',
      'aria-pressed': row.kept ? 'true' : 'false',
      'aria-label': `${row.kept ? W.KEPT : W.KEEP}: ${row.title}`,
      title: row.kept ? W.KEPT_TIP : W.KEEP_TIP,
      'data-key': `keep-${row.id}`,
      onclick: () => on.keep(row.id, !row.kept),
    }, row.kept ? icon('check') : null, row.kept ? W.KEPT : W.KEEP));
  }
  // Chrome can't put the tab in front of you to sleep, so Sleep isn't offered there.
  if (!row.active) {
    acts.append(h('button', {
      class: 'btn', 'aria-label': `${W.SLEEP}: ${row.title}`, 'data-key': `sleep-${row.id}`,
      'aria-describedby': confirming === 'sleep' ? warnId : null, onclick: () => on.sleep(row),
    }, W.SLEEP));
  }
  acts.append(h('button', {
    class: 'btn danger', 'aria-label': `${W.CLOSE}: ${row.title}`, 'data-key': `close-${row.id}`,
    'aria-describedby': confirming === 'close' ? warnId : null, onclick: () => on.close(row),
  }, W.CLOSE));
  const main = h('div', { class: 'tabmain' },
    // the title is the button that brings the tab forward, in its own window, so it can be checked before keeping,
    // sleeping, or closing it; an arrow says it goes somewhere
    h('button', { class: 'tabtitle show', title: `${W.SHOW}: ${row.title}`, 'aria-label': `${W.SHOW}: ${row.title}`,
      'data-key': `show-${row.id}`, onclick: () => on.show(row.id) },
      h('span', { class: 'name', text: row.title }), icon('external')),
    h('div', { class: 'tabline' }, h('span', { class: 'reason' }, icon(REASON_ICON[row.reason]), row.reasonText), acts));
  if (confirming) {
    main.append(h('div', { class: 'warn', id: warnId }, icon('warn'), h('span', { text: W.warning(confirming, row.risk) })));
  }
  return h('li', { class: 'tab' }, fav(row), main);
}

// Protected, opened from the bottom bar as Trusted is in Cool Head: what stays on, in two parts. Tabs: the tabs that
// stay awake and why. Extensions: the ones that stay on when extensions pause (once pausing is on and allowed).
function protectedScreen(view, ui, on) {
  const tabs = h('section', { class: 'part', 'aria-labelledby': 'p-tabs' },
    h('h3', { class: 'parthead', id: 'p-tabs' }, W.PROTECTED_TABS, h('span', { class: 'count', text: view.held.countText })));
  if (view.held.tabs.length === 0) tabs.append(h('p', { class: 'lede', text: W.PROTECTED_EMPTY }));
  else {
    tabs.append(h('p', { class: 'lede', text: W.PROTECTED_LEDE }),
      h('ul', { class: 'tabs', 'aria-labelledby': 'p-tabs' }, view.held.tabs.map((r) => heldRow(r, ui, on))));
  }
  const main = h('main', { class: 'middle', 'aria-label': W.PROTECTED }, screenTitle(W.PROTECTED, on), tabs, sitesPart(view, on), extensionsPart(view, ui, on));
  return [band(view, ui, on), main, toolbar(view, ui, on)];
}

// Sites whose every tab stays awake: the list, each with Remove, and the site you're on, to add it.
function sitesPart(view, on) {
  const sites = view.sites || { list: [], add: null };
  const part = h('section', { class: 'part', 'aria-labelledby': 'p-sites' },
    h('h3', { class: 'parthead', id: 'p-sites' }, W.SITES_PART, h('span', { class: 'count', text: String(sites.list.length) })),
    h('p', { class: 'lede', text: sites.list.length ? W.SITES_LEDE : W.SITES_NONE }));
  if (sites.list.length) {
    part.append(h('ul', { class: 'sitelist', 'aria-labelledby': 'p-sites' }, sites.list.map((host) => h('li', { class: 'ext' },
      h('span', { class: 'tabmain' }, h('span', { class: 'tabtitle', text: host })),
      h('button', { class: 'btn', 'data-key': `site-${host}`, 'aria-label': `${W.SITE_REMOVE}: ${host}`, onclick: () => on.keepSite(host, false) }, W.SITE_REMOVE)))));
  }
  if (sites.add) {
    part.append(h('div', { class: 'row' }, h('button', { class: 'btn', 'data-key': 'site-add', onclick: () => on.keepSite(sites.add, true) }, icon('globe'), W.siteAdd(sites.add))));
  }
  return part;
}

// The design drew two columns; a 360 px popup has room for one, so the two lists stack, each named. The switch that
// pauses extensions heads them, since it decides what the lists mean.
function extensionsPart(view, ui, on) {
  const st = view.settings;
  const cols = ui.safe;
  const part = h('section', { class: 'part', id: 'p-ext-part', 'aria-labelledby': 'p-ext' },
    h('h3', { class: 'parthead', id: 'p-ext' }, W.SAFE_TITLE),
    h('label', { class: 'choice' },
      h('input', { type: 'checkbox', checked: st.restEnabled, 'data-key': 'rest-on', onchange: (e) => on.restEnabled(e.target.checked) }),
      h('span', {}, h('b', { text: W.REST_TOGGLE }), h('span', { class: 'why', text: W.REST_WHY }))));
  if (!st.restEnabled) return part;
  if (st.restingText) part.append(h('p', { class: 'note', text: st.restingText }));
  if (!st.managementGranted) {
    part.append(h('p', { class: 'note', text: W.REST_NEEDS }),
      h('div', { class: 'row' }, h('button', { class: 'btn primary', 'data-key': 'allow', onclick: on.openSafe }, W.PAUSE_ALLOW)));
  } else if (!cols || (cols.alwaysOn.length === 0 && cols.rest.length === 0)) {
    part.append(h('p', { class: 'note', text: W.SAFE_EMPTY }));
  } else {
    part.append(
      h('section', { 'aria-labelledby': 'on-h' }, h('p', { class: 'sub', id: 'on-h', text: `${W.SAFE_ON} · ${cols.alwaysOn.length}` }),
        h('ul', { class: 'tabs' }, cols.alwaysOn.map((e) => extRow(e, false, on)))),
      h('section', { 'aria-labelledby': 'rest-h2' }, h('p', { class: 'sub', id: 'rest-h2', text: `${W.SAFE_REST} · ${cols.rest.length}` }),
        h('ul', { class: 'tabs' }, cols.rest.map((e) => extRow(e, true, on)))));
  }
  return part;
}

// The toolbar icon's two styles, each drawn at all three levels to pick one by sight, as Cool Head's Settings do
// (SettingsView.swift, IconStylePicker): the badge by its shapes and colors, the melting snowflake by its drawing alone.
function iconCard(st, on) {
  // dark when the page's own text is light, so the drawings match the card they sit on
  const rgb = (getComputedStyle(document.body).color.match(/\d+(\.\d+)?/g) || ['0', '0', '0']).map(Number);
  const dark = (0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]) / 255 > 0.5;
  const pic = (style, level) => {
    const c = h('canvas', { width: '44', height: '44', class: 'iconpic', 'aria-hidden': 'true' });
    drawToolbarIcon(c.getContext('2d'), 44, level, dark, style);
    return c;
  };
  return h('section', { class: 'card', 'aria-labelledby': 'icon-h' },
    h('h2', { id: 'icon-h', text: W.ICON_TITLE }),
    h('div', { class: 'iconhead', 'aria-hidden': 'true' }, h('span', {}), ...W.ICON_LEVELS.map((t) => h('span', { text: t }))),
    h('div', { role: 'radiogroup', 'aria-labelledby': 'icon-h' }, W.ICON_STYLES.map(([style, name, how]) => {
      const pressed = st.iconStyle === style;
      return h('button', { class: pressed ? 'iconrow on' : 'iconrow', role: 'radio', 'aria-checked': pressed ? 'true' : 'false',
        'aria-label': `${name}. ${how}`, 'data-key': `icon-${style}`, onclick: () => on.iconStyle(style) },
        h('span', { class: 'iconname' }, h('b', { text: name }), h('span', { class: 'why', text: how })),
        pic(style, 'good'), pic(style, 'warning'), pic(style, 'issue'));
    })));
}

// Recommends letting Cool Head for Chrome turn off unneeded extensions, saying what stays on, until allowed or set
// aside; Settings keeps the switch either way.
function extRecCard(view, on) {
  if (!view.extRec) return null;
  const { rec, describedBy } = recProps(view, 'extrec');
  return h('section', { class: 'card', 'aria-labelledby': 'extrec-h' },
    h('div', { class: 'head' }, h('h2', { id: 'extrec-h', text: W.EXT_REC_TITLE }), impactTag(W.IMPACT_LATER)),
    h('p', { text: W.EXT_REC_LINE }),
    h('p', { class: 'note', text: W.EXT_REC_NOTE }),
    h('div', { class: 'row' },
      h('button', { class: rec ? 'btn primary' : 'btn tall', 'data-key': 'extrec-allow', 'aria-describedby': describedBy, onclick: on.extRecAllow }, W.EXT_REC_ALLOW),
      h('button', { class: 'btn tall', 'data-key': 'extrec-later', onclick: on.extRecLater }, W.EXT_REC_LATER)),
    recLine(view, 'extrec'));
}

// Each page open more than once, its title showing a copy that would close, so they can be checked first. After
// closing, what closed shows for a few seconds, then the card goes and the next option turns blue (view.js,
// dupsResult). If Chrome closed none, the card stays, its button there to try again, with a line saying so; once the
// copies are gone (closed by hand, say), so is the card. Neither result is a live region: the popup says what happened
// through its one lasting live region (popup.js), and a region rebuilt on each redraw would be read again and again.
function duplicatesCard(view, on) {
  const c = view.closedDups;
  if (c && !c.failed) {
    return h('section', { class: 'card', 'aria-labelledby': 'dup-h' },
      h('div', { class: 'head' }, h('h2', { id: 'dup-h' }, icon('check'), W.closedDupsTitle(c.n))),
      h('ul', { class: 'duplist' }, c.groups.map((x) => h('li', {}, h('span', { class: 'name', text: x.title }),
        x.n > 1 ? h('span', { class: 'why', text: ` × ${x.n}` }) : null))),
      h('p', { class: 'note', text: W.CLOSED_DUPS_NOTE }));
  }
  const d = view.duplicates;
  if (!d) return null;
  const { rec, describedBy } = recProps(view, 'dups');
  return h('section', { class: 'card', 'aria-labelledby': 'dup-h' },
    // its tag only where closing frees memory now: a copy that's asleep frees nothing
    h('div', { class: 'head' }, h('h2', { id: 'dup-h', text: d.title }), view.dupsFrees ? impactTag(W.IMPACT_HELPS) : null),
    c?.failed ? h('p', { class: 'failed' }, icon('warn'), h('span', { text: W.DUPS_FAILED_LINE })) : null,
    h('p', { text: d.line }),
    h('ul', { class: 'duplist' }, (d.items || []).map((x) => h('li', {},
      h('button', { class: 'tabtitle show', title: `${W.SHOW}: ${x.title}`, 'aria-label': `${W.SHOW}: ${x.title}`,
        'data-key': `dup-show-${x.showId}`, onclick: () => on.show(x.showId) }, h('span', { class: 'name', text: x.title }), icon('external')),
      h('span', { class: 'why', text: W.dupExtra(x.extra) })))),
    h('div', { class: 'row' }, h('button', { class: rec ? 'btn primary' : 'btn tall', 'data-key': 'dups', 'aria-describedby': describedBy, onclick: on.closeDuplicates }, d.button)),
    recLine(view, 'dups'));
}

// Effort, a tool that fills the middle as Cool Head's do: one row a level, its name and what it does. A click sets
// it at once; the row says so, and a moment later it goes back home (popup.js). Arrow keys move between rows; Enter
// or Space chooses, so moving along with the keyboard doesn't change the level on the way.
function effortScreen(view, ui, on) {
  const l = view.levels;
  const enabled = l.options.filter((o) => !o.disabled);
  const keydown = (e) => {
    const i = enabled.findIndex((o) => o.id === e.currentTarget.dataset.level);
    let next = null;
    if (e.key === 'ArrowDown' || e.key === 'ArrowRight') next = enabled[(i + 1) % enabled.length];
    if (e.key === 'ArrowUp' || e.key === 'ArrowLeft') next = enabled[(i - 1 + enabled.length) % enabled.length];
    if (e.key === 'Home') next = enabled[0];
    if (e.key === 'End') next = enabled[enabled.length - 1];
    if (next) {
      e.preventDefault();
      e.currentTarget.parentElement.querySelector(`[data-level="${next.id}"]`)?.focus();
    }
  };
  const chosenEnabled = enabled.some((o) => o.id === l.chosen);
  const rows = l.options.map((o) => {
    const on_ = o.id === l.chosen;
    const justSet = on_ && ui.levelSet === o.id;
    const tabbable = on_ || (!chosenEnabled && o === enabled[0]);
    return h('button', {
      class: `levelrow${on_ ? ' chosen' : ''}`,
      role: 'radio', 'aria-checked': on_ ? 'true' : 'false', tabindex: tabbable ? '0' : '-1',
      'aria-disabled': o.disabled ? 'true' : null, 'aria-describedby': o.disabled && l.needs ? 'auto-needs' : null,
      'data-level': o.id, 'data-key': `level-${o.id}`,
      onclick: () => { if (!o.disabled) on.level(o.id); }, onkeydown: keydown,
    },
    h('span', { class: 'mark', 'aria-hidden': 'true' }, on_ ? icon('check') : null),
    h('span', { class: 'levelmain' },
      h('span', { class: 'levelname' }, o.label, justSet ? h('span', { class: 'setnow', text: W.levelSetTo(o.id) }) : null),
      h('span', { class: 'why', text: o.what })));
  });
  // What the chosen level is doing right now, when that's more than its line says (view.js).
  const status = l.status;
  const main = h('main', { class: 'middle', 'aria-label': W.LEVEL_LABEL },
    screenTitle(W.LEVEL_LABEL, on),
    h('div', { class: 'levelrows', role: 'radiogroup', 'aria-label': W.LEVEL_LABEL }, rows),
    status ? h('p', { class: 'note', text: status }) : null,
    l.needs ? h('p', { class: 'note', id: 'auto-needs', text: l.needs }) : null);
  return [band(view, ui, on), main, toolbar(view, ui, on)];
}

// ---------- the bottom bar ----------

// As in Cool Head's own bottom bar: each tool is an icon over its name, and the open one is white on Cool Head blue.
// Effort's tool reads "Effort: Auto", so the level can be read without opening it.
function toolbar(view, ui, on) {
  const l = view.levels;
  const chosen = l.options.find((o) => o.id === l.chosen)?.label || W.LEVEL_LABEL;
  const tool = (key, ico, label, open, props) => h('button', { class: `tool${open ? ' open' : ''}`, 'data-key': key, ...props },
    h('span', { class: 'toolicon' }, icon(ico)), h('span', { class: 'toolname', text: label }));
  // open, just "Effort": the level chosen shows in the middle
  const effort = ui.screen === 'effort' ? W.LEVEL_LABEL : `${W.LEVEL_LABEL}: ${chosen}`;
  const count = view.held.count ? h('span', { class: 'badge', 'aria-hidden': 'true', text: String(view.held.count) }) : null;
  const shield = tool('protected', 'shield', W.PROTECTED, ui.screen === 'protected', {
    'aria-current': ui.screen === 'protected' ? 'page' : null, 'aria-label': `${W.PROTECTED}, ${view.held.countText}`, onclick: on.openProtected,
  });
  if (count) shield.querySelector('.toolicon').append(count);
  return h('footer', { class: `bottom tone-${l.tone}` },
    h('nav', { class: 'tools', 'aria-label': W.NAME },
      tool('effort', 'gauge', effort, ui.screen === 'effort', {
        'aria-current': ui.screen === 'effort' ? 'page' : null, 'aria-label': `${W.LEVEL_LABEL}: ${chosen}`, onclick: on.openEffort,
      }),
      shield,
      windowsTool(view, ui, on, tool),
      tool('settings', 'gear', W.SETTINGS, ui.screen === 'settings', {
        'aria-current': ui.screen === 'settings' ? 'page' : null, onclick: on.openSettings,
      })));
}

// Saved windows' tool, with how many are saved beside it.
function windowsTool(view, ui, on, tool) {
  const n = view.windows?.saved.length || 0;
  const open = ui.screen === 'windows';
  const t = tool('windows', 'windowSaved', W.WINDOWS, open, {
    'aria-current': open ? 'page' : null, 'aria-label': `${W.WINDOWS}, ${n}`, onclick: on.openWindows,
  });
  if (n) t.querySelector('.toolicon').append(h('span', { class: 'badge', 'aria-hidden': 'true', text: String(n) }));
  return t;
}

// ---------- saved windows ----------

// Save this window: a button that opens a dialog over the tool, with a few words to name its folder, the whole name
// shown as it will be, and Save and close. Below, each saved window with Reopen and Remove, both asking first in the row itself; then anything in the parent
// folder Cool Head didn't put there, with Tidy, which moves it out and never deletes it.
function windowsScreen(view, ui, on) {
  const w = view.windows;
  const words = (ui.windowWords ?? '').trim();
  const name = W.windowFolderName(words || w.defaultWords, w.tabsHere, w.day);
  const input = h('input', { type: 'text', maxlength: '40', value: ui.windowWords ?? '', placeholder: W.WINDOWS_DESCRIBE_HINT,
    'data-key': 'window-words', oninput: (e) => on.windowWords(e.target.value),
    onkeydown: (e) => { if (e.key === 'Enter' && !e.isComposing) on.saveWindow(e.target.value); } });
  const risky = ui.windowRisky && w.risky.length;
  // The tool shows Save this window as a button; the dialog it opens sits over the tool, holding the words, the name
  // as it will be, any warning, and Save and close. Its X goes back to the tool; the shortcut opens it directly.
  const opener = h('div', { class: 'winopen' },
    h('button', { class: 'btn primary wide', 'data-key': 'window-open', 'aria-haspopup': 'dialog', onclick: on.saveDialog }, W.SAVE_DIALOG_OPEN),
    h('p', { class: 'note', text: W.SAVE_DIALOG_WHY }));
  // A click outside the dialog closes it, only when it both starts and ends there, so a selection dragged out of
  // the field doesn't.
  let pressedOutside = false;
  const dialog = ui.saveDialog ? h('div', { class: 'veil',
    onpointerdown: (e) => { pressedOutside = e.target === e.currentTarget; },
    onclick: (e) => { if (pressedOutside && e.target === e.currentTarget) on.closeDialog(); pressedOutside = false; } },
    h('section', { class: 'dialog', role: 'dialog', 'aria-modal': 'true', 'aria-labelledby': 'win-dlg-h', 'aria-describedby': 'win-dlg-p' },
      h('div', { class: 'screenhead' }, h('h2', { id: 'win-dlg-h', text: W.SAVE_DIALOG_TITLE }),
        h('button', { class: 'iconbtn', 'aria-label': W.CLOSE_DIALOG, title: W.CLOSE_DIALOG, 'data-key': 'close-dialog', onclick: on.closeDialog }, icon('x'))),
      h('p', { class: 'lede', id: 'win-dlg-p', text: W.SAVE_DIALOG_LEDE }),
      h('label', { class: 'field' }, W.WINDOWS_DESCRIBE, input),
      h('p', { class: 'savedas', 'aria-live': 'polite', text: W.windowsSavedAs(name) }),
      risky ? h('div', { class: 'warn', id: 'win-risky' }, icon('warn'), h('span', { text: W.windowsRisky(w.risky) })) : null,
      // why the last Save didn't close the window; already said aloud, so not a live region itself
      ui.windowSaid ? h('div', { class: 'warn', 'data-key': 'window-said' }, icon('warn'), h('span', { text: ui.windowSaid })) : null,
      h('button', { class: 'btn primary wide', 'data-key': 'window-save', 'aria-describedby': risky ? 'win-risky' : null,
        onclick: () => on.saveWindow(input.value) }, risky ? W.WINDOWS_SAVE_ANYWAY : W.WINDOWS_SAVE),
      h('p', { class: 'note', text: w.granted ? W.WINDOWS_SAVE_NOTE : `${W.WINDOWS_SAVE_NOTE} ${W.WINDOWS_ASKS}` }))) : null;
  const saved = h('section', { class: 'part', 'aria-labelledby': 'win-list-h' },
    h('h3', { class: 'parthead', id: 'win-list-h' }, W.WINDOWS_SAVED, h('span', { class: 'count', text: String(w.saved.length) })));
  if (!w.saved.length) saved.append(h('p', { class: 'lede', text: W.WINDOWS_EMPTY }));
  else saved.append(h('ul', { class: 'sitelist', 'aria-labelledby': 'win-list-h' }, w.saved.map((f) => savedRow(f, ui, on))));
  const others = w.others.length ? h('section', { class: 'part', 'aria-labelledby': 'win-others-h' },
    h('h3', { class: 'parthead', id: 'win-others-h' }, W.WINDOWS_OTHERS, h('span', { class: 'count', text: String(w.others.length) })),
    h('p', { class: 'lede', text: W.WINDOWS_OTHERS_WHY }),
    h('ul', { class: 'sitelist' }, w.others.map((o) => h('li', { class: 'ext' }, h('span', { class: 'tabmain' }, h('span', { class: 'tabtitle', title: o.title, text: o.title }))))),
    h('div', { class: 'row' }, h('button', { class: 'btn', 'data-key': 'win-tidy', onclick: on.tidyWindows }, W.WINDOWS_TIDY))) : null;
  const main = h('main', { class: 'middle', 'aria-label': W.WINDOWS }, screenTitle(W.WINDOWS, on), opener, saved, others);
  const parts = [band(view, ui, on), main, toolbar(view, ui, on)];
  // While the dialog is open, everything under it is out of reach of the keyboard and screen readers.
  if (dialog) for (const p of parts) p.inert = true;
  return [...parts, dialog];
}

// A saved window: its words, with its count and age under them, Reopen, and a small bin to remove it. Either asks in
// the row itself: the line under the words says what will happen, and the row's buttons become the answer and Cancel,
// so the list keeps its shape and nothing opens below it.
function savedRow(f, ui, on) {
  const asking = ui.confirmWindow?.id === f.id ? ui.confirmWindow.action : null;
  const reopen = asking === 'reopen';
  const line = asking ? (reopen ? W.windowsReopenAsk(f.n) : W.windowsRemoveAsk(f.n)) : W.windowsLine(f.n, f.ago);
  const acts = asking
    ? [h('button', { class: reopen ? 'btn primary' : 'btn danger solid', 'data-key': `win-yes-${f.id}`, onclick: () => (reopen ? on.reopenWindow(f.id) : on.removeWindow(f.id)) },
        reopen ? W.WINDOWS_REOPEN : W.WINDOWS_DELETE),
      h('button', { class: 'btn', 'data-key': `win-no-${f.id}`, onclick: () => on.askWindow(null) }, W.WINDOWS_CANCEL)]
    : [h('button', { class: 'btn', 'data-key': `win-reopen-${f.id}`, 'aria-label': `${W.WINDOWS_REOPEN}: ${f.name}`, onclick: () => on.askWindow(f.id, 'reopen') }, W.WINDOWS_REOPEN),
      h('button', { class: 'iconbtn bin', 'data-key': `win-remove-${f.id}`, 'aria-label': `${W.WINDOWS_REMOVE}: ${f.name}`, title: W.WINDOWS_REMOVE, onclick: () => on.askWindow(f.id, 'remove') }, icon('trash'))];
  // the folder's own words as the title; its count and age on the line under, so the title isn't cut short by them
  return h('li', { class: `ext savedwin${asking ? ` asking ${asking}` : ''}`, role: asking ? 'group' : null, 'aria-label': asking ? f.name : null },
    h('span', { class: 'tabmain' }, h('span', { class: 'tabtitle', title: f.name, text: f.words }),
      h('span', { class: 'why', 'aria-live': 'polite', text: line })),
    h('span', { class: 'acts' }, ...acts));
}

function home(view, ui, on) {
  // a session's Save form is the one blue button while it shows, so no card is recommended then
  if (ui.ending && view.recommended) view = { ...view, recommended: null };
  const main = h('main', { class: 'middle', 'aria-label': W.NAME },
    ui.laterNote ? h('p', { class: 'note laternote', role: 'status', text: W.MIGRATE_LATER_NOTE }) : null,
    view.offline ? h('section', { class: 'card', 'aria-labelledby': 'off-h' },
      h('h2', { id: 'off-h', text: view.offline.title }),
      h('p', { text: view.offline.line }),
      h('div', { class: 'row' }, h('button', { class: 'btn', 'data-key': 'offline-settings', onclick: on.openSettings }, view.offline.button))) : null,
    notice(view, on),
    questions(view, on),
    view.session ? sessionCard(view, ui, on) : startBlock(view, on),
    duplicatesCard(view, on),
    extRecCard(view, on));
  return [band(view, ui, on), main, toolbar(view, ui, on)];
}

// ---------- start a session ----------

function pick(row, ticked, on) {
  return h('label', { class: 'pick' },
    h('input', { type: 'checkbox', checked: ticked, 'data-key': `pick-${row.id}`, onchange: (e) => on.tick(row.id, e.target.checked) }),
    h('span', { class: 'box', 'aria-hidden': 'true' }, icon('check')),
    fav(row),
    h('span', { class: 'tabmain' }, h('span', { class: 'tabtitle', title: row.title, text: row.title }), h('span', { class: 'why', text: row.why })));
}

const OTHERS_SHOWN = 4;

export function startCounts(start, ticked) {
  const unticked = start.rows.filter((r) => !ticked.has(r.id));
  const sleep = unticked.filter((r) => r.ifUnticked === 'sleep').length;
  const stayLoaded = unticked.filter((r) => r.ifUnticked !== 'sleep' && r.ifUnticked !== 'none').map((r) => ({ id: r.id, reason: r.ifUnticked }));
  return { sleep, stayLoaded, ticked: start.rows.filter((r) => ticked.has(r.id)).length };
}

function startScreen(view, ui, on) {
  const st = ui.start;
  const byId = new Map(st.rows.map((r) => [r.id, r]));
  const suggested = st.suggested.map((id) => byId.get(id));
  const others = st.others.map((id) => byId.get(id));
  const shown = ui.showAllOthers ? others : others.slice(0, OTHERS_SHOWN);
  const counts = startCounts(st, ui.ticked);
  const main = h('main', { class: 'middle', 'aria-label': W.START },
    h('div', { class: 'screenhead' }, h('h2', { text: W.START }),
      h('button', { class: 'iconbtn', 'aria-label': W.CLOSE_START, title: W.CLOSE_START, 'data-key': 'close-start', onclick: on.closeStart }, icon('x'))),
    h('p', { class: 'lede', text: W.START_LEDE }),
    h('label', { class: 'pick framed' },
      h('input', { type: 'checkbox', checked: ui.windowOnly, 'data-key': 'window-only', onchange: (e) => on.windowOnly(e.target.checked) }),
      h('span', { class: 'box', 'aria-hidden': 'true' }, icon('check')),
      h('span', { class: 'tabmain' }, h('span', { style: 'display:block;font-weight:600', text: W.WINDOW_ONLY }), h('span', { class: 'why', text: W.windowOnlyWhy(st.windowTabs) }))),
    suggested.length ? h('div', {},
      h('p', { class: 'sub', id: 'sug', text: `${W.SUGGESTED} · ${suggested.length}` }),
      h('div', { role: 'group', 'aria-labelledby': 'sug' }, suggested.map((r) => pick(r, ui.ticked.has(r.id), on)))) : null,
    others.length ? h('div', {},
      h('p', { class: 'sub', id: 'oth', text: `${W.OTHERS} · ${others.length}` }),
      h('div', { role: 'group', 'aria-labelledby': 'oth' }, shown.map((r) => pick(r, ui.ticked.has(r.id), on))),
      others.length > OTHERS_SHOWN ? h('button', { class: 'more', 'aria-expanded': ui.showAllOthers ? 'true' : 'false', 'data-key': 'more', onclick: on.showMore },
        icon(ui.showAllOthers ? 'chevDown' : 'chevRight'), ui.showAllOthers ? W.SHOW_FEWER : W.showMore(others.length - OTHERS_SHOWN)) : null) : null);
  const footer = h('footer', { class: 'pinned' },
    h('button', { class: 'btn primary wide', disabled: counts.ticked === 0, 'aria-describedby': 'start-note', 'data-key': 'start-go', onclick: on.startSession }, W.startButton(counts.ticked)),
    h('p', { class: 'note', id: 'start-note', text: W.startNote(counts.sleep, counts.stayLoaded, st.resting) }));
  return [band(view, ui, on), main, footer];
}

// ---------- settings ----------

// A tool's title: a back arrow before its name, which goes back a level, home; an X is kept for cancelling a task, as
// Start a session and the save dialog do. The pill in the band, the band, and the tool again go back home too.
function screenTitle(title, on) {
  return h('div', { class: 'screenhead' },
    h('button', { class: 'iconbtn back', 'aria-label': W.BACK, title: W.BACK, 'data-key': 'tool-back', onclick: on.home }, icon('back')),
    h('h2', { text: title }));
}

function radio(name, value, checked, title, why, onchange) {
  return h('label', { class: 'choice' },
    h('input', { type: 'radio', name, value: String(value), checked, 'data-key': `${name}-${value}`, onchange }),
    h('span', {}, h('b', { text: title }), h('span', { class: 'why', text: why })));
}

function settingsScreen(view, ui, on) {
  const st = view.settings;
  const main = h('main', { class: 'middle', 'aria-label': W.SETTINGS },
    screenTitle(W.SETTINGS, on),
    // while tabs are moving, how far along, with no button to start another move
    view.migrate?.running ? h('section', { class: 'card', 'aria-labelledby': 'mig-h' },
      h('h2', { id: 'mig-h', text: W.MIGRATE_SETTINGS }),
      h('p', { class: 'strong', text: W.migrateRunning(view.migrate.done, view.migrate.total) }),
      h('progress', { style: 'width:100%', max: String(view.migrate.total || 1), value: String(view.migrate.done), 'aria-label': W.migrateProgress(view.migrate.done, view.migrate.total) }),
      h('p', { class: 'note', text: W.MIGRATE_KEEP_GOING }))
    : view.migrate?.count ? h('section', { class: 'card', 'aria-labelledby': 'mig-h' },
      h('h2', { id: 'mig-h', text: W.MIGRATE_SETTINGS }),
      h('p', { text: W.migrateHead(view.migrate.count, view.migrate.from) }),
      h('div', { class: 'row' }, h('button', { class: 'btn', 'data-key': 'open-migrate', onclick: on.openMigrate }, W.MIGRATE_TITLE))) : null,
    h('section', { class: 'card', 'aria-labelledby': 'leave-h' },
      h('h2', { id: 'leave-h', text: W.LEAVE_TITLE }),
      h('div', { role: 'radiogroup', 'aria-labelledby': 'leave-h', style: 'margin-top:6px' },
        radio('leave', 30000, st.leaveDelayMs === 30000, W.LEAVE_30, W.LEAVE_30_WHY, () => on.leaveDelay(30000)),
        radio('leave', 0, st.leaveDelayMs === 0, W.LEAVE_0, W.LEAVE_0_WHY, () => on.leaveDelay(0))),
      h('p', { class: 'note', text: W.LEAVE_NOTE }),
      // a quick look at a sleeping tab puts it back to sleep, so looking for something doesn't wake everything
      h('label', { class: 'choice', style: 'margin-top:8px' },
        h('input', { type: 'checkbox', checked: st.glanceSleep, 'data-key': 'glance', onchange: (e) => on.glanceSleep(e.target.checked) }),
        h('span', {}, h('b', { text: W.GLANCE_TITLE }), h('span', { class: 'why', text: W.GLANCE_WHY })))),
    // set and forget: what keeps tabs with typing or on a call awake, which needs Chrome's access to every site
    h('section', { class: 'card', 'aria-labelledby': 'sites-h' },
      h('h2', { id: 'sites-h', text: W.SITES_TITLE }),
      h('label', { class: 'choice' },
        h('input', { type: 'checkbox', checked: st.sitesGranted, 'data-key': 'sites', onchange: (e) => on.sites(e.target.checked) }),
        h('span', {}, h('b', { text: W.SITES_TOGGLE }), h('span', { class: 'why', text: W.SITES_TOGGLE_WHY }))),
      st.sitesGranted ? null : h('p', { class: 'note', text: W.SITES_ASKS })),
    iconCard(st, on),
    h('section', { class: 'card', 'aria-labelledby': 'key-h' },
      h('h2', { id: 'key-h', text: W.SHORTCUT_TITLE }),
      h('dl', { class: 'keys' },
        ...[[W.SHORTCUT_THIS, st.shortcuts.tab], [W.SHORTCUT_OTHERS, st.shortcuts.others], [W.SHORTCUT_WINDOW, st.shortcuts.window]].flatMap(([name, key]) => [
          h('dt', { text: name }), h('dd', {}, key ? h('kbd', { text: key }) : h('span', { class: 'muted', text: W.SHORTCUT_NONE }))])),
      h('p', { class: 'why', text: W.SHORTCUT_WHAT }),
      h('div', { class: 'row' },
        h('button', { class: 'btn', 'data-key': 'shortcut', onclick: on.shortcut }, st.shortcuts.tab || st.shortcuts.others ? W.SHORTCUT_CHANGE : W.SHORTCUT_SET)),
      h('p', { class: 'note', text: W.SHORTCUT_PAGE })),
    h('section', { class: 'card', 'aria-labelledby': 'off-set-h' },
      h('h2', { id: 'off-set-h', text: W.OFFLINE_TITLE }),
      h('label', { class: 'choice' },
        h('input', { type: 'checkbox', checked: st.offlineHold, 'data-key': 'offline', onchange: (e) => on.offlineHold(e.target.checked) }),
        h('span', {}, h('b', { text: W.OFFLINE_TOGGLE }), h('span', { class: 'why', text: W.OFFLINE_WHY })))),
    h('section', { class: 'card', 'aria-labelledby': 'about-h' },
      h('h2', { id: 'about-h', text: W.ABOUT_TITLE }),
      h('p', { text: st.about })));
  return [band(view, ui, on), main, toolbar(view, ui, on)];
}

function extRow(e, toOn, on) {
  return h('li', { class: 'ext' },
    h('span', { class: 'tabmain' }, h('span', { class: 'tabtitle', title: e.name, text: e.name }),
      e.open ? h('span', { class: 'why', text: W.EXT_OPEN })
        : W.EXT_WHY[e.kind] ? h('span', { class: 'why', text: e.kind === 'admin' ? W.SAFE_ADMIN : W.EXT_WHY[e.kind] })
        : e.everySite ? h('span', { class: 'why heavy', text: W.EXT_EVERY_SITE }) : null),
    e.kind === 'admin' ? null : h('button', {
      class: 'btn', 'data-key': `move-${e.id}`, 'aria-label': `${toOn ? W.MOVE_TO_ON : W.MOVE_TO_REST}: ${e.name}`,
      onclick: () => on.safeMove(e.id, toOn),
    }, toOn ? W.MOVE_TO_ON : W.MOVE_TO_REST));
}

// ---------- moving a suspender's tabs ----------

// Shown once when the popup first finds tabs a suspender holds, and from Settings after. Three states: the offer,
// the move under way, and its result, with the suspender's removal offered once its tabs are safe.
function migrateScreen(view, ui, on) {
  const m = view.migrate || { count: 0 };
  const body = [];
  if (m.running) {
    body.push(h('h2', { text: W.migrateProgress(m.done, m.total) }),
      h('progress', { max: String(m.total || 1), value: String(m.done), 'aria-label': W.migrateProgress(m.done, m.total) }),
      h('p', { class: 'note', text: W.MIGRATE_KEEP_GOING }));
  } else if (m.result) {
    body.push(h('h2', { text: W.migrateDone(m.result.moved) }));
    if (m.result.failed) body.push(h('p', { text: W.migrateFailed(m.result.failed) }));
    if (m.result.stuck) body.push(h('p', { text: W.migrateParked(m.result.stuck) }));
    if (m.result.removeId && !m.count) {
      body.push(h('p', { text: W.migrateRemove(m.result.removeName) }),
        h('div', { class: 'row' },
          h('button', { class: 'btn primary', 'data-key': 'mig-remove', onclick: () => on.migrateRemove(m.result.removeId) }, W.MIGRATE_REMOVE),
          h('button', { class: 'btn', 'data-key': 'mig-close', onclick: on.migrateClose }, W.MIGRATE_NOT_NOW)));
    } else {
      body.push(h('div', { class: 'row' }, h('button', { class: 'btn', 'data-key': 'mig-close', onclick: on.migrateClose }, W.CLOSE_TOOL)));
    }
  } else {
    body.push(h('h2', { text: W.migrateHead(m.count, m.from) }),
      h('p', { text: W.MIGRATE_HOW }),
      h('p', { class: 'warnline', text: W.MIGRATE_WARN }),
      h('div', { class: 'row' },
        h('button', { class: 'btn primary', 'data-key': 'mig-go', onclick: on.migrate }, W.migrateGo(m.count)),
        h('button', { class: 'btn', 'data-key': 'mig-later', onclick: on.migrateLater }, W.MIGRATE_LATER)));
  }
  const main = h('main', { class: 'middle', 'aria-label': W.MIGRATE_TITLE },
    screenTitle(W.MIGRATE_TITLE, { home: m.running || m.result ? on.migrateClose : on.migrateLater }),
    h('section', { class: 'card migrate' }, ...body));
  return [band(view, ui, on), main, toolbar(view, ui, on)];
}

// ---------- the whole popup ----------

export function render(root, view, ui, on) {
  const screens = { home, start: startScreen, settings: settingsScreen, protected: protectedScreen, effort: effortScreen, migrate: migrateScreen, windows: windowsScreen };
  const parts = (screens[ui.screen] || home)(view, ui, on);
  // Keep the person's place: the focused control and the scroll position survive a redraw.
  const focusKey = document.activeElement?.dataset?.key;
  const scroll = root.querySelector('main')?.scrollTop ?? 0;
  const sameScreen = root.dataset.screen === ui.screen;
  root.replaceChildren(...parts.filter(Boolean));
  root.dataset.screen = ui.screen;
  const main = root.querySelector('main');
  if (main && sameScreen) main.scrollTop = scroll;
  // A soft fade at the foot of the middle while there is more below, as in render 1c.
  if (main) {
    const fade = () => main.classList.toggle('more-below', main.scrollTop + main.clientHeight < main.scrollHeight - 2);
    fade();
    main.addEventListener('scroll', fade, { passive: true });
  }
  if (focusKey) {
    const again = root.querySelector(`[data-key="${CSS.escape(focusKey)}"]`);
    // The control may be gone (a closed tab's row, an answered question): focus goes to the section it was in,
    // or the first control, never lost to the page.
    const fallback = focusKey.match(/^(keep|sleep|close)-/) ? root.querySelector('[data-key="protected"]') : null;
    // Without scrolling: focus() alone brings the control into view, which jumped the list back to the top whenever
    // the focused control was above where the person had scrolled.
    (again || fallback || root.querySelector('main button, main input'))?.focus({ preventScroll: true });
  }
}
