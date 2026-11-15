# What's new in Cool Head

Short notes for each version. The newest is first. Each release's notes on GitHub come from this file, and the app shows the notes for a version once, after it updates to it.

## v0.4.5 (15 November 2026)

- **Turn on Energy Saver** and **Turn off the extension** now copy the settings address and bring Chrome forward, with the keys to press. Chrome doesn't open its own settings pages when another app asks, so the old buttons opened Chrome without the page.
- A card that's warming your Mac shows **Explore fixes**, not Learn more.
- New screenshots and documentation for this version.

## v0.4.4 (15 November 2026)

- Security, device management and VPN software (CrowdStrike, Jamf, Microsoft Defender, Zscaler and others) is never offered Stop, Run it cooler or Quit: stopping it could leave your Mac unprotected or break your organization's rules. The list comes from System Sentinel, with thanks.
- Sync apps (Google Drive, Dropbox, OneDrive, Box) recommend **Pause syncing** for 1 hour, 3 hours or until 8pm. Cool Head opens the app so you can pause it, and reminds you to resume, even after a restart.
- **Save Battery When Unplugged** (on by default, in the right-click menu): on battery, a really hungry job (two cores for 10 minutes) or a long one (a core for 30 minutes) is flagged even when your Mac is cool, with **Pause until you plug in**; below 50% battery, any job using a core for 10 minutes. Nothing is lost, and it carries on by itself when you plug in. Cool Head never leaves a job paused: quitting or restarting it lets the job carry on.

## v0.4.3 (15 November 2026)

- Chrome without quitting it. Cool Head tells a busy tab, a busy extension and Chrome's graphics work apart (also in Edge, Brave and Arc), and offers what fits: run just that tab cooler, turn on Energy Saver (one click opens Chrome's Performance settings), turn off an extension, or close just that tab, before ever suggesting Quit.
- If you're using Chrome, Energy Saver comes first, since the busy tab may be the one you're on.
- If an app speeds a slowed process back up (Chrome does when you switch to the tab), it's unpinned and Cool Head says so.
- Works with Chrome 157, which renamed its helper programs.

## v0.4.2 (15 November 2026)

- Games are recognised as games, wherever they're installed (Steam included), instead of "We can't tell why". A game is never slowed down: while your Mac is warm it suggests lower graphics settings, and Quit warns you to save first.
- While a game is running, other busy work is offered to run cooler first, to leave the game more power.

## v0.4.1 (15 November 2026)

- A warm Mac now shows what's warming it. Each cause gets a card that says it's adding to the heat, with something to do, and the icon turns yellow. If nothing is working hard, a card says so and what usually explains it.
- Options come in one order everywhere: the recommended one first, marked **Recommended**; then ones you can undo; then ones that close or lose something; then sharing.
- Waiting is now a clock in each card's corner: check back in 10 minutes, 30 minutes or an hour.
- **Always trust** an app or job from the same clock. It stays listed but calm, and is flagged anyway if it looks stuck, your Mac gets hot, or it has been busy for 8 hours without a break. See and remove trusted items from the right-click menu.
- The frozen border is frost on glass: crystals in the corners, a clear middle, no snowflakes.

## v0.4.0 (15 November 2026)

- Cards say less: one short sentence, then **Explore fixes** for anything worth watching, or **Learn more** for calm ones.
- Every option has an icon and a few plain words on what it does.
- After you act, a green note says what changed. If something fails, it says so in orange, with a way to report it.
- Anything you slow down stays pinned at the top, frosted over, until it finishes or you set it back.
- "Nerdy stuff (detailed info)": the whole line opens it, with a button to copy the details.
- The memory card names the three biggest users and offers real fixes: close a browser's heaviest tabs, turn on Memory Saver, or quit an app, with what each costs. It no longer mentions disk swap on Macs that aren't using it.
- The panel is a clean rounded rectangle under the icon. Its top and bottom stay put, the middle scrolls when it's long, and it opens tidy every time.
- New menu bar icon option, from the right-click menu: **Melting Snowflake**, which melts into a puddle as things heat up.
- Notes like these, after each update.

## v0.3.2 (15 November 2026)

- Run it cooler said "macOS didn't apply it" even when it had worked. It now checks the right way.

## v0.3.1 (15 November 2026)

- Click **Cool Head v…** at the top right to check for updates.
- On first launch, the panel opens with a short welcome, since Cool Head has no window.

## v0.3.0 (15 November 2026)

- Cool Head updates itself. It checks once a day (you can turn that off), and installs an update only after checking it's genuinely signed by the project.

## v0.2.0 (15 November 2026)

- **Report a problem**: your own words plus what Cool Head did recently, anonymised, sent as a GitHub issue only if you choose.
- The memory card counts each app's processes together and offers fixes with their risks.
- No warning offers only "wait"; there's always something you can do.
- Choosing to wait turns the icon green until then, unless things get worse.
- A rounded caution triangle in a stronger yellow.

## v0.1.0 (15 November 2026)

- The first public version: a menu bar app that explains what's keeping your Mac hot or busy, in one sentence, with options to act.
- It tells working jobs from stuck ones, and never suggests stopping a job just because it's big.
- **Share this case** for anything it can't explain, anonymised and shown to you first.
- A command-line tool, `coolhead`, for the same answers in Terminal.
