# Cool Head for Chrome

Cool Head's companion extension for Google Chrome, version 1. It puts tabs you aren't using to sleep, so Chrome holds less memory and your Mac stays quick. A sleeping tab stays in your tab bar with its title and icon, "zzZ" before the title when the extension has access to all sites, and reloads when you click it. Free and open source under the AGPL, like Cool Head.

Get it from the [Chrome Web Store](https://chromewebstore.google.com/detail/pobnaljpjmpbpokcdbjpmlkdaljhhcfm), or load it by hand (below). The link to Cool Head is in [PROTOCOL.md](PROTOCOL.md).

## What it does

The menu has a bottom bar like Cool Head's: Effort, Protected, Saved windows, and Settings. Each opens in the middle of the menu; the back arrow beside its title, or the pill under the top band's title, goes back home. An X is kept for cancelling a task, such as Start a session or saving a window.

- **Effort.** Light keeps your 5 most used tabs loaded, Balanced 3, Focus only the tab you're on; the others sleep 30 seconds after you leave them (or at once, in Settings), so going back and forth within half a minute never reloads. A minimized window's tab in front counts as left when you minimize the window, so it sleeps by the same rules, and it loads again when you bring the window back; a window that's only behind another keeps its tab in front awake, since it may be on screen. Auto, with Cool Head, sleeps nothing while memory is fine; when memory slows your Mac, it sleeps tabs you haven't used for 30 minutes, one at a time, oldest first (5 minutes when memory is very tight), and stops after memory has been fine for 5 minutes.
- **Protected: tabs.** Every tab that doesn't sleep on its own, with the reason: on a call, sharing your screen, unsent typing, playing sound, kept by you, on a site you keep awake, or pinned. Each has Keep, Sleep, and Close. Sleep or Close on a call or on unsent typing asks once first, since it would end the call or lose the typing. Keep isn't offered on a pinned tab, which stays loaded already.
- **Protected: sites.** Sites whose every tab stays awake, including their subdomains, each with Remove. Add the site you're on from Protected, or by right-clicking a page and choosing Keep every tab of that site loaded.
- **Protected: extensions.** Optional. Pauses extensions you haven't kept on during a session, or while memory is very tight on Auto, and turns them back on when the session ends or memory clears. Password managers, ad and tracker blockers, VPNs, security tools, and anything your organization installed start kept on, and you can move any. An extension with tabs open on its own pages always stays on, since Chrome would close those tabs.
- **Start a session.** For a meeting or a task: it suggests the tab you're on, tabs on a call or playing sound, tabs you kept, and tabs used in the last 10 minutes, all ticked; "This window only" ticks this window's tabs and unticks the rest. Starting sleeps the rest; a tab you open or switch to joins. Ending offers to save the session's tabs as a named tab group; nothing reloads.
- **Keep.** On any tab, from Protected or by right-clicking the page: that tab, not its address, stays loaded until you un-keep it, and Chrome's own Memory Saver is told to leave it too. After Chrome restarts, kept tabs are found again by window, position, and address; when two match, the menu asks which.
- **Duplicates.** Pages open more than once in this Chrome profile, with one button to close the extra copies, keeping the one you used last. Never automatic.
- **Saved windows.** Save a window you're done with for now: Save this window, at the top of Saved windows, opens a small dialog over the list, where a few words describe it, and its tabs go into a bookmark folder named with those words, how many tabs, and the date, such as "Trip planning · 12 tabs · 24 November 2026"; then the window closes. Without words, the window's main site names it. A tab with unsent typing or a call asks first, and the window closes only once the folder is saved. The folders live in "Cool Head windows" under Other bookmarks, so Chrome's own Open all in new window works too, even without this extension. Saved windows lists them, each with Reopen, which opens every tab in a new window and puts each to sleep once its page has loaded, or after 15 seconds, so it keeps its address, title, and icon (one whose page hasn't answered by then stays awake and loads), and then removes the folder, and a bin to delete it; both ask first. Anything else in that folder is listed apart, with Tidy, which moves it to Other bookmarks and never deletes it. Command-Shift-Y on a Mac (Ctrl+Shift+Y elsewhere) opens that dialog directly, ready for the words; its X, Escape, or a click outside it goes back to the list, and the words typed stay until the menu closes. Bookmarks permission is asked for the first time.
- **Keyboard shortcuts.** Command-Shift-S on a Mac (Ctrl+Shift+S elsewhere) puts the tab you're on to sleep and shows the next awake tab to its right, so pressing it again sleeps one tab after another. Another, with no key until you choose one, puts the other tabs in the window to sleep, keeping their protections. Chrome keeps every extension's keys on its own shortcuts page, which Settings opens; Chrome gives the default key only if no other extension holds it.
- **Offline.** On by default: no tab sleeps on its own while you're offline, since a sleeping tab couldn't reload until you're back. When you're offline and memory is low, the menu says so and points to the setting.
- **Moving from a tab suspender.** Suspenders such as The Marvellous Suspender swap each tab for a page of their own, which Chrome closes if the suspender is removed. When the menu finds such tabs, it offers to move them: each opens once at its real address and goes straight to sleep, one at a time, so memory never jumps; then it offers to remove the suspender, which Chrome asks you to confirm. Do it later keeps the offer in Settings. It reads The Marvellous Suspender, The Great Suspender 2026, Tab Suspender, Tiny Suspender, tabssuspender.com's Tab Suspender, and Workona's Tab Suspender.
- **The toolbar.** The icon is the melting snowflake with a status badge, like Cool Head's menu bar icon: a green circle when memory is fine, a yellow triangle when it's tight, a red octagon when it's very tight (Cool Head's reading), and no badge without that reading. Its tooltip says how many tabs are asleep.

