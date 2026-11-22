# Changelog

What changed in each version of Cool Head, newest first, in plain words. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and version numbers follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html): see [RELEASING.md](RELEASING.md). Each release's notes on GitHub are copied from its section here, and the app shows a short version of them once, after it updates.

## [Unreleased]

Changes waiting for the next release are in [changes/](changes/), one file each, so pull requests don't edit the same lines here. The release pull request gathers them into this file (see [RELEASING.md](RELEASING.md)).

## [0.17.0] - 2026-11-21

### Added

- Cool Head links with Cool Head for Chrome when both are installed: Settings and the welcome card offer Set up, which lets Chrome start Cool Head's helper and opens how to add the extension. Linked, Chrome's memory card can sleep tabs you aren't looking at, close duplicate tabs, hide unused tab groups, and open the extension's list of extensions, each in one click, and the extension's Auto level follows Cool Head's reading of memory. Each works alone too.
- Cool Head for Chrome, a companion extension in `Extension/chrome/`, loaded by hand for now: it puts tabs you aren't using to sleep so Chrome holds less memory; lists the tabs held in memory and why (a call, sound, unsent typing, pinned, or kept by you), with Keep, Sleep, or Close for each; starts a session that keeps only the tabs a task needs; closes duplicate tabs; and can rest extensions you choose. It works on its own, and with Cool Head it sleeps tabs only when memory is short.
- Cool Head for Chrome's link: a small helper inside the app, `coolhead-chrome-host`, that Chrome can start to pass messages between the Cool Head for Chrome extension and Cool Head on this Mac, adding nothing and using no network. Nothing sets it up in Chrome yet.

### Changed

- A new app icon: the menu bar's melting snowflake in white on Cool Head blue, in place of the smiling face. The Status badge menu bar icon now shows one melting snowflake, the same at every level, with the badge (green circle, yellow triangle, or red octagon) as the only change.

## [0.16.0] - 2026-11-21

### Added

- When Chrome uses a lot of memory, its card says how much is in tabs you aren't looking at (Chrome marks them itself, so no permission is needed) and how much in its extensions, which unloading tabs never reaches, with where to see each extension's memory. It offers to hide tab groups you aren't using, which Chrome keeps to open again. When Chrome's own program has grown past 2 GB, restarting Chrome is recommended, since only a restart gives that memory back; when Chrome has been open for days, the card says so.
- Cool Head now keeps when memory was tight on this Mac, for 30 days and on this Mac only, to tell whether memory is what slows it. The This Mac page says how often this week ("Memory slowed your Mac 3 times this week, about 40 minutes in all"), and Chrome's memory card says so from the second time. When Chrome uses the most memory but your Mac isn't moving memory to its disk, a calm card says your Mac is keeping up, instead of asking you to close tabs.
- When memory keeps slowing your Mac with Chrome using the most (twice this week, or on a Mac with 8 GB of memory or less), Chrome's memory card offers Set Memory Saver to Maximum. It restarts Chrome, keeping your tabs, and sets Memory Saver as your own setting, with no "managed by your organization": tabs you haven't looked at for 2 hours unload, and reload when you click them. Change it any time in Chrome's Performance settings.

### Changed

- Cool Head now has a color of its own, Cool Head blue, the same on every Mac, in place of your Mac's accent color. The recommended option, switches, and links read clearly in light and dark (white text on the blue measures 5.3:1), and the blue keeps "do this" apart from the yellow, orange, and red that say "watch out".

### Fixed

- Limit Chrome is gone, and Cool Head removes the settings it wrote for it. Chrome only applies that memory limit on a Mac an organization manages, so it never unloaded a tab, while Chrome said it was "managed by your organization". That notice goes within 15 minutes, or when Chrome is reopened.

## [0.15.0] - 2026-11-21

### Changed

- The dashes around the Network globe also show while Network is open, gray around an orange globe.
- Battery is now Power. A Mac with no battery shows a plug and gets the page too, with the week's energy use. The energy list shows the three that used the most without a click, "Show everything that used 5% or more this week" for the rest, and every one with its share in Nerdy stuff.
- Hardware is now This Mac. Its page shows your Mac's model and serial number, with a copy button, and how much of the startup disk is free, with a button to macOS's Storage settings and, when space is low, one to the Cleaner. The lines under the temperatures are gone: the ring at the top already says whose temperature it shows.
- The tools along the bottom are now in the order This Mac, Power, Network, and Cleaner: the three that show how your Mac is, then the one that changes things.
- With a tool open, a pill in the top row says what the cards hold, such as "2 fixes recommended", and goes back to them. The top row's sentence gives the cause without pointing at the cards ("The cards below need a look" is gone), and the tools bar along the bottom takes the same green, yellow, or red tint as the top row.

## [0.14.1] - 2026-11-19

### Changed

- Trusted moves to the right of the tools bar, between Report a problem and Settings, since it's Cool Head's own list rather than a tool for the Mac. Hardware's icon is now your Mac, drawn as a laptop or a desktop, and Cleaner's is an open hard disk with sparkles. While a network test runs out of sight, its dashes are orange and travel the other way, and the globe keeps its usual color. A poor network result is now red rather than orange.

