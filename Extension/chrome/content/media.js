// Camera, microphone, and screen sharing: Chrome tells extensions when a tab plays sound, but not when it uses
// the camera or microphone, so a call on mute could look idle and be put to sleep, which ends it. This runs in
// the page's own world, notes the streams the page asks for, and says only whether any are still live.
// It returns the page's own promise untouched, so the page sees no difference.
(() => {
  const proto = globalThis.MediaDevices && globalThis.MediaDevices.prototype;
  if (!proto) return;
  const live = new Map(); // track -> 'call' | 'screen'
  let last = '';
  let timer = null;

  function tell() {
    let call = false;
    let screen = false;
    for (const [track, kind] of live) {
      if (track.readyState !== 'live') { live.delete(track); continue; }
      if (kind === 'screen') screen = true; else call = true;
    }
    const now = JSON.stringify({ call, screen });
    if (now !== last) {
      last = now;
      document.dispatchEvent(new CustomEvent('coolhead-media', { detail: now }));
    }
    // A track stopped by the page fires no event, so look every 5 seconds while any is live.
    if (live.size && !timer) timer = setInterval(tell, 5000);
    if (!live.size && timer) { clearInterval(timer); timer = null; }
  }

  function watch(name, kind) {
    const original = proto[name];
    if (typeof original !== 'function') return;
    const wrapped = {
      [name](...args) {
        const p = original.apply(this, args);
        Promise.resolve(p).then((stream) => {
          try {
            for (const track of stream.getTracks()) {
              live.set(track, kind);
              track.addEventListener('ended', tell);
            }
            tell();
          } catch { /* not a stream: nothing to watch */ }
        }, () => {});
        return p;
      },
    }[name];
    Object.defineProperty(proto, name, { value: wrapped, writable: true, configurable: true, enumerable: true });
  }

  watch('getUserMedia', 'call');
  watch('getDisplayMedia', 'screen');
})();
