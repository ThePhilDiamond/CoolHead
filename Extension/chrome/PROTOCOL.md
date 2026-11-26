# Cool Head and Cool Head for Chrome: the link, version 1

The spec for the link between Cool Head and this extension, which implements it in src/link-client.js, src/logic/protocol.js, and src/logic/framing.js.

Both sides work alone; this is only what they say when linked. Unknown message types and fields are ignored, so either side can be newer.

## Pieces

1. **The extension** (`Extension/chrome/`, Manifest V3) calls `chrome.runtime.connectNative("io.github.thephildiamond.coolhead")`.
2. **The host** (`coolhead-chrome-host`, a small executable inside `Cool Head.app/Contents/Helpers/`), which Chrome starts for that connection. Chrome finds it through a manifest named `io.github.thephildiamond.coolhead.json` in Chrome's `NativeMessagingHosts` folder (for a test profile, `<user-data-dir>/NativeMessagingHosts/`), listing the host's path and `allowed_origins: ["chrome-extension://<id>/"]`. The extension's ID is fixed by a `key` in its manifest while loaded by hand.
3. **Cool Head** (the app) listens on a Unix socket at `~/Library/Application Support/Cool Head/chrome-link.sock` (folder mode 700, socket 600). The host relays between Chrome and the socket, adding nothing.

## Framing

- Chrome to host and back: Chrome's native messaging framing, a 4-byte little-endian length then UTF-8 JSON; at most 1 MB from the host.
- Host to Cool Head and back: one JSON object per line (newline-delimited), UTF-8.
- Every message: `{"v": 1, "type": "...", ...}`.

## Messages

From the host itself:
- `{"type": "link", "app": "running" | "notRunning"}`: sent first, and again if the socket closes. With `notRunning`, the host keeps trying the socket every 10 seconds while Chrome keeps it open, so opening Cool Head later links them.

Extension to Cool Head:
- `hello`: `extension` (version), `browser` ("chrome"), `level` ("auto" | "light" | "balanced" | "focus").
- `report`, at most every 10 seconds and on change: `asleep` (tabs it has unloaded and that are still unloaded), `held` (counts by reason: `sound`, `call`, `screen`, `typing`, `pinned`, `kept`, `session`), `session` (`{"active": bool, "tabs": int}`), `duplicates` (int), `extensionsResting` (int), `level`, and, from the version after 1.3.0, `toSleep` (int: the tabs `sleepHidden` would sleep now, out of sight and not protected; Cool Head's memory card says how many, never how much).
- `result`: `id` (from the request), `ok` (bool), `done` (a short sentence in Cool Head's voice, such as "Put 23 tabs to sleep."), `count`.

Cool Head to extension:
- `hello`: `app` (version).
- `state`, every 10 seconds and on change: `memory` ("fine" | "tight" | "slowed" | "veryTight"; "slowed" is Cool Head's gate: macOS has said warning or critical for a minute and memory is moving to disk), `freeMB`, `chromeMB`, `hiddenTabsMB` (or null), `extensionsMB` (or null), `auto` (bool: the person lets Auto follow Cool Head).
- `request`: `id`, `action`: "sleepHidden" (sleep tabs you aren't looking at, protections and safe list kept) | "closeDuplicates" | "hideUnusedGroups" | "restExtensions" | "openExtensionsList" | "openPopup".

## Privacy

No addresses, titles, or extension names cross the link; counts and the person's level only. Nothing goes over the network. The socket and host accept only this user's connections.

## Auto, decided together

Cool Head's `memory` sets how hard the extension works when its level is Auto: fine, nothing; tight, nothing; slowed, tabs unused 30 minutes sleep, one at a time, oldest first; veryTight, 5 minutes. Back to nothing after memory has been fine for 5 minutes. Without a link, Auto is unavailable and the extension says so.
