// Draws the popup from a view (src/logic/view.js) and the popup's own state (ui). No chrome.* calls, so
// dev/preview.html draws the same popup from made-up data. Tab titles come from web pages, so they only ever
// go in as text (textContent), never as markup.
import * as W from '../src/logic/words.js';
import { icon, flake, REASON_ICON } from './icons.js';

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
  if (ui.screen === 'home') {
    brand.append(h('button', { class: 'iconbtn', 'aria-label': W.SETTINGS, title: W.SETTINGS, 'data-key': 'settings', onclick: on.openSettings }, icon('gear')));
  }
  return h('header', { class: `band tone-${b.tone}` }, brand,
    // Not a live region itself: it is redrawn often, and a fresh live region is not reliably read. popup.js says a
    // change in memory through the one lasting live region instead.
    h('div', { class: 'status' }, flake(b.melting),
      h('div', {}, h('h1', { text: b.title }), h('p', { text: b.line }))));
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

function startBlock(view, on) {
  return h('div', {},
    h('button', { class: 'btn primary wide', 'data-key': 'start', onclick: on.openStart }, view.start.label),
    h('p', { class: 'note', text: view.start.note }));
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
    h('span', { class: 'tabtitle', title: row.title, text: row.title }),
    h('div', { class: 'tabline' }, h('span', { class: 'reason' }, icon(REASON_ICON[row.reason]), row.reasonText), acts));
  if (confirming) {
    main.append(h('div', { class: 'warn', id: warnId }, icon('warn'), h('span', { text: W.warning(confirming, row.risk) })));
  }
  return h('li', { class: 'tab' }, fav(row), main);
}

function heldSection(view, ui, on) {
  const open = ui.heldOpen;
  const header = h('button', {
    class: 'group', id: 'held-h', 'aria-expanded': open ? 'true' : 'false', 'aria-controls': 'held', 'data-key': 'held',
    onclick: on.toggleHeld,
  }, icon('bolt', 'ico lead'), h('span', { class: 'cap', text: W.HELD_TITLE }), h('span', { class: 'count', text: view.held.countText }),
  icon(open ? 'chevDown' : 'chevRight', 'ico chev'));
  const body = h('div', { class: 'section-body', id: 'held', hidden: !open });
  if (open) {
    if (view.held.tabs.length === 0) body.append(h('p', { class: 'lede', text: W.HELD_EMPTY }));
    else {
      body.append(h('p', { class: 'lede', text: W.HELD_LEDE }),
        h('ul', { class: 'tabs', 'aria-label': 'Tabs held in memory' }, view.held.tabs.map((r) => heldRow(r, ui, on))));
    }
  }
  return h('section', { 'aria-labelledby': 'held-h' }, header, body);
}

function duplicatesCard(view, on) {
  const d = view.duplicates;
  if (!d) return null;
  return h('section', { class: 'card', 'aria-labelledby': 'dup-h' },
    h('div', { class: 'head' }, h('h2', { id: 'dup-h', text: d.title })),
    h('p', { text: d.line }),
    h('div', { class: 'row' }, h('button', { class: 'btn tall', 'data-key': 'dups', onclick: on.closeDuplicates }, d.button)));
}

function levels(view, on) {
  const l = view.levels;
  const enabled = l.options.filter((o) => !o.disabled);
  const choose = (id) => { if (id !== l.chosen) on.level(id); };
  // One tab stop, arrow keys move and choose, as a radio group does.
  const keydown = (e) => {
    const i = enabled.findIndex((o) => o.id === e.currentTarget.dataset.level);
    let next = null;
    if (e.key === 'ArrowRight' || e.key === 'ArrowDown') next = enabled[(i + 1) % enabled.length];
    if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') next = enabled[(i - 1 + enabled.length) % enabled.length];
    if (e.key === 'Home') next = enabled[0];
    if (e.key === 'End') next = enabled[enabled.length - 1];
    if (next) {
      e.preventDefault();
      // Focus moves with the choice, so the redraw puts it back on the newly chosen level.
      e.currentTarget.parentElement.querySelector(`[data-level="${next.id}"]`)?.focus();
      choose(next.id);
    }
  };
  const chosenEnabled = enabled.some((o) => o.id === l.chosen);
  const buttons = l.options.map((o) => {
    const on_ = o.id === l.chosen;
    const tabbable = on_ || (!chosenEnabled && o === enabled[0]);
    return h('button', {
      role: 'radio', 'aria-checked': on_ ? 'true' : 'false', tabindex: tabbable ? '0' : '-1',
      'aria-disabled': o.disabled ? 'true' : null, 'aria-describedby': o.disabled && l.needs ? 'auto-needs' : null,
      'data-level': o.id, 'data-key': `level-${o.id}`,
      onclick: () => { if (!o.disabled) choose(o.id); }, onkeydown: keydown,
    }, on_ ? icon('check') : null, o.label);
  });
  return h('footer', { class: `bottom tone-${l.tone}` },
    h('p', { class: 'label', id: 'lvl', text: l.label }),
    h('div', { class: 'seg', role: 'radiogroup', 'aria-labelledby': 'lvl' }, buttons),
    h('p', { class: 'what', text: l.line }),
    l.needs ? h('p', { class: 'what', id: 'auto-needs', text: l.needs }) : null);
}

