# Cool Head: design choices

Drafted 14 November 2026 for Phil's review, at his request: *"we also should possibly consider user journeys, workflows, UX, layout, build language and other choices"*. Each choice has a recommendation and the reason; Phil decides.

## Journeys

1. **"Why is my Mac hot?"** Click the menu bar icon. The panel opens on the answer: one card per cause, worst first. If all is calm, it says so in one line.
2. **It tells you first.** Something has been abnormal for a while (default 10 minutes): the icon gets a dot, and a notification gives the card's one sentence. Clicking opens the panel on that card. No sound, at most one notification per cause.
3. **Act.** The card's one button does the obvious thing (let it finish, run it cooler, close the tab, quit the app). Stopping anything asks once.
4. **Look closer.** Tapping the card opens its evidence in place: the facts that led to the sentence, in plain lines. Nothing else to navigate.
5. **Unknown.** The card says it is not sure and offers Look it up, which opens a web search for the process name in the browser. That is the only network use.
6. **Looking back.** "What happened today?" is a short list under the cards: each past cause with its time. (A 24-hour chart was tried and removed on 15 November 2026. Phil: *"I don't know what that chart/bar is at the bottom. Is it meant to be temperature? Speed? System resource load? It's not clear or actionable, which just adds confusing clutter."*)

## Layout

The menu bar panel, about 360 points wide, nothing else:

- Status line: "Running warm: 1 cause" or "All calm".
- Cards: one sentence each, and Explore fixes.
- "N things today": past causes, with times.
- Along the bottom: battery health, then switches for notifications and open at login, and icons for Activity Monitor, About and Quit. The name and version ("Cool Head v0.1.0") sit small at the top right. Right-clicking the menu bar icon shows About and Quit.

No tabs, no tables, no process list. Activity Monitor is one click away, from the icon at the bottom of the panel, for anyone who wants the raw list.

## Look

System font, system colors, generous spacing, one accent color for "needs a look". Light and dark follow macOS. Icons only where they carry meaning (heat, battery, a process's own app icon).

## Build language

**Swift with SwiftUI (recommended).** Native menu bar app, small (a few MB), lowest overhead, direct access to the system facts (process info, battery, thermal state) and to Apple's on-device model. Builds on this Mac with the installed Command Line Tools. Weakest point: Mac-only, which is the point.

Alternatives considered: a web app in a native shell (Tauri or Electron) would make the design easier to iterate but would be 10 to 100 times larger, use more memory than the problems it reports, and still need native code for every system fact. Python would be quick to write but cannot make a proper menu bar app without extra layers.

## Other choices

- **No history (Phil, 15 November 2026):** Cool Head is not a record of the past. It samples every 10 seconds and keeps only what it needs in memory (recent readings, which cards have already notified); nothing is written to disk. Diagnostic logs exist only inside a case the user chooses to share, or where the law requires.
- **Overhead target:** under 0.5% of the Mac on average (not shown in the panel; Phil, 15 November 2026: the "Cool Head uses…" line was unnecessary).
- **Permissions:** none required. Full Disk Access is optional, only for reading other users' or system processes' files.
- **Distribution:** for Phil's Mac only at first, ad-hoc signed. Public release later is a separate decision.
