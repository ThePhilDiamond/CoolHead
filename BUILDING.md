# Building Cool Head

You need macOS 15 or later on Apple Silicon or Intel (it still builds on macOS 14, which isn't tested), and the Xcode Command Line Tools. Xcode itself is not needed.

```bash
xcode-select --install
```

## The command-line tool

```bash
swift build -c release
```

```bash
.build/release/coolhead now
```

`coolhead now` shows the Mac's heat, power, battery, and memory, and a card for each busy process. `coolhead why <name or PID>` shows one process's card and the facts behind it: type the process's name or PID from Activity Monitor in place of `<name or PID>`, as in `.build/release/coolhead why mds_stores`. `coolhead selftest` checks every recorded example still gives the card it should.

## The menu bar app

```bash
scripts/build-app.sh
```

This builds `build/Cool Head.app`, ad-hoc signed, with the command-line tool in `Contents/MacOS` beside the app and the helper that links it with Cool Head for Chrome, `coolhead-chrome-host`, in `Contents/Helpers`. Open it from Finder; it appears in the menu bar, not the Dock. Because the build is not notarized by Apple, macOS may ask you to confirm the first time you open it.

To see the panel without clicking (for screenshots or checks), this waits 25 seconds and writes `/tmp/panel-light.png`, `/tmp/panel-dark.png` and `/tmp/panel-menu.png` (the menu bar icons), then quits. The value of `COOLHEAD_SNAPSHOT`, here `/tmp/panel`, is the prefix: the start of each file's path, which the settings below call `<prefix>`.

```bash
COOLHEAD_SNAPSHOT=/tmp/panel "build/Cool Head.app/Contents/MacOS/Cool Head"
```

Screenshots for the project must never show your own processes. These settings shape them; each goes before the command, like `COOLHEAD_SNAPSHOT` above:

- `COOLHEAD_SNAPSHOT_SAMPLES=<sample names>`, such as `COOLHEAD_SNAPSHOT_SAMPLES="crash-loop|job-with-progress"`: show made-up example cards instead of this Mac's. The names are the ones in square brackets in what `.build/release/coolhead wording` prints; separate several with `|`, and keep the quotes.
- `COOLHEAD_SNAPSHOT_RUNNING=cool`, `hot`, or `fire`: show made-up values at the top of the panel (heat and fans) instead of this Mac's.

- `COOLHEAD_SNAPSHOT_ONLY=<phrase>`, such as `COOLHEAD_SNAPSHOT_ONLY=Spotlight`: show only cards whose headline contains that phrase (and no welcome or What's new). For several, separate them with `|` and put the whole value in quotes.
- `COOLHEAD_SNAPSHOT_AFTER=<seconds>`, such as `COOLHEAD_SNAPSHOT_AFTER=70`: wait this many seconds first (a job needs a minute of being busy before it gets a card).
- `COOLHEAD_SNAPSHOT_OPEN=1`: show cards open.
- `COOLHEAD_SNAPSHOT_SETTINGS=1`: show the Settings page open.
- `COOLHEAD_SNAPSHOT_WELCOME=1`: show the first-launch welcome, even beside made-up example cards.
- `-toolLabels YES` or `-toolLabels NO`, after the command: show or hide the tools' names for this screenshot only, without changing your own setting.
- `COOLHEAD_SNAPSHOT_STEPS=1`: show each option's mini-guide open.
- `COOLHEAD_SNAPSHOT_WARM=1`: treat the Mac as warm.
- `COOLHEAD_SNAPSHOT_FIRSTLOOK=1`: show the first look after launch (screenshots skip it otherwise). It ends at the first full reading, about 10 seconds in, so use it with `COOLHEAD_SNAPSHOT_AFTER=4`.
- `COOLHEAD_SNAPSHOT_ENERGY=1`, with `COOLHEAD_SNAPSHOT_BATTERY=1` and `COOLHEAD_SNAPSHOT_SAMPLES`: the Battery page with "What used the most energy this week" open, on made-up history.
- `COOLHEAD_TEST_MEMORY=1`: treat memory as tight, so the memory card shows.
- `COOLHEAD_HANG_SECONDS=<seconds>`, such as `COOLHEAD_HANG_SECONDS=10`: show a card for a paused, drive-waiting, or Not Responding process after this long, instead of minutes.
- `COOLHEAD_SNAPSHOT_COOL=<phrase>` or `COOLHEAD_SNAPSHOT_PAUSE=<phrase>`, with a phrase from a card's headline as for `COOLHEAD_SNAPSHOT_ONLY`: run that card's process cooler, or pause it, first.
- `COOLHEAD_SNAPSHOT_ABOUT=1`: also draw the About panel to `<prefix>-about-light.png` and `-dark.png`.
- `COOLHEAD_SNAPSHOT_NETWORK=reading`, `ready`, `testing`, or `done`: show Test my network in that state, with made-up figures, never this Mac's network.
- `COOLHEAD_SNAPSHOT_NETWORK_VPN=all`, `some`, or `off`, with `COOLHEAD_SNAPSHOT_NETWORK`: a made-up VPN that carries everything (the default), only a few addresses, or none; in `done`, a made-up country websites see you in.

The README's screenshots use a made-up job (a script in a folder named Photo Export that prints progress lines), started with `launchctl submit` so it runs at full priority, and the app run in the background with `ONLY`, `WARM`, and `AFTER=100`.

## The icon

The logo and app icon are drawn in code. To redraw them:

```bash
swift scripts/make-icon.swift build/icon app
```

```bash
iconutil -c icns build/icon/AppIcon.iconset -o Resources/AppIcon.icns
```

The README's logo is the same drawing at 512 pixels:

```bash
sips -z 512 512 build/icon/logo.png --out docs/images/logo.png
```

Then redraw the social card, which uses it: `swift scripts/social-card.swift`.

The menu bar icon, a snowflake, is drawn in `Sources/CoolHeadApp/CoolHeadApp.swift` (`MenuIcon`). The logo ideas that weren't chosen can still be drawn: `sheet`, `linesheet`, `facesheet`, and `facesheet2`, and the logo before the melting snowflake, the smiling face, with `face`.

## Layout

- `Sources/CoolHeadCore`: everything that reads the Mac and decides what a card says. `Proc.swift` (kernel calls), `MacState.swift` (heat, power, battery, memory), `Evidence.swift` (the facts about one process, including games and browser parts), `Progress.swift` (reading a job's own progress lines), `Catalogue.swift` (known patterns), `Card.swift` (the decision, and the order of options), `MemoryAdvice.swift` (the memory card), `Protected.swift` (security software and sync apps), `Trust.swift` (Always trust and its limits), `Pauses.swift` (paused jobs and sync reminders), `CaseReport.swift` and `ProblemReport.swift` (the anonymised reports), `Watcher.swift` (sampling, in memory only), `Fixtures.swift` (examples for selftest).
- `Sources/coolhead`: the command-line tool.
- `Sources/CoolHeadChromeLink`: the link with Cool Head for Chrome: how messages are framed, what they hold, the socket, and the file that tells Chrome where the helper is.
- `Sources/coolhead-chrome-host`: that helper, which Chrome starts and which relays messages between Chrome and Cool Head.
- `Sources/CoolHeadApp`: the SwiftUI menu bar app, including `Updater.swift` (signed updates).
- `scripts`: packaging and icon drawing.