function home(view, ui, on) {
  const main = h('main', { class: 'middle', 'aria-label': W.NAME },
    notice(view, on),
    questions(view, on),
    view.session ? sessionCard(view, ui, on) : startBlock(view, on),
    heldSection(view, ui, on),
    duplicatesCard(view, on));
  return [band(view, ui, on), main, levels(view, on)];
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

function backHead(title, on) {
  return h('div', { class: 'screenhead' },
    h('button', { class: 'iconbtn', 'aria-label': W.BACK, title: W.BACK, 'data-key': 'back', onclick: on.back }, icon('chevLeft')),
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
    backHead(W.SETTINGS, on),
    h('section', { class: 'card', 'aria-labelledby': 'leave-h' },
      h('h2', { id: 'leave-h', text: W.LEAVE_TITLE }),
      h('div', { role: 'radiogroup', 'aria-labelledby': 'leave-h', style: 'margin-top:6px' },
        radio('leave', 30000, st.leaveDelayMs === 30000, W.LEAVE_30, W.LEAVE_30_WHY, () => on.leaveDelay(30000)),
        radio('leave', 0, st.leaveDelayMs === 0, W.LEAVE_0, W.LEAVE_0_WHY, () => on.leaveDelay(0))),
      h('p', { class: 'note', text: W.LEAVE_NOTE })),
    h('section', { class: 'card', 'aria-labelledby': 'sites-h' },
      h('h2', { id: 'sites-h', text: W.SITES_TITLE }),
      h('p', { text: st.sitesGranted ? W.SITES_ON : W.SITES_OFF }),
      st.sitesGranted ? null : h('p', { class: 'note', text: W.SITES_HOW }),
      h('div', { class: 'row' }, h('button', { class: st.sitesGranted ? 'btn tall' : 'btn primary', 'data-key': 'sites', onclick: () => on.sites(!st.sitesGranted) },
        st.sitesGranted ? W.TURN_OFF : W.TURN_ON))),
    h('section', { class: 'card', 'aria-labelledby': 'rest-h' },
      h('h2', { id: 'rest-h', text: W.REST_TITLE }),
      h('label', { class: 'choice' },
        h('input', { type: 'checkbox', checked: st.restEnabled, 'data-key': 'rest-on', onchange: (e) => on.restEnabled(e.target.checked) }),
        h('span', {}, h('b', { text: W.REST_TOGGLE }), h('span', { class: 'why', text: W.REST_WHY }))),
      st.managementGranted ? null : h('p', { class: 'note', text: W.REST_NEEDS }),
      st.restingText ? h('p', { class: 'note', text: st.restingText }) : null,
      h('div', { class: 'row' }, h('button', { class: 'btn tall', 'data-key': 'safe', onclick: on.openSafe }, W.REST_SET_UP))),
    h('section', { class: 'card', 'aria-labelledby': 'about-h' },
      h('h2', { id: 'about-h', text: W.ABOUT_TITLE }),
      h('p', { text: st.about })));
  return [band(view, ui, on), main];
}

function extRow(e, toOn, on) {
  return h('li', { class: 'ext' },
    h('span', { class: 'tabmain' }, h('span', { class: 'tabtitle', title: e.name, text: e.name }),
      W.EXT_WHY[e.kind] ? h('span', { class: 'why', text: e.kind === 'admin' ? W.SAFE_ADMIN : W.EXT_WHY[e.kind] }) : null),
    e.kind === 'admin' ? null : h('button', {
      class: 'btn', 'data-key': `move-${e.id}`, 'aria-label': `${toOn ? W.MOVE_TO_ON : W.MOVE_TO_REST}: ${e.name}`,
      onclick: () => on.safeMove(e.id, toOn),
    }, toOn ? W.MOVE_TO_ON : W.MOVE_TO_REST));
}

// The design draws two columns; a 360 px popup has room for one, so the two lists stack, each named.
function safeScreen(view, ui, on) {
  const cols = ui.safe;
  const main = h('main', { class: 'middle', 'aria-label': W.SAFE_TITLE }, backHead(W.SAFE_TITLE, on), h('p', { class: 'lede', text: W.SAFE_LEDE }));
  if (!cols || (cols.alwaysOn.length === 0 && cols.rest.length === 0)) {
    main.append(h('p', { class: 'lede strong', text: W.SAFE_EMPTY }));
  } else {
    main.append(
      h('section', { 'aria-labelledby': 'on-h' }, h('p', { class: 'sub', id: 'on-h', text: `${W.SAFE_ON} · ${cols.alwaysOn.length}` }),
        h('ul', { class: 'tabs' }, cols.alwaysOn.map((e) => extRow(e, false, on)))),
      h('section', { 'aria-labelledby': 'rest-h2' }, h('p', { class: 'sub', id: 'rest-h2', text: `${W.SAFE_REST} · ${cols.rest.length}` }),
        h('ul', { class: 'tabs' }, cols.rest.map((e) => extRow(e, true, on)))));
  }
  const footer = h('footer', { class: 'pinned' }, h('button', { class: 'btn primary wide', 'data-key': 'safe-done', onclick: on.back }, W.SAFE_DONE));
  return [band(view, ui, on), main, footer];
}

// ---------- the whole popup ----------

export function render(root, view, ui, on) {
  const screens = { home, start: startScreen, settings: settingsScreen, safe: safeScreen };
  const parts = (screens[ui.screen] || home)(view, ui, on);
  // Keep the person's place: the focused control and the scroll position survive a redraw.
  const focusKey = document.activeElement?.dataset?.key;
  const scroll = root.querySelector('main')?.scrollTop ?? 0;
  const sameScreen = root.dataset.screen === ui.screen;
  root.replaceChildren(...parts);
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
    const fallback = focusKey.match(/^(keep|sleep|close)-/) ? root.querySelector('[data-key="held"]') : null;
    // Without scrolling: focus() alone brings the control into view, which jumped the list back to the top whenever
    // the focused control was above where the person had scrolled.
    (again || fallback || root.querySelector('main button, main input'))?.focus({ preventScroll: true });
  }
}
