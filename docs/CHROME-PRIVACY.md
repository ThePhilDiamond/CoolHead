# Cool Head for Chrome: privacy

Last changed 24 November 2026.

Cool Head for Chrome puts tabs you aren't using to sleep, so Chrome holds less memory. Everything it reads stays on your computer. It sends nothing over the internet: it has no account, no analytics, no ads, and no server, and its pages are built so they can't open a network connection at all (their content security policy sets `connect-src 'none'`).

## What it reads, and why

All of this is read and used on your computer only.

- **Your tabs' addresses and titles,** to find pages that are open twice, to list the tabs it's keeping loaded and say why, and to show your tabs when you start a session.
- **When you switch tabs,** to know which tabs you use most, so those stay loaded. This is kept only until Chrome quits.
- **Whether a page has text you typed and haven't sent,** so that tab never sleeps and loses it. Only a yes or no leaves the page, never what you typed. This needs access to sites, which you can give or remove at any time.
- **Whether a page is using your camera, microphone, or screen sharing,** so a call isn't put to sleep. Only a yes or no leaves the page, never sound or video. This also needs access to sites.
- **A sleeping tab's title,** which it changes rather than reads: just before a tab sleeps, it puts "zzZ" before the title, so you can see the tab is asleep, and the page brings back its own title when it wakes. Chrome's history keeps the marked title while the tab sleeps, and keeps it if the tab is closed while asleep. This also needs access to sites.
- **Your list of extensions,** only if you turn on resting extensions, so that during a session, or when memory is very tight, it can turn off extensions that aren't on your safe list, and turn them back on when the session ends or memory clears.
- **How much memory your computer has free,** from Chrome.
- **Its own bookmark folder,** only if you use Saved windows. Saving a window writes its pages' addresses and titles to a folder named "Cool Head windows" in Other bookmarks. It reads that folder to list what's saved, and Tidy moves anything it didn't put there to Other bookmarks. Of your other bookmarks, it reads only the names of the top folders, to find Other bookmarks. This needs permission to change your bookmarks, which Chrome asks you for the first time.

## What it keeps

In Chrome's own storage on your computer: your settings, the tabs you've chosen to keep loaded (with their address and title, so it can find them again after Chrome restarts), the tabs it put to sleep, your session, your safe list of extensions, and which bookmark folders it saved. Removing the extension deletes all of it. A saved window is an ordinary bookmark folder, so it stays in your bookmarks until you reopen or remove it, even if you remove the extension, and Chrome syncs it like any bookmark if you use Chrome sync.

## With Cool Head on a Mac

If you install Cool Head, the free Mac app, the extension can link to it through a small helper that Chrome starts on your Mac. They talk only to each other, on your Mac. The extension sends counts only, such as how many tabs are asleep and how many are kept loaded for each reason, never an address or a title. Cool Head sends how much memory your Mac has free and whether it's slowing down, and can ask the extension to do what you click in Cool Head, such as putting hidden tabs to sleep.

## What it never does

It doesn't sell or share anything, use what it reads for advertising or anything other than the features above, or let anyone else, including the people who make it, see your tabs. Its use of information follows the Chrome Web Store User Data Policy, including the Limited Use requirements.

## Questions

Ask on [Cool Head's issues page](https://github.com/ThePhilDiamond/CoolHead/issues). The extension's code is open, in [Extension/chrome](https://github.com/ThePhilDiamond/CoolHead/tree/main/Extension/chrome).