## Alone or with Cool Head

Everything works without Cool Head, including on Windows, Linux, and ChromeOS, where there is no Cool Head; there it shows Chrome's own reading of free memory. Auto needs Cool Head, since only Cool Head can tell when memory is actually slowing the Mac, and the popup says so.

With Cool Head, Auto follows Cool Head's reading, Cool Head's Chrome card can ask for one-click actions (sleep tabs you aren't looking at, close duplicates, fold groups not used today, pause extensions), and each says what the other did. Cool Head's card says how many tabs would sleep, by the extension's own count, which leaves out the tabs it protects, and afterwards how much less memory Chrome uses, measured; it never promises an amount beforehand, since memory already squeezed or moved to the disk, and protected tabs, make any such figure too high. Only counts and your level cross the link: never addresses, titles, or extension names.

If the link drops at any moment, the extension carries on alone with nothing lost: your level stays as you chose it (Auto waits for Cool Head and says so), tabs asleep stay asleep, and extensions paused because memory was tight come back on.

## Permissions, and why

| Permission | Why | What Chrome says |
|---|---|---|
| `tabs` | To see each tab's address and title: to list protected tabs, find duplicates, find kept tabs after a restart, and find tabs a suspender holds. | "Read your browsing history" |
| `nativeMessaging` | To talk to Cool Head, only through the helper Cool Head installs. | "Communicate with cooperating native applications" |
| `tabGroups` | To save a session as a named tab group, and to fold groups for Cool Head's card. | |
| `storage` | To remember your level, kept tabs and sites, session, and which extensions may pause, on this computer only. | |
| `alarms` | To check again after the 30 seconds a tab waits once you leave it. | |
| `contextMenus` | For "Keep this tab loaded" and keeping a whole site loaded, on the right-click menu. | |
| `scripting` | To start the typing and call checks, only if you allow access to all sites. | |
| `favicon` | To show each tab's icon from Chrome's own copy, so no icon is fetched from the web. | |
| `system.memory` | For Chrome's reading of free memory when Cool Head isn't there. | |
| `management` (optional) | To pause extensions and turn them back on, to name a tab suspender, and to remove one when you ask after its tabs are moved. Asked for only when first needed. | "Manage your apps, extensions, and themes" |
| Access to all sites (optional) | To see unsent typing and calls, and to put "zzZ" before a sleeping tab's title. Asked at setup with the cost of saying no, and never assumed. | "Read and change all your data on all websites" |

**Why access to all sites helps.** Chrome's own unloading spares a tab with typed text; an extension's doesn't, and the text is lost when the tab reloads (Cool Head's test T11). Chrome also doesn't tell extensions when a tab uses the camera or microphone. With access, two small scripts check whether a text box has been typed in and whether the camera, microphone, or screen sharing is on; only a yes or no leaves the page, never what you typed. Without it, a tab with unsent typing can sleep and lose the typing, and a call that has been quiet for 10 minutes can sleep, which ends it. Known meeting rooms (Google Meet, Zoom in the browser, Jitsi, Whereby, and Teams meeting links) are recognized by address either way.

