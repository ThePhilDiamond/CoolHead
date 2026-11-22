// 16 px line icons, the same ones drawn for the design renders.
const NS = 'http://www.w3.org/2000/svg';

export const PATHS = {
  speaker: '<path d="M2.5 6h2.5L8.5 3v10L5 10H2.5z"/><path d="M11 5.5a3.5 3.5 0 0 1 0 5"/><path d="M12.8 3.8a6 6 0 0 1 0 8.4"/>',
  camera: '<rect x="1.5" y="4.5" width="9" height="7" rx="1.5"/><path d="M10.5 7.2l4-2.2v6l-4-2.2"/>',
  screen: '<rect x="1.8" y="2.5" width="12.4" height="8.5" rx="1.5"/><path d="M5.5 13.8h5M8 11v2.8"/>',
  pencil: '<path d="M10.8 2.2l3 3L5.8 13.2H2.8v-3z"/><path d="M9.3 3.7l3 3"/>',
  pin: '<path d="M5.5 1.8h5l-.6 4.4 2.3 2.3H3.8l2.3-2.3z"/><path d="M8 8.5v5.7"/>',
  bookmark: '<path d="M4.2 1.8h7.6v12.4L8 11.3l-3.8 2.9z"/>',
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
  gear: '<path d="M2 4.5h6.5M12.5 4.5H14M2 11.5h1.5M7.5 11.5H14"/><circle cx="10.5" cy="4.5" r="2"/><circle cx="5.5" cy="11.5" r="2"/>',
};

export const REASON_ICON = { call: 'camera', screen: 'screen', typing: 'pencil', sound: 'speaker', kept: 'bookmark', pinned: 'pin', session: 'bookmark' };

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
