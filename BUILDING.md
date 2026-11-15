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

To see the panel without clicking (for screenshots or checks), this waits 25 seconds and writes `panel-light.png` and `panel-dark.png`, then quits:

```bash
COOLHEAD_SNAPSHOT=/tmp/panel "build/Cool Head.app/Contents/MacOS/Cool Head"
```

## The icon

The logo and app icon are drawn in code. To redraw them:

```bash
swift scripts/make-icon.swift build/icon app
```

```bash
iconutil -c icns build/icon/AppIcon.iconset -o Resources/AppIcon.icns
```

The menu bar icon is drawn in `Sources/CoolHeadApp/CoolHeadApp.swift` (`MenuIcon`). The logo ideas that weren't chosen can still be drawn: `sheet`, `linesheet`, `facesheet` and `facesheet2`.

## Layout

- `Sources/CoolHeadCore`: everything that reads the Mac and decides what a card says. `Proc.swift` (kernel calls), `MacState.swift` (heat, power, battery, memory), `Evidence.swift` (the facts about one process), `Progress.swift` (reading a job's own progress lines), `Catalogue.swift` (known patterns), `Card.swift` (the decision), `Watcher.swift` (sampling, in memory only), `Fixtures.swift` (examples for selftest).
- `Sources/coolhead`: the command-line tool.
- `Sources/CoolHeadApp`: the SwiftUI menu bar app.
- `scripts`: packaging and icon drawing.
