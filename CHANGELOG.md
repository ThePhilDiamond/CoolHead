# Changelog

What changed in each version of Cool Head, newest first, in plain words. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and version numbers follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html): see [RELEASING.md](RELEASING.md). Each release's notes on GitHub are copied from its section here, and the app shows a short version of them once, after it updates.

## [Unreleased]

Changes waiting for the next release are in [changes/](changes/), one file each, so pull requests don't edit the same lines here. The release pull request gathers them into this file (see [RELEASING.md](RELEASING.md)).

## [0.8.0] - 2026-11-17

### Added

- Terms of use, in TERMS.md and linked from About: Cool Head is provided as is, a card is its best judgement and not a guarantee, and what you choose to do with it is your responsibility.
- A program pretending to be part of macOS now says so: "mdworker_local is pretending to be part of macOS", because it uses a macOS name from outside macOS's folders without Apple's signature. One click stops it and moves it to the Trash, where you can put it back.
  - Also a background item labelled like Apple's (`com.apple.…`) whose program Apple didn't sign: one click turns it off, stops it and moves both to the Trash. And a copy in macOS's folders that isn't Apple's, said only where those folders could really have been changed: Cool Head advises turning macOS's protection back on, and offers a reinstall without recommending it.
  - A process named like part of macOS whose program couldn't be found is no longer taken for macOS's own; its card says it's probably part of macOS, but Cool Head couldn't confirm it.
- Cards about macOS's own background work read it by priority and time, not % CPU: Spotlight indexing at low priority says it runs on the efficiency cores and uses little power; after a macOS update it says "You updated to macOS 27.2 2 days ago", and that's normal for hours or days.
  - macOS's own work busy for over a day says it seems stuck, and advises a restart. Still busy after a restart, it says only Apple can fix it, and offers to check for a macOS update or tell Apple.
- A busy Intel app says it runs through Rosetta and won't open in macOS 28, with a search for its Apple silicon version; on macOS 27, where to see Apple's own list. An app set to open using Rosetta, though it has an Apple silicon version, shows how to run it natively.
  - On macOS 26.0 and 26.1, a busy WindowServer names the open apps built on an older Electron that slows the Mac, and recommends updating them.
- When memory is tight and Ollama is keeping an AI model loaded, one click unloads it and frees its memory; Ollama loads it again the next time it's asked something.
  - When the startup disk is nearly full, one click deletes Xcode's build data (it asks first); Xcode rebuilds what it needs.
- A Hardware tool along the bottom: the drive's wear and temperature and whether Time Machine backs it up, crash restarts explained in plain words with what to do, and port errors. At the top of the panel, how your Mac is running: the snowflake whole, melting or in flames as it heats up, with how busy the chip and memory are.
- When memory is tight and the app using the most has kept growing for hours with the same windows open, the memory card says so plainly ("Pages is using more than it usually does"; it's at 8.5 GB, up from 1.1 GB three hours ago) and recommends saving your work, then Quit and reopen, which gives the memory back.
  - Options that quit an app now say to save your work first.
- Stop and Force Quit, which end a program at once with no chance to save, now warn on the option itself: "Anything unsaved will be lost. Click again to stop it." The second click within 5 seconds goes ahead. Quit stays a normal quit, where the app asks about anything unsaved.
- Cards for sleep and power: an app that has kept your Mac awake for hours (with Quit), Low Power Mode left on with the charger while your Mac is busy, and a battery that drained while asleep because the Mac kept waking, naming what woke it. The warm-but-nothing-busy card gives Apple's 10 to 35°C range, and a game's card says Game Mode gives it priority in full screen.
- Cards for browser changes you didn't make: Chrome, Edge or Brave managed by settings Cool Head didn't make, on a Mac no organization manages (with a link to the browser's own policy page), and a browser a script started with an extension loaded from a folder (with the folder shown, and Quit).
- A card for an app that keeps crashing: 5 or more crashes in 24 hours, read from the first line of macOS's crash reports, with Look it up and See the crash reports (in Console).

### Changed

- Rest the pointer on a Caution label to see why the option is risky: "It ends at once, without a chance to save or finish what it was doing." Fixes the cause says why too.
- What Cool Head is holding back, at the top of the panel, has its undo as a button right on each line (Speed up, Remove limit, Turn on and so on), and a chevron opens what each one is. The frost around them now grows along every edge. A folder left out of Time Machine shows its path starting with ~ rather than your account's name.
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
- Cool Head knows six more causes of heat, drain or a Mac that won't sleep, each with its source and the macOS versions it was seen on:
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
  - The page keeps one size from the moment it opens: the Wi-Fi signal (Strong, Fair or Weak, with the numbers a click away), download, upload and delay fill in as the test runs.
  - The result says in a few words whether the network is the problem, then in one plain sentence what the connection is fine for and only what isn't, and marks web, HD and 4K video, video calls and games as Fine, Laggy or Too slow, from the speeds the FCC, Netflix and Zoom publish.
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
- Anything Cool Head is slowing, pausing or limiting (a job it's slowing to keep your Mac cool, a job paused until you plug in, a sync app you paused, the Chrome limit) is one line at the top of the panel saying so, with **Speed up**, **Resume** or **Remove** to open it and put it back.

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

- Security, device management and VPN software (CrowdStrike, Jamf, Microsoft Defender, Zscaler and others) is never offered Stop, Run it cooler or Quit: stopping it could leave your Mac unprotected or break your organization's rules. The list comes from System Sentinel, with thanks.
- Sync apps (Google Drive, Dropbox, OneDrive, Box) recommend **Pause syncing** for 1 hour, 3 hours or until 8pm. Cool Head opens the app so you can pause it, and reminds you to resume, even after a restart.
- **Save Battery When Unplugged** (on by default, in the right-click menu): on battery, a really hungry job (two cores for 10 minutes) or a long one (a core for 30 minutes) is flagged even when your Mac is cool, with **Pause until you plug in**; below 50% battery, any job using a core for 10 minutes. Nothing is lost, and it carries on by itself when you plug in. Cool Head never leaves a job paused: quitting or restarting it lets the job carry on.

## [0.4.3] - 2026-11-15

### Added

- Chrome without quitting it. Cool Head tells a busy tab, a busy extension and Chrome's graphics work apart (also in Edge, Brave and Arc), and offers what fits: run just that tab cooler, turn on Energy Saver, turn off an extension, or close just that tab, before ever suggesting Quit.
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
- Waiting is now a clock in each card's corner: check back in 10 minutes, 30 minutes or an hour.
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

[Unreleased]: https://github.com/ThePhilDiamond/CoolHead/compare/v0.8.0...HEAD
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