## [0.14.0] - 2026-11-19

### Changed

- The Battery tool's icon is a battery a quarter full with a lightning bolt, so it reads as battery and power.
- Battery Saver is no longer a switch on the Battery page: on battery, a really hungry job always gets its card offering to pause it until you plug in. A job you mean to run on battery can be trusted from its card. If you had switched Battery Saver off, those cards show again.
- Report a problem asks what happened in a few words, up to 60 characters with a count in the corner, and uses them as the issue's title, so each report has its own. A report about something Cool Head is managing asks what went wrong with it instead, such as "Caused an app to crash or quit" or "Didn't help", and titles the issue with both: "Chrome's memory limit caused an app to crash or quit".
- Trends is gone from the tools. What used the most energy this week is on the Battery page, folded to one line until you open it. Why the Mac woke from sleep almost never led to anything to do, so it's no longer shown; when wakes cost battery overnight, the sleep card says so and what to do. `coolhead history` still prints both.
- The gauges at the top of the panel are off to start, for less to read: turn on Show usage and temperature in Settings to see how busy the chip and memory are and how hot the Mac is. The snowflake and its words still say how the Mac is running.
- A network test you start carries on when you open another tool or close the panel, and its results wait in Test my network. While it runs out of sight, dashes circle the Network globe; when it's done, the globe shows the result's mark (a green check when it's good) until you look. Only Stop, or quitting Cool Head, ends a test.
- Settings has a short line under more of its choices: when automatic update checks happen (when Cool Head opens, then once a day), and which menu bar icon is color-blind friendly.

## [0.13.0] - 2026-11-19

### Added

- Test my network keeps its results for 30 minutes after you close it or the panel, with the time and date of the test, so you can read them out on a call to your internet provider.

### Changed

- About says what Cool Head is in the same words as the README: "Is your Mac running hot or slow? Cool Head says why in one sentence, with options to act in one click, plus tools to test your network, check your battery and hardware, and clear space." Its license line now says GNU AGPL v3.0 only, as the license does.
- Managed by Cool Head is open whenever nothing else is: each time the panel opens, and when a tool or Settings closes. It folds while a card or tool is open.
- Learn more and Show less are centered on the card, and Show less is in the same color as Learn more, below a line that sets it apart from Nerdy stuff.
- Nerdy stuff opens as a small terminal, green on black, with its copy button in the title bar; folded, it has no copy button.
- Settings says "Cool Head version" before the number, and the day that version was released.
- Every tool closes with the same ✕ at the top right, Trends included, and with a tool open, clicking the top of the panel goes back to the cards.
- The gauges at the top are grouped under Usage and Temperature, each with its part's icon. The temperature ring shows the chip, or the battery or drive when one is nearer its own limit, named under the ring.
- A battery or drive warmer than its own limit gets a card that needs a look, so the status, the panel's color, and the menu bar icon agree with the temperature ring. A battery too warm to charge says so on that card.

### Fixed

- Quitting DisplayLink Manager is no longer marked Caution: its screens only go dark until it's running again. Quitting Docker still is, because its containers stop.
- The battery-lost-while-asleep card no longer counts a day of use as sleep: opening the lid now ends a sleep, as it should. Its sentence also says what macOS's own wakes are for.
- Options that open a page of System Settings, such as Open Battery settings, open it directly, instead of asking you to paste an address System Settings has no place for.
- Hardware's chip temperature is the same reading as the temperature ring at the top, taken every 3 seconds, and says so. It had shown a reading up to 10 minutes old.
- The switches in Settings show their color when on, whichever app is in front, like the panel's other switches.

## [0.12.0] - 2026-11-19

### Changed

- Cleaner's check for identical copies works on any folder you choose, with Downloads chosen to start, and the folders inside it, and also finds Finder's duplicates, such as Report copy.pdf beside Report.pdf. It skips hidden folders and the inside of apps, and stops after 100,000 files.
- The section at the top of the panel for what Cool Head is slowing, limiting, pausing, or has turned off is now called Managed by Cool Head, in place of On hold, which could read as turned off. Open, each line now shows what it is and since when, without a click.
- Opening a tool folds Managed by Cool Head, and opening Managed by Cool Head closes the tool, the way opening one tool closes another, so one thing is open at a time.
- What you type in Report a problem is kept if the panel closes or you open a tool, until you send it or press Cancel. It's kept in memory only, so quitting Cool Head drops it.
- In Trends, what each app's share of the energy means now shows under it, without a click.
- Trends' Why it woke from sleep now shows every wake as one bar split by reason, then a row for each reason with its color, a symbol, a short name, the count, and its share, and what it means under it.

### Fixed

- About now opens in front of the panel; in 0.11.0 it still opened behind it. Choosing a folder to check for identical copies no longer closes the panel.

## [0.11.0] - 2026-11-18

### Changed

- One thing opens at a time in the panel: a card, or On hold, which now folds to one frosted line with its count. An open card shows its recommended option, with One click and Do it yourself each folded to a line saying how many more options there are. Trends shows one section at a time.
- The panel is a little wider, and tall enough for all of Test my network.
- Cleaner: the check for identical copies in Downloads is now part of Quick clean, since the original always stays. A copy is a second download, such as Report (1).pdf beside Report.pdf, whose bytes match the original's in full.
- Cleaner's icon is macOS's bubbles and sparkles, in place of a drawn broom that was hard to make out at its size. Deep clean's heading has a checklist icon.
- Cleaner: every count of items shows their size too, in B, KB, MB, or GB: "Moved 3 items (272 MB) to the Trash", the question before moving, and the list of what Cool Head moved. Every item shows its size, however small.
- Cleaner: items under 20 MB fold into one line laid out like the others, such as "3 smaller items, each under 20 MB" with their total, and "Show each one" opens them, so the big ones stand out. One small item alone still shows.

### Fixed

- With scroll bars set to always show, opening a card no longer narrows the panel's middle and makes the On hold lines wrap: the panel grows by the scroll bar's width instead.
- The frost on held items could stop short of the row's bottom, most often after closing and quickly reopening the panel, until On hold was folded and opened again. It's now drawn afresh each time the panel opens and whenever the row changes size.
- About and the folder chooser for Check Downloads… opened behind Cool Head's panel; they now open in front of it.

## [0.10.0] - 2026-11-18

### Added

- When Google Chrome is using the most memory, its card offers **Show each tab's memory**: it opens Chrome's Appearance settings to turn on memory in tab hover cards, so pointing at any tab shows how much it uses. It isn't offered once that setting is on.
- Cleaner, a new tool along the bottom of the panel (a broom), for what deleted apps leave behind and what takes space and rebuilds itself.
  - Quick clean moves what nothing uses to the Trash with one click: background helpers whose program is gone, logs and crash reports over 30 days old, and saved windows of deleted apps.
  - Deep clean is a list to choose from: what rebuilds itself is ticked (Xcode's build data, Homebrew's and npm's downloads, and Chrome's cache while Chrome is closed); what Cool Head can't be sure of is left for you to tick and marked Caution, such as settings panes in the System Settings sidebar whose app is gone, a deleted app's caches, and old macOS installers.
  - Check Downloads… looks, in a folder you choose, for old installers and identical second downloads.
  - Everything goes to the Trash after a second click, and Cool Head can put it back; items in folders for all users ask for an administrator's password and leave nothing installed.
  - Links to Privacy & Security, where deleted apps can stay in the permission lists, and to Apple's Storage settings.

### Changed

- Test my network's tiles have bigger symbols, and Site lookup (DNS) has a magnifying glass over a page, easier to read than the letter it had.
- Lists of three or more in Cool Head's text, and in its documents, use a comma before the last "and" or "or".
- Steps that send you to Chrome's Task Manager say where the Window menu is, which heading to click, and what to close. Menu items, buttons, and settings named in steps are underlined, so they stand out.

## [0.9.0] - 2026-11-17

### Added

- The chip's temperature, in the top row's Heat gauge and under Hardware ▸ Temperatures. macOS has no public way to read it, so Cool Head reads it from macOS's sensor service, as monitoring tools do; SECURITY.md says how.
- Test my network has a Privacy section: whether a VPN is on, by name, and whether it carries all your traffic, only a few addresses, or lets IPv6 or website-name lookups go around it, with what to look for in its settings; who looks website names up (your router, or a service such as Cloudflare or Quad9) and who set that; and, from the test, the country websites see you in, which with a VPN is compared with the country they'd see without it. For that, the test also asks Cloudflare where the request came from; Cool Head shows only the country.
  - A VPN that carries only some addresses is now noticed; before, only one that was the Mac's main connection was.
  - When the router didn't give the Mac an address, the top line says so and what to do.
  - The Smart Queue steps give your router's own address to open its settings.
  - `coolhead network --test` asks it too, and `coolhead network --where` asks it alone.
- A card about a busy process now explains its recommendation in its Nerdy stuff, in plain words: what Cool Head saw, why it recommends what it does, what that costs or what it checked, and why a stronger option isn't recommended. `coolhead cards` lists every kind of card, the rule it comes from, and its samples.

### Changed

- A Caution option asks twice: the first click says why it's risky, and a second click goes ahead.
- Hardware shows the drive's life used, what it has written, and its hours on as tiles, a Temperatures section for the chip, battery, and drive, and says which parts it checked.
- The memory card says less: what's happening and what matters, with the other apps using a lot in Nerdy stuff.
- The top of the panel is one row, gently tinted green, yellow, or red: the snowflake, what's happening in plain words, and round gauges for the chip, memory, and the chip's heat.
- Cool Head reads less of macOS's power log: only each app's energy and why the Mac woke, no longer how often each app woke the chip.
- The snowflake in the menu bar and at the top of the panel always agree now: it melts when something is slowing your Mac or needs a look, and bursts into flames for a serious problem, such as a stuck job, very tight memory, or macOS slowing it hard to cool it down. A Mac that macOS is slowing a little melts now, instead of bursting into flames.
- Temperatures follow your Mac's setting in Language & Region: °F or °C.
- Trends says what each figure means: click an app for whether its share of the energy is worth doing anything about. macOS's own parts are one line, and the list of what woke the chip most often is gone, since it gave nothing to act on.
- Settings are in the panel: a gear at the right end of the toolbar opens a Settings page with notifications, Open at login, update checks, the version with Check Now, the menu bar icon (both styles shown to pick from), whether the tools' names show, About, and Quit. The first-launch welcome lets you pick the icon and Open at login, and the right-click menu is now just Settings…, About and Quit.
- What Cool Head is holding back is now a section titled On hold, with one Report a problem button under it in place of one under each line. Its form opens there and starts by asking which one caused the problem, and the report names it without file, folder, or project names. The report form's choices are now fields that open to a list, in place of radio buttons.

### Fixed

- The drive's health disappeared from Hardware after Cool Head first read it: Cool Head kept the drive's health record open, so every later read failed, in the app and in `coolhead hardware`, until it quit.
- A click anywhere in the frosted frame at the top of the panel opens the line beside it, including its edges.
- An app keeping your Mac awake while it's working, such as Claude during a long task, no longer gets a card. One appears only when the app has done almost nothing for half an hour, and it says for how long.
- The lines at the top of the panel for what Cool Head is holding back sit centered in their frosted frame, and their buttons have a backing, so they no longer blend into the frost.

## [0.8.0] - 2026-11-17

### Added

- Terms of use, in TERMS.md and linked from About: Cool Head is provided as is, a card is its best judgement and not a guarantee, and what you choose to do with it is your responsibility.
- A program pretending to be part of macOS now says so: "mdworker_local is pretending to be part of macOS", because it uses a macOS name from outside macOS's folders without Apple's signature. One click stops it and moves it to the Trash, where you can put it back.
  - Also a background item labelled like Apple's (`com.apple.…`) whose program Apple didn't sign: one click turns it off, stops it, and moves both to the Trash. And a copy in macOS's folders that isn't Apple's, said only where those folders could really have been changed: Cool Head advises turning macOS's protection back on, and offers a reinstall without recommending it.
  - A process named like part of macOS whose program couldn't be found is no longer taken for macOS's own; its card says it's probably part of macOS, but Cool Head couldn't confirm it.
- Cards about macOS's own background work read it by priority and time, not % CPU: Spotlight indexing at low priority says it runs on the efficiency cores and uses little power; after a macOS update it says "You updated to macOS 27.2 2 days ago", and that's normal for hours or days.
  - macOS's own work busy for over a day says it seems stuck, and advises a restart. Still busy after a restart, it says only Apple can fix it, and offers to check for a macOS update or tell Apple.
- A busy Intel app says it runs through Rosetta and won't open in macOS 28, with a search for its Apple silicon version; on macOS 27, where to see Apple's own list. An app set to open using Rosetta, though it has an Apple silicon version, shows how to run it natively.
  - On macOS 26.0 and 26.1, a busy WindowServer names the open apps built on an older Electron that slows the Mac, and recommends updating them.
- When memory is tight and Ollama is keeping an AI model loaded, one click unloads it and frees its memory; Ollama loads it again the next time it's asked something.
  - When the startup disk is nearly full, one click deletes Xcode's build data (it asks first); Xcode rebuilds what it needs.
- A Hardware tool along the bottom: the drive's wear and temperature and whether Time Machine backs it up, crash restarts explained in plain words with what to do, and port errors. At the top of the panel, how your Mac is running: the snowflake whole, melting, or in flames as it heats up, with how busy the chip and memory are.
- When memory is tight and the app using the most has kept growing for hours with the same windows open, the memory card says so plainly ("Pages is using more than it usually does"; it's at 8.5 GB, up from 1.1 GB three hours ago) and recommends saving your work, then Quit and reopen, which gives the memory back.
  - Options that quit an app now say to save your work first.
- Stop and Force Quit, which end a program at once with no chance to save, now warn on the option itself: "Anything unsaved will be lost. Click again to stop it." The second click within 5 seconds goes ahead. Quit stays a normal quit, where the app asks about anything unsaved.
- Cards for sleep and power: an app that has kept your Mac awake for hours (with Quit), Low Power Mode left on with the charger while your Mac is busy, and a battery that drained while asleep because the Mac kept waking, naming what woke it. The warm-but-nothing-busy card gives Apple's 10 to 35°C range, and a game's card says Game Mode gives it priority in full screen.
- Cards for browser changes you didn't make: Chrome, Edge, or Brave managed by settings Cool Head didn't make, on a Mac no organization manages (with a link to the browser's own policy page), and a browser a script started with an extension loaded from a folder (with the folder shown, and Quit).
- A card for an app that keeps crashing: 5 or more crashes in 24 hours, read from the first line of macOS's crash reports, with Look it up and See the crash reports (in Console).

### Changed

- Rest the pointer on a Caution label to see why the option is risky: "It ends at once, without a chance to save or finish what it was doing." Fixes the cause says why too.
- What Cool Head is holding back, at the top of the panel, has its undo as a button right on each line (Speed up, Remove limit, Turn on, and so on), and a chevron opens what each one is. The frost around them now grows along every edge. A folder left out of Time Machine shows its path starting with ~ rather than your account's name.
- Run it cooler is offered only where it helps: not for work already running at background priority (slowing it further does nothing), and never for macOS's own programs. For a virtual machine it warns that everything running inside it slows down sharply.
- When macOS shows web pages for another app (Mail, or an app with a web view such as Google Drive's), the card names that app and offers to quit it, instead of calling it a Safari tab. When macOS's own services work for an app, such as decoding video, the card says which app they're working for.
- A macOS service Cool Head doesn't know by name now says so: it's part of macOS, working in the background, and, when its work runs at low priority, that it uses little power even though it looks busy. Before, it got the card for an unknown program ("We can't tell why").
- Cool Head supports macOS 15 Sequoia or later. It still opens on macOS 14 Sonoma, but it isn't tested there, and a later version will need macOS 15.

### Fixed

- An update that needs a newer macOS than your Mac has is no longer installed over the copy that works: Cool Head says which macOS it needs, keeps your copy, and stops offering that version.

## [0.7.0] - 2026-11-16

### Added

- Hardware checks, with no password. A card appears, saying what to do (including how to run Apple Diagnostics), when:
  - the Mac's internal drive reports a fault, errors it couldn't correct, or heavy wear;
  - the battery needs service, has recorded a fault, or holds under 80% of its original charge;
  - it's plugged in but not charging, with the likely reason: on hold on purpose, too warm, or a charger that isn't keeping up;
  - the Mac restarted because of a crash, or crashed more than once in a week;
  - a device asked a USB-C port for more power than it can give, or keeps failing to connect.
  - `coolhead hardware` prints every check, and what can't be checked: the memory, and Apple Diagnostics' own results.
- Cool Head knows six more causes of heat, drain, or a Mac that won't sleep, each with its source and the macOS versions it was seen on:
  - macOS's sound service, which keeps the Mac awake while apps play or record sound; when it's busy for long, a virtual microphone or an app that hides the microphone dot is the likely cause.
  - Contacts syncing on macOS 26.4 and later, where a Contacts widget is the likely cause.
  - Messages catching up with iCloud.
  - Aerial wallpaper and screen saver downloads on macOS 14 and 15.
  - DisplayLink Manager drawing extra screens.
  - Local AI models in Ollama and LM Studio.
- **The past week**: which apps and parts of macOS used the most energy, which woke the chip most often, and why the Mac woke from sleep (on a timer, the lid, a charger, the Wi-Fi and Bluetooth chip), read from macOS's own power log. Cool Head reads only those figures, never the record of which app you were using, and keeps no copy. `coolhead history` prints the same in Terminal.
- The memory card says how much memory your Mac moved to its disk in the last 2 minutes, and shows even when macOS still calls memory normal if that's over 1 GB.
  - When memory is tight and the startup disk has less than 20 GB free, it says the disk limits how much your Mac can use as memory, and offers Free up disk space, which opens Storage settings.
- **Stop it starting by itself.** When a busy process is another app's background helper (Google's updater, for one), its card offers to turn the helper off: stopped now and kept from starting at login, which stopping alone can't do, since macOS starts a helper again. It's marked Caution, because what the helper does for its app stops too, and it asks first. Turn it back on from its line at the top of the panel.
- **Keep build output out of Time Machine.** When Time Machine is busy while a build keeps rewriting its output (Xcode's DerivedData, a project's build or node_modules folder), its card says so and offers to leave that folder out of later backups, in one click. Only folders a build makes again are offered. Back it up again from its line at the top of the panel.
- **Test my network**, a tool along the bottom of the panel, for a Mac that feels slow when nothing on it is busy. It shows how the Mac is connected without asking for any permission, and runs Apple's own network test only when you press Start test, since the test fills your connection for up to 30 seconds.
  - The page keeps one size from the moment it opens: the Wi-Fi signal (Strong, Fair, or Weak, with the numbers a click away), download, upload, and delay fill in as the test runs.
  - The result says in a few words whether the network is the problem, then in one plain sentence what the connection is fine for and only what isn't, and marks web, HD and 4K video, video calls, and games as Fine, Laggy, or Too slow, from the speeds the FCC, Netflix, and Zoom publish.
  - When something is wrong, it offers fixes for the causes it found (a sync app filling the connection, a weak Wi-Fi signal, a router setting, AirDrop, iCloud Private Relay, a VPN or proxy), most useful first. When the network is fine, it offers none.

### Changed

- A card's options are in two groups: **One click**, which Cool Head does for you, then **Do it yourself**, where Cool Head takes you there and shows how. Your tasks have a dashed outline; Cool Head's are filled.
  - When the recommended option would be a task for you, a safe one-click option that helps is recommended instead, such as Limit Chrome or Run it cooler.
  - Options with consequences that can't be undone or known are tagged **Caution** in the tile's corner: Stop, Force Quit, Restart the browser, and quitting an app in the middle of something (containers, a call, a game, a browser's tabs). Quitting an app that asks to save, or loses nothing, such as Slack, isn't, and is recommended when it's the way to free memory.
  - A task that fixes the cause when the recommended option only eases it, such as closing Chrome's heaviest tabs, is tagged **Fixes the cause**.
  - Within each group, the options that do the most come first.
  - The switches in the panel show their color when on, even while another app is in front.
- **Tools along the bottom, settings in the right-click menu.** The bottom of the panel is now a row of tools, each an icon with its name: Network (Test my network), Battery, Trends (the past week from macOS's power log, with a chart icon), Trusted, and Report at the right, each opening in the panel's middle. The Activity Monitor and Quit buttons are gone; Quit is in the right-click menu. The settings move into a **Settings** submenu of the right-click menu, each one a toggle: Notifications and Open at Login, then how Cool Head looks: a new Hide Tool Names, and Melting Snowflake Icon, which replaces the Menu Bar Icon choice. Check for Updates stays at the top of the menu, and About and Quit at the bottom.
  - **Battery** opens the battery's page, laid out like Test my network: whether it's healthy, three figures (how much charge it holds, its cycles against Apple's rating, its temperature), what it's doing now (on battery, charging, or plugged in and why it isn't charging), Low Power Mode, and the switch for **Battery Saver**, the setting first called Save Battery When Unplugged, which you may turn on and off as your day changes. The battery line above the tools is gone. A Mac with no battery has no Battery tool.
  - Trusted is now a list in the panel, the standard macOS way: select one and press − to stop trusting it, or press + to choose an app to trust.

### Fixed

- The Docker card says Docker's virtual machine stops on its own 5 minutes after the last container stops (Docker's Resource Saver, on by default); it had said the machine keeps running.

## [0.6.1] - 2026-11-16

### Fixed

- The Melting Snowflake icon's drawings are full size again: the yellow or red bar added in 0.6.0, which shrank them, is gone.

## [0.6.0] - 2026-11-16

### Added

- **The graphics chip.** Cool Head now sees how much of the graphics chip each app uses. Something keeping it busy, about half of it or more for over a minute, gets a card even when it uses little CPU, and the card says how much: "It's keeping about 70% of the graphics chip busy." An app doing this can be quit from its card. Games stay calm and are never slowed, and Chrome's graphics process and Safari's web pages say how much of the chip they use. Each card's details show the graphics chip too, and `coolhead now` lists what is busy on it.
- Cards for processes that are stuck while using almost nothing, which Cool Head didn't see before because it looked only at busy ones:
  - **Paused by something other than Cool Head** for 5 minutes: **Resume it** is recommended. A job you suspended in a Terminal window with Control-Z gets a calm card after 30 minutes, saying how to bring it back.
  - **Stuck waiting on a disk or network drive** for 2 minutes, naming the drive when it can: check or reconnect the drive. Nothing can stop such a process until the drive answers, so Stop isn't offered.
  - **Apps macOS marks Not Responding** for a minute: give it a few minutes, then, if it is still stuck and idle after 5 minutes, **Force quit** is recommended (it asks first).
  - Each says what started it, and names programs it started that may be waiting on it.
- `coolhead hangs` lists what's paused, waiting on a drive, or not responding right now.
- **Restart Chrome, keeping your tabs**: when memory is tight and Chrome is one of the three biggest users, one click closes Chrome the normal way (so it can ask about downloads first) and reopens it with the same windows and tabs, freeing the memory Chrome builds up over time. Incognito windows, text typed into a form and not sent, and downloads in progress don't come back; the option says so. If Chrome hasn't closed within 20 seconds (it may be asking you something), it isn't reopened, and Cool Head tells you. Also for Microsoft Edge, Brave, Vivaldi, and Chromium.
- When a sync app (Google Drive, Dropbox, OneDrive, Box) is busy and a build or other job is writing lots of files into a folder it syncs, its card says so and recommends keeping that project out of synced folders. For a job in the sync app's own folder it says "probably"; in Documents or Desktop, which it may be backing up, it says "may", since only the sync app's own settings say which folders it backs up and Cool Head doesn't read them.

### Changed

- Every option is a button. What Cool Head can't do itself, it opens the app where it's done and says how (Chrome's Task Manager, a game's settings, the Terminal window a job is suspended in), takes you to the settings page (Memory Saver, Edge's sleeping tabs), shows the folder in Finder, or shows the steps under the option (giving the Mac air, reconnecting a drive). Statements such as "macOS needs this" are now part of the card's explanation.
- Card wording, rewritten by hand: each fact said once (a long-running macOS task no longer gives its time twice, and the memory card no longer repeats the headline's figure), several facts about one thing joined into one sentence ("It's adding to the heat, competing with Hades, and draining your battery"), every step with a verb ("Choose Window ▸ Task Manager, then click CPU to put the busiest first"), and plain words for what started a process ("a command from a window or script that has since closed"). `coolhead wording` prints every card's text from the recorded examples.
- The Melting Snowflake icon gets a bar underneath when something needs a look: yellow when it's worth watching, red for a problem. When all is well it stays a plain snowflake.
- When a sync app (Google Drive, Dropbox, OneDrive, Box) uses the most memory, the memory card says quitting it loses nothing (it catches up when reopened), instead of "It'll ask to save first", and also offers Pause syncing, noting that pausing doesn't free its memory.
- Stop now works on a paused process: it lets it carry on just long enough to end.
- When a card names two things that look alike, it says what each is: "the Claude app" and "the claude command-line program", or "another ffmpeg" for a second copy of the same program.

## [0.5.0] - 2026-11-15

### Added

- **Limit Chrome**: when memory is tight and Chrome is one of the three biggest users, one click sets Chrome's own memory limit, with Memory Saver at Maximum. Past the limit, Chrome unloads tabs you aren't using; they reload when you click them. The limit is a quarter of your Mac's memory or what Chrome is using now, whichever is lower, so it frees memory straight away, and never below 2 GB. Chrome will then say it's "managed by your organization"; that's how Chrome shows any setting made this way. It isn't offered if Chrome already has these settings, and Cool Head only removes what it set.
- Anything Cool Head is slowing, pausing, or limiting (a job it's slowing to keep your Mac cool, a job paused until you plug in, a sync app you paused, the Chrome limit) is one line at the top of the panel saying so, with **Speed up**, **Resume**, or **Remove** to open it and put it back.

### Changed

- A click anywhere on a card opens it, and another click closes it. **Explore fixes** and **Show less** say so, with an arrow.
- Each option is its own bordered button, with what it does inside it. Options that close or end something have a red icon.
- Once an option has done something, the options give way to a note saying what was done, so nothing is left to press twice.
- Putting something back now happens only at the top of the panel, never in the right-click menu, which is for settings.
- When memory is tight and the Chrome limit is already on, the card says whether Chrome is within it, instead of offering to remove it.
- A warm Mac with nothing working hard says when tight memory is adding to the work.
- New screenshots for this version.

### Fixed

- The About window showed the version twice.
- Making screenshots could hide Cool Head's menu bar icon until it was restarted.

## [0.4.5] - 2026-11-15

### Changed

- A card that's warming your Mac shows **Explore fixes**, not Learn more.
- New screenshots and documentation for this version.

### Fixed

- **Turn on Energy Saver** and **Turn off the extension** now copy the settings address and bring Chrome forward, with the keys to press. Chrome doesn't open its own settings pages when another app asks, so the old buttons opened Chrome without the page.

## [0.4.4] - 2026-11-15

### Added

- Security, device management, and VPN software (CrowdStrike, Jamf, Microsoft Defender, Zscaler, and others) is never offered Stop, Run it cooler, or Quit: stopping it could leave your Mac unprotected or break your organization's rules. The list comes from System Sentinel, with thanks.
- Sync apps (Google Drive, Dropbox, OneDrive, Box) recommend **Pause syncing** for 1 hour, 3 hours, or until 8pm. Cool Head opens the app so you can pause it, and reminds you to resume, even after a restart.
- **Save Battery When Unplugged** (on by default, in the right-click menu): on battery, a really hungry job (two cores for 10 minutes) or a long one (a core for 30 minutes) is flagged even when your Mac is cool, with **Pause until you plug in**; below 50% battery, any job using a core for 10 minutes. Nothing is lost, and it carries on by itself when you plug in. Cool Head never leaves a job paused: quitting or restarting it lets the job carry on.

## [0.4.3] - 2026-11-15

### Added

- Chrome without quitting it. Cool Head tells a busy tab, a busy extension, and Chrome's graphics work apart (also in Edge, Brave, and Arc), and offers what fits: run just that tab cooler, turn on Energy Saver, turn off an extension, or close just that tab, before ever suggesting Quit.
- If an app speeds a slowed process back up (Chrome does when you switch to the tab), it's unpinned and Cool Head says so.

### Changed

- If you're using Chrome, Energy Saver comes first, since the busy tab may be the one you're on.

### Fixed

- Works with Chrome 157, which renamed its helper programs.

## [0.4.2] - 2026-11-15

### Added

- Games are recognised as games, wherever they're installed (Steam included), instead of "We can't tell why". A game is never slowed down: while your Mac is warm it suggests lower graphics settings, and Quit warns you to save first.

### Changed

- While a game is running, other busy work is offered to run cooler first, to leave the game more power.

## [0.4.1] - 2026-11-15

### Added

- A warm Mac now shows what's warming it. Each cause gets a card that says it's adding to the heat, with something to do, and the icon turns yellow. If nothing is working hard, a card says so and what usually explains it.
- **Always trust** an app or job from the clock in a card's corner. It stays listed but calm, and is flagged anyway if it looks stuck, your Mac gets hot, or it has been busy for 8 hours without a break. See and remove trusted items from the right-click menu.

### Changed

- Options come in one order everywhere: the recommended one first, marked **Recommended**; then ones you can undo; then ones that close or lose something; then sharing.
- Waiting is now a clock in each card's corner: check back in 10 minutes, 30 minutes, or an hour.
- The frozen border is frost on glass: crystals in the corners, a clear middle, no snowflakes.

## [0.4.0] - 2026-11-15

### Added

- Every option has an icon and a few plain words on what it does.
- After you act, a green note says what changed. If something fails, it says so in orange, with a way to report it.
- Anything you slow down stays pinned at the top, frosted over, until it finishes or you set it back.
- New menu bar icon option, from the right-click menu: **Melting Snowflake**, which melts into a puddle as things heat up.
- Notes like these, after each update.

### Changed

- Cards say less: one short sentence, then **Explore fixes** for anything worth watching, or **Learn more** for calm ones.
- "Nerdy stuff (detailed info)": the whole line opens it, with a button to copy the details.
- The memory card names the three biggest users and offers real fixes: close a browser's heaviest tabs, turn on Memory Saver, or quit an app, with what each costs. It no longer mentions disk swap on Macs that aren't using it.
- The panel is a clean rounded rectangle under the icon. Its top and bottom stay put, the middle scrolls when it's long, and it opens tidy every time.

## [0.3.2] - 2026-11-15

### Fixed

- Run it cooler said "macOS didn't apply it" even when it had worked. It now checks the right way.

## [0.3.1] - 2026-11-15

### Added

- Click **Cool Head v…** at the top right to check for updates.
- On first launch, the panel opens with a short welcome, since Cool Head has no window.

## [0.3.0] - 2026-11-15

### Added

- Cool Head updates itself. It checks once a day (you can turn that off), and installs an update only after checking it's genuinely signed by the project. From this version on, every release's download has a signature file.

## [0.2.0] - 2026-11-15

### Added

- **Report a problem**: your own words plus what Cool Head did recently, anonymised, sent as a GitHub issue only if you choose.

### Changed

- The memory card counts each app's processes together and offers fixes with their risks.
- No warning offers only "wait"; there's always something you can do.
- Choosing to wait turns the icon green until then, unless things get worse.
- A rounded caution triangle in a stronger yellow.

### Notes

- This download has no signature file: signing began with 0.3.0, the first version that updates itself.

## [0.1.0] - 2026-11-15

### Added

- The first public version: a menu bar app that explains what's keeping your Mac hot or busy, in one sentence, with options to act.
- It tells working jobs from stuck ones, and never suggests stopping a job just because it's big.
- **Share this case** for anything it can't explain, anonymised and shown to you first.
- A command-line tool, `coolhead`, for the same answers in Terminal.

### Notes

- This download has no signature file: signing began with 0.3.0, the first version that updates itself.

[Unreleased]: https://github.com/ThePhilDiamond/CoolHead/compare/v0.17.0...HEAD
[0.17.0]: https://github.com/ThePhilDiamond/CoolHead/compare/v0.16.0...v0.17.0
[0.16.0]: https://github.com/ThePhilDiamond/CoolHead/compare/v0.15.0...v0.16.0
[0.15.0]: https://github.com/ThePhilDiamond/CoolHead/compare/v0.14.1...v0.15.0
[0.14.1]: https://github.com/ThePhilDiamond/CoolHead/compare/v0.14.0...v0.14.1
[0.14.0]: https://github.com/ThePhilDiamond/CoolHead/compare/v0.13.0...v0.14.0
[0.13.0]: https://github.com/ThePhilDiamond/CoolHead/compare/v0.12.0...v0.13.0
[0.12.0]: https://github.com/ThePhilDiamond/CoolHead/compare/v0.11.0...v0.12.0
[0.11.0]: https://github.com/ThePhilDiamond/CoolHead/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/ThePhilDiamond/CoolHead/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/ThePhilDiamond/CoolHead/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/ThePhilDiamond/CoolHead/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/ThePhilDiamond/CoolHead/compare/v0.6.1...v0.7.0
[0.6.1]: https://github.com/ThePhilDiamond/CoolHead/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/ThePhilDiamond/CoolHead/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/ThePhilDiamond/CoolHead/compare/v0.4.5...v0.5.0
[0.4.5]: https://github.com/ThePhilDiamond/CoolHead/compare/v0.4.4...v0.4.5
[0.4.4]: https://github.com/ThePhilDiamond/CoolHead/compare/v0.4.3...v0.4.4
[0.4.3]: https://github.com/ThePhilDiamond/CoolHead/compare/v0.4.2...v0.4.3
[0.4.2]: https://github.com/ThePhilDiamond/CoolHead/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/ThePhilDiamond/CoolHead/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/ThePhilDiamond/CoolHead/compare/v0.3.2...v0.4.0
[0.3.2]: https://github.com/ThePhilDiamond/CoolHead/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/ThePhilDiamond/CoolHead/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/ThePhilDiamond/CoolHead/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/ThePhilDiamond/CoolHead/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/ThePhilDiamond/CoolHead/releases/tag/v0.1.0
