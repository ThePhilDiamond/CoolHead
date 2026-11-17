# Building Cool Head

You need macOS 14 or later on Apple Silicon or Intel, and the Xcode Command Line Tools. Xcode itself is not needed.

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

`coolhead now` shows the Mac's heat, power, battery and memory, and a card for each busy process. `coolhead why <pid or name>` shows one process's card and the facts behind it. `coolhead selftest` checks every recorded example still gives the card it should.

## The menu bar app

```bash
scripts/build-app.sh
```

This builds `build/Cool Head.app`, ad-hoc signed. Open it from Finder; it appears in the menu bar, not the Dock. Because the build is not notarized by Apple, macOS may ask you to confirm the first time you open it.

To see the panel without clicking (for screenshots or checks), this waits 25 seconds and writes `panel-light.png`, `panel-dark.png` and `panel-menu.png` (the menu bar icons), then quits:

```bash
COOLHEAD_SNAPSHOT=/tmp/panel "build/Cool Head.app/Contents/MacOS/Cool Head"
```

Screenshots for the project must never show your own processes. These settings shape them:

- `COOLHEAD_SNAPSHOT_ONLY=<phrase>`: show only cards whose headline contains the phrase (and no welcome or What's new).
- `COOLHEAD_SNAPSHOT_AFTER=<seconds>`: wait this long first (a job needs a minute of being busy before it gets a card).
- `COOLHEAD_SNAPSHOT_OPEN=1`: show cards open.
- `COOLHEAD_SNAPSHOT_STEPS=1`: show each option's mini-guide open.
- `COOLHEAD_SNAPSHOT_WARM=1`: treat the Mac as warm.
- `COOLHEAD_SNAPSHOT_HISTORY=<prefix>` (instead of `COOLHEAD_SNAPSHOT`): draw the history view with made-up history to `<prefix>-history-light.png` and `-dark.png`, and quit, before watching starts.
- `COOLHEAD_TEST_MEMORY=1`: treat memory as tight, so the memory card shows.
- `COOLHEAD_HANG_SECONDS=<seconds>`: show a card for a paused, drive-waiting or Not Responding process after this long, instead of minutes.
- `COOLHEAD_SNAPSHOT_ONLY` takes several phrases separated by `|`.
- `COOLHEAD_SNAPSHOT_COOL=<phrase>` or `COOLHEAD_SNAPSHOT_PAUSE=<phrase>`: run that card's process cooler, or pause it, first.
- `COOLHEAD_SNAPSHOT_ABOUT=1`: also draw the About panel to `<prefix>-about-light.png` and `-dark.png`.

The README's screenshots use a made-up job (a script in a folder named Photo Export that prints progress lines), started with `launchctl submit` so it runs at full priority, and the app run in the background with `ONLY`, `WARM` and `AFTER=100`.

## The icon

The logo and app icon are drawn in code. To redraw them:

```bash
swift scripts/make-icon.swift build/icon app
```

```bash
iconutil -c icns build/icon/AppIcon.iconset -o Resources/AppIcon.icns
```

The menu bar icon, a snowflake, is drawn in `Sources/CoolHeadApp/CoolHeadApp.swift` (`MenuIcon`). The logo ideas that weren't chosen can still be drawn: `sheet`, `linesheet`, `facesheet` and `facesheet2`.

## Layout

- `Sources/CoolHeadCore`: everything that reads the Mac and decides what a card says. `Proc.swift` (kernel calls), `MacState.swift` (heat, power, battery, memory), `Evidence.swift` (the facts about one process, including games and browser parts), `Progress.swift` (reading a job's own progress lines), `Catalogue.swift` (known patterns), `Card.swift` (the decision, and the order of options), `MemoryAdvice.swift` (the memory card), `Protected.swift` (security software and sync apps), `Trust.swift` (Always trust and its limits), `Pauses.swift` (paused jobs and sync reminders), `CaseReport.swift` and `ProblemReport.swift` (the anonymised reports), `Watcher.swift` (sampling, in memory only), `Fixtures.swift` (examples for selftest).
- `Sources/coolhead`: the command-line tool.
- `Sources/CoolHeadApp`: the SwiftUI menu bar app, including `Updater.swift` (signed updates).
- `scripts`: packaging and icon drawing.
