// 16 px line icons, the same ones drawn for the design renders.
const NS = 'http://www.w3.org/2000/svg';

export const PATHS = {
  speaker: '<path d="M2.5 6h2.5L8.5 3v10L5 10H2.5z"/><path d="M11 5.5a3.5 3.5 0 0 1 0 5"/><path d="M12.8 3.8a6 6 0 0 1 0 8.4"/>',
  camera: '<rect x="1.5" y="4.5" width="9" height="7" rx="1.5"/><path d="M10.5 7.2l4-2.2v6l-4-2.2"/>',
  screen: '<rect x="1.8" y="2.5" width="12.4" height="8.5" rx="1.5"/><path d="M5.5 13.8h5M8 11v2.8"/>',
  pencil: '<path d="M10.8 2.2l3 3L5.8 13.2H2.8v-3z"/><path d="M9.3 3.7l3 3"/>',
  pin: '<path d="M5.5 1.8h5l-.6 4.4 2.3 2.3H3.8l2.3-2.3z"/><path d="M8 8.5v5.7"/>',
  bookmark: '<path d="M4.2 1.8h7.6v12.4L8 11.3l-3.8 2.9z"/>',
  // Saved windows: a window in front of another, with a bookmark ribbon hanging from its title bar
  windowSaved: '<path d="M4.6 2.2h8.3a1.4 1.4 0 0 1 1.4 1.4v7.6"/><rect x="1.7" y="4.6" width="10.4" height="9.4" rx="1.4"/><path d="M1.7 7.1h10.4"/><path d="M4 7.1v5.2l1.5-1.1 1.5 1.1V7.1"/>',
  sync: '<path d="M13.2 6.2A5.3 5.3 0 0 0 3.4 4.6"/><path d="M3.1 1.9v2.9H6"/><path d="M2.8 9.8a5.3 5.3 0 0 0 9.8 1.6"/><path d="M12.9 14.1v-2.9H10"/>',
  syncOff: '<path d="M13.2 6.2A5.3 5.3 0 0 0 3.4 4.6"/><path d="M3.1 1.9v2.9H6"/><path d="M2.8 9.8a5.3 5.3 0 0 0 9.8 1.6"/><path d="M12.9 14.1v-2.9H10"/><path d="M2 2l12 12"/>',
  chevRight: '<path d="M6 3.5L10.5 8 6 12.5"/>',
  chevDown: '<path d="M3.5 6L8 10.5 12.5 6"/>',
  chevLeft: '<path d="M10 3.5L5.5 8 10 12.5"/>',
  x: '<path d="M4 4l8 8M12 4l-8 8"/>',
  check: '<path d="M3.2 8.4l3 3 6.6-7"/>',
  external: '<path d="M6.5 3.5h6v6"/><path d="M12.5 3.5L4 12"/>',
  warn: '<path d="M8 1.8l6.6 11.6H1.4z"/><path d="M8 6.2v3.3"/><path d="M8 11.6v.1"/>',
  bolt: '<path d="M9 1.5L3.5 9h4L7 14.5 12.5 7h-4z"/>',
  shield: '<path d="M8 1.8l5.2 2v4c0 3.1-2.2 5.4-5.2 6.4-3-1-5.2-3.3-5.2-6.4v-4z"/><path d="M5.7 8.1l1.6 1.6 3-3.1"/>',
  gauge: '<path d="M2.4 11.8a5.8 5.8 0 1 1 11.2 0"/><path d="M8 10l2.8-3.3"/><path d="M8 10h.01"/>',
  globe: '<circle cx="8" cy="8" r="6.2"/><path d="M1.8 8h12.4"/><path d="M8 1.8c-2.2 2.4-2.2 10 0 12.4M8 1.8c2.2 2.4 2.2 10 0 12.4"/>',
  tray: '<path d="M8 1.8v7"/><path d="M5.2 6.2L8 9l2.8-2.8"/><path d="M1.8 9.5h3.4l1 2h3.6l1-2h3.4"/><path d="M1.8 9.5v4.2h12.4V9.5L12.6 4M3.4 4L1.8 9.5"/>',
  trash: '<path d="M2.6 4.2h10.8"/><path d="M6.2 4.2V2.4h3.6v1.8"/><path d="M3.9 4.2l.8 9.4h6.6l.8-9.4"/><path d="M6.7 6.8v4.4M9.3 6.8v4.4"/>',
  gear: '<path d="M12.96 6.81L14.64 7.11V8.89L12.96 9.19L12.35 10.66L13.33 12.06L12.06 13.33L10.66 12.35L9.19 12.96L8.89 14.64H7.11L6.81 12.96L5.34 12.35L3.94 13.33L2.67 12.06L3.65 10.66L3.04 9.19L1.36 8.89V7.11L3.04 6.81L3.65 5.34L2.67 3.94L3.94 2.67L5.34 3.65L6.81 3.04L7.11 1.36H8.89L9.19 3.04L10.66 3.65L12.06 2.67L13.33 3.94L12.35 5.34Z"/><circle cx="8" cy="8" r="2.2"/>',
};

export const REASON_ICON = { call: 'camera', screen: 'screen', typing: 'pencil', sound: 'speaker', kept: 'bookmark', site: 'globe', pinned: 'pin', session: 'bookmark' };

export function icon(name, cls = 'ico') {
  const svg = document.createElementNS(NS, 'svg');
  svg.setAttribute('class', cls);
  svg.setAttribute('viewBox', '0 0 16 16');
  svg.setAttribute('aria-hidden', 'true');
  svg.setAttribute('focusable', 'false');
  // Our own fixed markup, never page text, so parsing it is safe.
  const doc = new DOMParser().parseFromString(`<svg xmlns="${NS}">${PATHS[name]}</svg>`, 'image/svg+xml');
  for (const node of [...doc.documentElement.childNodes]) svg.appendChild(document.importNode(node, true));
  return svg;
}

// The Melting Snowflake: it melts while memory is short, so the state shows in its shape, not only in color.
export function flake(melting) {
  const svg = document.createElementNS(NS, 'svg');
  svg.setAttribute('class', 'flake');
  svg.setAttribute('viewBox', '0 0 40 44');
  svg.setAttribute('aria-hidden', 'true');
  svg.setAttribute('focusable', 'false');
  let arms = '';
  for (let a = 0; a < 360; a += 60) {
    arms += `<g transform="rotate(${a} 20 18)"><path d="M20 18V4"/><path d="M20 8.5l-3.2-3M20 8.5l3.2-3"/><path d="M20 12.5l-2.4-2.2M20 12.5l2.4-2.2"/></g>`;
  }
  const drips = melting
    ? '<path class="drip" d="M14 35c0 1.6 1 2.6 2.2 2.6s2.2-1 2.2-2.6c0-1.4-2.2-4-2.2-4s-2.2 2.6-2.2 4z"/>'
      + '<path class="drip" d="M22.5 37c0 1.6 1 2.6 2.2 2.6s2.2-1 2.2-2.6c0-1.4-2.2-4-2.2-4s-2.2 2.6-2.2 4z"/>'
      + '<ellipse class="drip" cx="20" cy="42" rx="9" ry="1.6" opacity="0.7"/>'
    : '';
  const markup = `<svg xmlns="${NS}"><g fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round">${arms}</g><circle cx="20" cy="18" r="2.2" fill="currentColor"/>${drips}</svg>`;
  const doc = new DOMParser().parseFromString(markup, 'image/svg+xml');
  for (const node of [...doc.documentElement.childNodes]) svg.appendChild(document.importNode(node, true));
  return svg;
}
