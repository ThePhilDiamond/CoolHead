# Chrome Web Store listing

Everything the Chrome Web Store dashboard asks for, ready to paste, in the dashboard's order. The package comes from `scripts/package-extension.sh`; the images are in `store/images`, made with `store/make-images.py` from made-up data.

## Package

Run `scripts/package-extension.sh`. It builds `build/cool-head-for-chrome-<version>.zip` and, signed with the key in `.secrets/chrome-extension-key.pem`, `build/cool-head-for-chrome-<version>.crx`. Both leave out the manifest's `key`, which the store refuses, and the tests and developer tools. Verified CRX uploads is on for this item, so upload the `.crx`; the store rejects anything not signed with that key. Keep a backup of the key outside this Mac: without it, updates wait until Chrome Web Store support replaces it, which can take a week.

## Store listing tab

**Name and summary** come from the manifest: "Cool Head for Chrome", and "Sleeps unused tabs and temporarily turns off extensions you don't need, so Chrome holds less memory. Works alone or with Cool Head." (131 of the 132 characters allowed)

**Description:** (1.2.0's first submission listed seven kinds of extension that stay on and was rejected for "excessive keywords"; name only a couple of examples.)

```
Cool Head for Chrome puts tabs you aren't using to sleep and can pause extensions you don't need, so Chrome holds less memory and your computer stays quick. A sleeping tab stays in your tab bar and reloads when you click it. A paused extension isn't removed: it's switched off for a while and comes back on by itself. Nothing closes unless you choose.

What it does
• Sleeps tabs once you leave them. Effort sets how many stay loaded: Light keeps your 5 most used tabs, Balanced your 3, and Focus only the tab you're on.
• Back to sleep after a quick look: a sleeping tab you open and leave within 10 seconds sleeps again at once, so looking for a tab doesn't wake them all.
• Keeps what matters awake: calls, sound, unsent typing, pinned tabs, any tab you keep, and every tab from a site you choose.
• Shows which tabs are asleep: with access to sites, "zzZ" goes before a sleeping tab's title, in your theme's own text color.
• Protected shows each tab it's keeping loaded and why, so you can keep it, sleep it, or close it.
• Start a session: tick the tabs a task needs, like a meeting or a project, and the rest sleep until you want them back. When it ends, you can save its tabs as a tab group.
• Keyboard shortcuts: Command-Shift-S (Ctrl+Shift+S on Windows and Linux) sleeps the tab you're on, and another can sleep the rest of the window.
• Doesn't sleep tabs while you're offline, when they couldn't reload, unless you choose otherwise.
• Moving from another tab suspender: its tabs move over one at a time, each asleep at its real address, so you can remove the suspender without losing them. A tab whose address downloads a file moves to a page of its own, with Download it again.
• Finds pages open twice and closes the extra copy, keeping the one you used last.
• Saved windows: save a window you're done with for now into a bookmark folder named with a few words, how many tabs, and the date, and close it. Reopen it later with every tab asleep, or open it with Chrome's own Open all.
• Pauses extensions you don't need, during a session or, with Cool Head, when memory is very tight, then turns them back on for you. Essentials such as password managers and security tools stay on by default, and you can switch any extension on or off at any time. One that runs on every site is listed first, since it adds memory to every tab. Pausing is off until you turn it on.

Works on its own, or with Cool Head
Cool Head is a free Mac app that keeps an eye on your Mac's memory, heat, and battery. Linked to it, the extension's Auto level puts tabs to sleep only when memory is actually short, so they reload less; its toolbar icon shows how tight memory is, like Cool Head's menu bar icon; and Cool Head's advice can act in Chrome with one click. Without it, the extension works on its own at the level you choose.

Private
Everything stays on your computer. There's no account, no analytics, and no ads, and it sends nothing over the internet.
Privacy: https://github.com/ThePhilDiamond/CoolHead/blob/main/docs/CHROME-PRIVACY.md
Open source (AGPL): https://github.com/ThePhilDiamond/CoolHead
```

**Category:** Productivity, then Tools (or the closest the dashboard offers). **Language:** English (United States).

**Graphic assets:**
- Store icon, 128 by 128: `Extension/chrome/icons/icon128.png`, the melting snowflake, the same as the package's.
- Screenshots, 1280 by 800, in this order: `1-tabs.png`, `2-extensions.png`, `3-protected.png`, `4-session.png`, `5-alone.png`.
- Small promo tile, 440 by 280: `promo-tile.png`.
- Marquee promo tile, 1400 by 560: `marquee-tile.png`.

**Homepage URL:** https://github.com/ThePhilDiamond/CoolHead/tree/main/Extension/chrome
**Support URL:** https://github.com/ThePhilDiamond/CoolHead/issues

## Privacy tab

**Single purpose:**

```
Reduces how much memory Chrome uses. It puts tabs the user isn't using to sleep and, if the user turns it on, temporarily pauses extensions they don't need, while keeping awake what they need: calls, sound, unsent typing, and the tabs, sites, and extensions they choose. Every feature serves that one purpose: choosing which tabs sleep, marking sleeping tabs, showing which tabs are holding memory and why, sessions that keep only one task's tabs loaded, keyboard shortcuts to sleep tabs, closing duplicate tabs, saving a window as a bookmark folder to reopen later with its tabs asleep, moving tabs held by another tab suspender so they can sleep natively, and optionally linking to Cool Head, a Mac app that reports when the computer's memory is short.
```

**Permission justifications:**

| Permission | Justification to paste |
|---|---|
| tabs | Reads each tab's address, title, and state (loaded, asleep, playing sound, pinned) to choose which tabs to put to sleep, to find pages open twice, to list the tabs it keeps loaded and why, and to find tabs another tab suspender holds, which it reopens at their own address when the person asks. Puts tabs to sleep with chrome.tabs.discard. |
| tabGroups | When a session ends, the person can save its tabs as a named tab group; Cool Head can also ask it to collapse groups the person isn't using. |
| storage | Keeps settings, the tabs and sites the person chose to keep, the session, and which extensions may pause in chrome.storage on the computer, because a Manifest V3 service worker stops when idle. |
| nativeMessaging | Optionally links to Cool Head, a Mac app, through its helper, so tabs sleep only when the Mac's memory is short. Only counts are sent (tabs asleep, tabs held by reason), never addresses or titles, and only on the Mac. |
| alarms | Wakes the service worker to put tabs to sleep after the person leaves them, and to find kept tabs again after Chrome restarts. |
| contextMenus | Adds "Keep this tab loaded" and "Keep every tab of this site loaded" checkboxes to the page and toolbar menus. |
| scripting | Registers its two page scripts, which say only whether a page has unsent typing or a live call, and runs them in tabs already open when the person turns on "Unsent typing and calls". Neither reads page content. Just before a tab sleeps, it also runs one line in that tab that puts "zzZ" before the page's title, so the person can see the tab is asleep; the page's own title comes back when it wakes. |
| favicon | Shows each tab's icon in the popup's lists, from Chrome's own icon cache. |
| system.memory | Reads the computer's free memory, to show and decide how hard to work. |
| management (optional, asked for when used) | Asked for only when the person turns on "Pause extensions", or asks to remove a tab suspender after its tabs are moved. During a session, or when Cool Head reports memory is very tight, pauses extensions the person hasn't kept on, and turns them back on when the session ends or memory clears. Never pauses an extension with tabs open on its own pages. Removing a suspender uses Chrome's own confirmation. |
| bookmarks (optional, asked for when used) | Asked for only the first time the person saves a window. Saved windows writes the window's pages to a bookmark folder in its own "Cool Head windows" folder, lists that folder's contents, reopens a saved folder with its tabs asleep and then removes it, deletes one the person removes, and moves anything the person put in that folder to Other bookmarks. It reads no other bookmarks beyond the top folders' names, to find Other bookmarks. |
| Host permissions, all sites (optional, asked for when used) | Asked for only when the person turns on "Unsent typing and calls". Lets its page scripts check whether a tab has unsent typing or a camera, microphone, or screen-sharing call, so those tabs never sleep and lose typing or end a call. Only a yes or no leaves the page. It also lets the extension put "zzZ" before a sleeping tab's title, so the person can see which tabs are asleep. The person can turn it off at any time. |

**Remote code:** No, I am not using remote code. (Every script is in the package; the content security policy allows only the extension's own scripts.)

**Data usage:** tick these, because Chrome's policy asks for data handled on the device to be disclosed too:
- Web history: tab addresses and titles, used on the device to find duplicates, list tabs, and choose which sleep.
- User activity: which tabs the person switches to, and whether a page has unsent typing (yes or no only), used on the device to keep those tabs loaded.

Then tick the three certifications: no selling or transferring to third parties outside the approved uses, no use or transfer for purposes unrelated to the single purpose, and no use or transfer to determine creditworthiness or for lending.

**Privacy policy URL:** https://raw.githubusercontent.com/ThePhilDiamond/CoolHead/main/docs/CHROME-PRIVACY.md (since 1.2.0: the store's link check got an error from github.com's file page, which refuses automated requests, while the raw file answers; it moves to Cool Head's own site once there is one).

## Distribution tab

**Visibility:** Unlisted (anyone with the link can install it; it doesn't show in search), until testers have used the store copy. **Regions:** all.

## Test instructions tab

```
The extension works on its own; the Cool Head Mac app is optional and not needed to review it.
1. Open several tabs, then click the toolbar button. Effort, in the bottom bar, sets how many of the most used tabs stay loaded (Balanced: 3). Leave a tab and it goes to sleep 30 seconds later; it stays in the tab bar and reloads when clicked.
2. Play a video or sound in a tab: it stays awake and appears in Protected with Keep, Sleep, and Close.
3. Click "Start a session", keep a few tabs ticked, and press Start: the unticked tabs sleep. End the session from the menu.
4. Press Command-Shift-S (Ctrl+Shift+S on Windows and Linux) on a tab: it sleeps, and the next tab to its right shows. Press it again to sleep that one too.
5. Optional: in Settings, turn on "Keep tabs with unsent typing or a call awake" and allow access, then type in a form without sending it; that tab is held as "Unsent typing".
No account or sign-in is needed.
```

## After it's approved

The store's ID is `pobnaljpjmpbpokcdbjpmlkdaljhhcfm`. Cool Head's helper allows it from the release after 0.17.0, so the store copy links to the Mac app; until then the store copy works on its own. A copy loaded by hand keeps its own ID, `idncmcjhcnoknfiomdkjidgmjkglmghl`, from the manifest's key, and the helper allows both.