**The zzZ mark.** Chrome shows no sign of a tab an extension put to sleep: its own dashed ring around the icon is only for tabs Chrome slept itself. So with access to all sites, just before a tab sleeps, the extension puts "zzZ" before its title; the page brings back its own title when it wakes. Nothing stays loaded to show it. The letters are plain text, so Chrome draws them in the tab's own text color, which it picks to stand out on any theme. Chrome's history and its Recently closed list keep the marked title while the tab sleeps, and keep it if the tab is closed while asleep; Cool Head takes the mark off every title it shows or saves, such as Saved windows' bookmarks. A PDF, a text file, or a page without a title gets the mark before what Chrome showed for it, and a tab reopened from Saved windows before its saved title. Without access, or on pages no extension may change (Chrome's own pages and the Web Store), a tab sleeps unmarked.

**What it never does.** No network use at all: no analytics, no remote code, no fonts or icons from the web (the popup's content security policy blocks connections). Every sleep is Chrome's own `chrome.tabs.discard`, never a stand-in page, so tabs keep working if the extension is removed.

## Load it by hand

1. In Chrome, open `chrome://extensions` and turn on Developer mode (top right).
2. Click Load unpacked and choose this folder, `Extension/chrome`.
3. A setup tab opens once and asks about unsent typing and calls.

**The IDs.** Loaded by hand, the extension's ID is `idncmcjhcnoknfiomdkjidgmjkglmghl`, fixed by the `key` in manifest.json; the key's private half isn't needed to load unpacked and isn't in the repository. From the Chrome Web Store, its ID is `pobnaljpjmpbpokcdbjpmlkdaljhhcfm`. Cool Head's helper allows both.

## Link it to Cool Head

Cool Head places a file named `io.github.thephildiamond.coolhead.json` in Chrome's `NativeMessagingHosts` folder (for a test profile, `<user-data-dir>/NativeMessagingHosts/`), naming its helper inside Cool Head.app and allowing both IDs. Cool Head writes it when you press Set up in its Settings, and writes it again if Cool Head moves or an update allows a new ID. Until then the extension shows "Not linked to Cool Head" and works alone.

For testing, [tools/mock-host.mjs](tools/mock-host.mjs) stands in for the helper and for Cool Head: it speaks Chrome's framing and plays a scenario from a JSON file (memory state, Cool Head open or not, requests). [tools/run-browser-tests.mjs](tools/run-browser-tests.mjs) shows how to point a test profile at it.

## The test build

For trying the extension day to day with a record of what it did. `scripts/make-extension-test-build.sh` (from the repository's top folder) writes a copy to `build/chrome-test`, named Cool Head for Chrome (test), with the test log on. Load that folder unpacked; it has the same ID as a copy loaded by hand, so it links to Cool Head. After running the script again, press the reload arrow on `chrome://extensions`.

- **What it records:** each check's sentence (the level, and how many tabs are in front, asleep, held and why, kept as most used, waiting, or due), each tab it sleeps and why, each it meant to but didn't, tabs unloaded by Chrome or another extension, tabs waking, the link to Cool Head, Cool Head's memory readings and requests, extensions turned off and on, what you press in the popup, typing and calls seen on a page, and errors. A check that says the same as the last one isn't written again.
- **What it never records:** a full address, a page title, or anything typed. Sites appear by host name only, such as `mail.example.com`.
- **Where:** in this Chrome profile's storage, the last 2,000 entries. Nothing leaves the computer.
- **Reading it:** right-click the toolbar button and choose Open the test log. The page shows the newest first, can show one kind at a time, and has Copy, Save as a file, and Clear.

The store build has the same code with the log off (`src/build.js`), so it records nothing.

## Tests

- `node --test` (Node 22 or later): the rules (which tabs sleep at each level, Auto, sessions, keep after a restart, duplicates, held reasons, the safe list), what the popup says alone, together, and after the link drops, the link's messages and both framings against a mock port and a real mock host process, the voice (no em dashes or exclamation marks, the Oxford comma, times as 2:15pm), and every color pair's contrast in light and dark.
- `CFT="<Chrome for Testing binary>" node tools/run-browser-tests.mjs <scratch folder>`: loads the extension into Chrome for Testing on a throwaway profile in the scratch folder, with the mock host in that profile's own `NativeMessagingHosts` folder, and checks the fixed ID and setup; alone, linked, very tight memory, a one-click request, Cool Head closing, the helper ending and relinking; Focus with pinned and kept tabs; a session saved as a group; the popup drawing with no errors; the save dialog's focus, Escape, and messages; and, in a copy with access to all sites, unsent typing, a call through a fake camera, and resting a second extension. It quits only the Chrome it started.
- `dev/render-previews.sh <output folder> <scratch folder>`: screenshots the real popup from made-up data ([dev/preview.html](dev/preview.html)) with headless Chrome on its own data folder.

## Testing by hand

In a separate Chrome profile (or Chrome for Testing), never your everyday one:

1. Load it unpacked. The setup tab opens; choose Protect them, accept Chrome's question, and see "Done. Tabs with unsent typing or on a call stay loaded."
2. Open 8 tabs on different sites. Choose Focus, then switch between two tabs: each tab you leave sleeps after 30 seconds, and the badge counts them. Click one: it reloads.
3. Type in a text box on a page, don't send, switch away, and wait a minute: that tab stays loaded, and Protected lists it as Unsent typing. Press Close on it: the popup warns once; press again to close.
4. Play a video in a tab, switch away: it stays loaded as Playing sound. Pause it: it stays protected for 10 minutes, listed as Played sound recently.
5. Pin a tab: it shows in Protected without Keep. Right-click a page and choose Keep this tab loaded: it shows as Kept by you, and doesn't sleep. In Protected's Sites, keep the site you're on: its other tabs show as Site kept awake.
6. Open the same address twice: the duplicates card offers to close one, keeping the one you used last.
7. Start a session with 2 tabs ticked: the rest sleep; switching to another tab adds it. End session, save as a group: a named group appears, and nothing reloads.
8. Quit and reopen Chrome with tabs restored: kept tabs are still kept. Open the same address twice in the same place first to see the question.
9. In Protected, turn on Pause extensions (Chrome asks once). Start a session: extensions under Pause when needed turn off; end it: they come back.
10. Press Command-Shift-S (or set it in Settings first): the tab you're on sleeps and the next awake tab to its right shows; press it again and that one sleeps too. Turn off Wi-Fi with memory low: nothing sleeps, and the menu says why.
11. With a tab suspender in the same test profile, suspend a few tabs, then open the menu: Move them, and each lands on its real address, asleep.
12. With Cool Head's helper installed: the band says Working with Cool Head, and Auto becomes available. Quit Cool Head: the band says Cool Head is not open within 10 seconds, and nothing else changes.

## Files

- `manifest.json`: Manifest V3, with the key that fixes the ID.
- `src/worker.js`: the service worker. Chrome can stop it at any moment, so all state lives in `chrome.storage` (`src/store.js`).
- `src/logic/`: the rules as pure functions with no Chrome calls, tested in Node. `words.js` holds every word on screen.
- `src/link-client.js`: the extension's end of the link; `src/sites.js`: registers the two content scripts in `content/` only when access to all sites is allowed.
- `popup/`: the popup (`render.js` draws it from a view; `popup.js` talks to the worker). `setup/`: the page shown once at install.
- `src/log.js` and `src/logic/explain.js`: the test log and its words, on only in the test build (`src/build.js`); `log/`: the Log page, left out of the store upload.
- `dev/`: the preview page and render script. `tools/`: the mock host and the browser test runner. `test/`: the Node tests.

For the Chrome Web Store, `scripts/package-extension.sh` builds the upload, leaving out the manifest's `key`, `log/`, `dev/`, `tools/`, `test/`, `store/`, `package.json`, and this README. [store/listing.md](store/listing.md) has everything the store's dashboard asks for, and [docs/CHROME-PRIVACY.md](../../docs/CHROME-PRIVACY.md) is the privacy policy.

## Not in version 1

- **Tidy up** (journey 2, old tabs saved as a group and closed): replaced by Saved windows (24 November 2026), which keeps a window in a bookmark folder rather than a closed tab group, since an extension can't rely on Chrome keeping a closed group saved; a bookmark folder works even without this extension.
- **"About 2.1 GB freed"** in the band, as the renders showed: Chrome doesn't tell extensions a tab's memory, and the link doesn't carry it yet, so the band counts tabs asleep instead.
- Windows and Linux are untested; they need a tester or a virtual machine before the store listing says it supports them.
