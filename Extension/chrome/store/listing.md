# Chrome Web Store listing

Everything the Chrome Web Store dashboard asks for, ready to paste, in the dashboard's order. The package comes from `scripts/package-extension.sh`; the images are in `store/images`, made with `store/make-images.py` from made-up data.

## Package

Run `scripts/package-extension.sh` and upload the zip it names (`build/cool-head-for-chrome-1.0.0.zip`). It leaves out the manifest's `key`, which the store refuses, and the tests and developer tools.

## Store listing tab

**Name and summary** come from the manifest: "Cool Head for Chrome", and "Sleeps unused tabs and temporarily turns off extensions you don't need, so Chrome holds less memory. Works alone or with Cool Head." (131 of the 132 characters allowed)

**Description:**

```
Cool Head for Chrome puts tabs you aren't using to sleep and temporarily turns off extensions you don't need, so Chrome holds less memory and your computer stays quick. A sleeping tab stays in your tab bar and reloads when you click it. A resting extension isn't removed: it's switched off for a while and comes back on by itself. Nothing closes unless you choose.

What it does
• Sleeps tabs once you leave them. You choose how hard it works: Light keeps your 5 most used tabs loaded, Balanced your 3, and Focus only the tab you're on.
• Keeps what matters awake: calls, sound, unsent typing, pinned tabs, and any tab you mark Keep.
• Shows each tab it's keeping loaded and why, so you can keep it, sleep it, or close it.
• Start a session: tick the tabs a task needs, like a meeting or a project, and the rest sleep until you want them back. When it ends, you can save its tabs as a tab group.
• Finds pages open twice and closes the extra copy, keeping the one you used last.
• Temporarily turns off extensions you don't need, during a session or, with Cool Head, when memory is very tight, then turns them back on for you. They give back their memory without you removing anything or remembering to switch them on again. Password managers, ad blockers, VPNs, and security tools stay on, and you choose the rest. It's off until you turn it on.

Works on its own, or with Cool Head
Cool Head is a free Mac app that keeps an eye on your Mac's memory, heat, and battery. Linked to it, the extension's Auto level puts tabs to sleep only when memory is actually short, so they reload less, and Cool Head's advice can act in Chrome with one click. Without it, the extension works on its own at the level you choose.

Private
Everything stays on your computer. There's no account, no analytics, and no ads, and it sends nothing over the internet.
Privacy: https://github.com/ThePhilDiamond/CoolHead/blob/main/docs/CHROME-PRIVACY.md
Open source (AGPL): https://github.com/ThePhilDiamond/CoolHead
```

**Category:** Productivity, then Tools (or the closest the dashboard offers). **Language:** English (United States).

**Graphic assets:**
- Store icon: comes from the package (`icons/icon128.png`).
- Screenshots, 1280 by 800, in this order: `1-tabs.png`, `2-extensions.png`, `3-held.png`, `4-session.png`, `5-alone.png`.
- Small promo tile, 440 by 280: `promo-tile.png`. No marquee tile.

**Homepage URL:** https://github.com/ThePhilDiamond/CoolHead/tree/main/Extension/chrome
**Support URL:** https://github.com/ThePhilDiamond/CoolHead/issues

## Privacy tab

**Single purpose:**

```
Reduces the memory Chrome holds, by putting tabs the person isn't using to sleep and, if they choose, turning off extensions they don't need for a while, while keeping awake what they need (calls, sound, unsent typing, and tabs and extensions they choose). Every feature serves that: choosing which tabs sleep, showing which tabs hold memory and why, sessions that keep only a task's tabs loaded, closing duplicate tabs, resting extensions not on the safe list, and optionally linking to the Cool Head Mac app, which reports when the computer's memory is short.
```

**Permission justifications:**

| Permission | Justification to paste |
|---|---|
| tabs | Reads each tab's address, title, and state to choose which tabs to put to sleep, to find pages open twice, and to list the tabs it keeps loaded and why. Puts tabs to sleep with chrome.tabs.discard. |
| tabGroups | When a session ends, the person can save its tabs as a named tab group; Cool Head can also ask it to collapse groups the person isn't using. |
| storage | Keeps settings, the tabs the person chose to keep, the session, and the safe list in chrome.storage on the computer, because a Manifest V3 service worker stops when idle. |
| nativeMessaging | Optionally links to Cool Head, a Mac app, through its helper, so tabs sleep only when the Mac's memory is short. Only counts are sent (tabs asleep, tabs held by reason), never addresses or titles, and only on the Mac. |
| alarms | Wakes the service worker to put tabs to sleep after the person leaves them, and to find kept tabs again after Chrome restarts. |
| contextMenus | Adds a "Keep this tab loaded" checkbox to the page and toolbar menus. |
| scripting | Registers its two page scripts, which say only whether a page has unsent typing or a live call, and runs them in tabs already open when the person turns on "Unsent typing and calls". Neither reads page content. |
| favicon | Shows each tab's icon in the popup's lists, from Chrome's own icon cache. |
| system.memory | Reads the computer's free memory, to show and decide how hard to work. |
| management (optional, asked for when used) | Asked for only when the person turns on "Rest extensions". During a session, or when Cool Head reports memory is very tight, turns off extensions that aren't on the person's safe list, and turns them back on when the session ends or memory clears. |
| Host permissions, all sites (optional, asked for when used) | Asked for only when the person turns on "Unsent typing and calls". Lets its page scripts check whether a tab has unsent typing or a camera, microphone, or screen-sharing call, so those tabs never sleep and lose typing or end a call. Only a yes or no leaves the page. The person can turn it off at any time. |

**Remote code:** No, I am not using remote code. (Every script is in the package; the content security policy allows only the extension's own scripts.)

**Data usage:** tick these, because Chrome's policy asks for data handled on the device to be disclosed too:
- Web history: tab addresses and titles, used on the device to find duplicates, list tabs, and choose which sleep.
- User activity: which tabs the person switches to, and whether a page has unsent typing (yes or no only), used on the device to keep those tabs loaded.

Then tick the three certifications: no selling or transferring to third parties outside the approved uses, no use or transfer for purposes unrelated to the single purpose, and no use or transfer to determine creditworthiness or for lending.

**Privacy policy URL:** https://github.com/ThePhilDiamond/CoolHead/blob/main/docs/CHROME-PRIVACY.md (live once this branch is merged).

## Distribution tab

**Visibility:** Unlisted (anyone with the link can install it; it doesn't show in search), until testers have used the store copy. **Regions:** all.

## Test instructions tab

```
The extension works on its own; the Cool Head Mac app is optional and not needed to review it.
1. Open several tabs, then click the toolbar button. "How hard it works" sets how many of the most used tabs stay loaded (Balanced: 3). Leave a tab and it goes to sleep 30 seconds later; it stays in the tab bar and reloads when clicked.
2. Play a video or sound in a tab: it stays awake and appears under "Held in memory" with Keep, Sleep, and Close.
3. Click "Start a session", keep a few tabs ticked, and press Start: the unticked tabs sleep. End the session from the popup.
4. Optional: in Settings, turn on "Unsent typing and calls" and allow access, then type in a form without sending it; that tab is held as "Unsent typing".
No account or sign-in is needed.
```

## After it's approved

1. From the Package tab, copy the item ID (and the public key, for local builds to share the ID).
2. Add the ID to Cool Head's helper allowlist (`ChromeCompanion.extensionID`, `ChromeLink.manifest`) in the next Cool Head release, so the store copy links to the Mac app. Until then the store copy works on its own.
