// Unsent typing: whether this page has text the person typed and hasn't sent. Chrome's own unloading spares
// such a tab; an extension's doesn't, and the text is lost when the tab reloads (test T11). So a tab with
// unsent typing never sleeps on its own. Only a yes or no leaves this page: never what was typed.
// Runs in the extension's isolated world, so the page can't read or change it.
(() => {
  if (globalThis.__coolHeadTyping) return; // injected again into an open page after the permission was given
  globalThis.__coolHeadTyping = true;

  const TEXT_INPUTS = new Set(['text', 'search', 'email', 'url', 'tel', 'number', 'password', '']);
  const edited = new Set();
  let dirty = false;
  let poll = null;

  function send(msg) {
    try {
      chrome.runtime.sendMessage(msg).catch(() => {});
    } catch {
      // The extension was reloaded or removed; this old copy of the script has nobody to tell.
    }
  }

  function editable(el) {
    if (!el || el.nodeType !== 1) return null;
    if (el instanceof HTMLTextAreaElement) return el;
    if (el instanceof HTMLInputElement) return TEXT_INPUTS.has(el.type) ? el : null;
    if (el.isContentEditable) {
      let root = el;
      while (root.parentElement && root.parentElement.isContentEditable) root = root.parentElement;
      return root;
    }
    return null;
  }

  function unsent(el) {
    if (!el.isConnected) return false;
    if (el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement) {
      return el.value.trim() !== '' && el.value !== el.defaultValue;
    }
    return (el.textContent || '').trim() !== '';
  }

  function check() {
    for (const el of [...edited]) if (!unsent(el)) edited.delete(el);
    const now = edited.size > 0;
    if (now !== dirty) {
      dirty = now;
      send({ type: 'typing', dirty });
    }
    // While there is unsent typing, look again every 5 seconds: a sent message usually clears or removes its box
    // without another input event.
    if (dirty && !poll) poll = setInterval(check, 5000);
    if (!dirty && poll) { clearInterval(poll); poll = null; }
  }

  document.addEventListener('input', (e) => {
    const el = editable(e.composedPath ? e.composedPath()[0] : e.target);
    if (el) { edited.add(el); check(); }
  }, true);
  document.addEventListener('submit', () => setTimeout(check, 1500), true);

  // Injected into a page that was already open: text typed before now still counts.
  for (const el of document.querySelectorAll('input, textarea')) {
    if (editable(el) && unsent(el)) edited.add(el);
  }
  check();

  // Calls and screen sharing, seen by content/media.js in the page's own world and passed here as a string.
  // A page could send this event itself, but all it could do is keep its own tab awake.
  document.addEventListener('coolhead-media', (e) => {
    try {
      const d = JSON.parse(e.detail);
      send({ type: 'media', call: Boolean(d.call), screen: Boolean(d.screen) });
    } catch { /* not ours */ }
  });
})();
