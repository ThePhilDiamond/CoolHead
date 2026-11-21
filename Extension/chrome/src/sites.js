// The two content scripts that see unsent typing and calls run only when the person has allowed access to all
// sites (an optional permission, asked at setup with the cost of saying no; never assumed). They are registered
// here when that permission is there and removed when it isn't, so granting or taking it back in Chrome's own
// settings takes effect without anything else.

const ALL_SITES = { origins: ['<all_urls>'] };
const SCRIPTS = [
  // In the page's own world, so it can see when the page turns on the camera, microphone, or screen sharing.
  { id: 'coolhead-media', js: ['content/media.js'], matches: ['<all_urls>'], allFrames: true, runAt: 'document_start', world: 'MAIN', persistAcrossSessions: true },
  // In the extension's isolated world: watches typing and passes both yes-or-no answers to the worker.
  { id: 'coolhead-typing', js: ['content/typing.js'], matches: ['<all_urls>'], allFrames: true, runAt: 'document_start', persistAcrossSessions: true },
];

export async function ensure() {
  const granted = await chrome.permissions.contains(ALL_SITES);
  const have = new Set((await chrome.scripting.getRegisteredContentScripts()).map((s) => s.id));
  if (granted) {
    const missing = SCRIPTS.filter((s) => !have.has(s.id));
    if (missing.length) {
      await chrome.scripting.registerContentScripts(missing);
      // Pages already open get the typing check now; a call already running is seen once the page next asks
      // for the camera or microphone, and meanwhile its sound protects it.
      const tabs = await chrome.tabs.query({ url: ['http://*/*', 'https://*/*', 'file://*/*'] });
      await Promise.all(tabs.filter((t) => !t.discarded).map((t) => chrome.scripting.executeScript({
        target: { tabId: t.id, allFrames: true },
        files: ['content/typing.js'],
      }).catch(() => {})));
    }
  } else if (have.size) {
    await chrome.scripting.unregisterContentScripts({ ids: SCRIPTS.map((s) => s.id).filter((id) => have.has(id)) });
  }
  return granted;
}
