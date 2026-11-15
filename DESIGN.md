# Cool Head: design choices

Drafted 14 November 2026 for Phil's review, at his request: *"we also should possibly consider user journeys, workflows, UX, layout, build language and other choices"*. Each choice has a recommendation and the reason; Phil decides.

## Journeys

1. **"Why is my Mac hot?"** Click the menu bar icon. The panel opens on the answer: one card per cause, worst first. If all is calm, it says so in one line.
2. **It tells you first.** Something has been abnormal for a while (default 10 minutes): the menu bar badge changes (yellow triangle, or red octagon for a problem), and a notification says something needs a look, without naming it (macOS keeps notification text). No sound, at most one notification per cause, none for a card you chose to wait on.
3. **Act.** The card's one button, Explore fixes, shows how Cool Head knows and the options, each with its consequence. The options always come in one order (Phil, 15 November 2026): the recommended one first, as a filled button tagged Recommended; then options you can undo, most helpful first; then options that close or lose something, least loss first; then Share this case. Stopping asks once and names the process.
3a. **Not now.** Waiting isn't an option in the list: a clock in each card's corner hides it for 10 minutes, 30 minutes or an hour (never "until it's done"); it comes back sooner if it gets worse. From the same clock, **Always trust** an app or job: it stays listed but calm, and is flagged anyway if it looks stuck, the Mac gets hot, or it has been busy nonstop for 8 hours. Trusted items are listed, and removable, in the right-click menu.
3b. **Warm means a cause.** While the Mac is warm, anything warming it that you can act on turns the badge yellow, and its card says it's adding to the heat; if nothing is working hard, a card says so and what usually explains it.
4. **Look closer.** Under the options, "The facts" opens the evidence in place: the facts that led to the sentence, in plain lines, with anything that looks like a password hidden. Nothing else to navigate.
5. **Unknown.** The card says it can't tell, and offers Look it up (a web search for the process name) and Share this case (an anonymised report, shown in full, that the person can open as a GitHub issue). Those are the only ways anything leaves the Mac, and only when pressed.
6. **No looking back.** Cool Head is about now; it keeps no record of past causes. (A 24-hour chart and a "things today" list were tried and removed on 15 November 2026. Phil: *"I don't know what that chart/bar is at the bottom. Is it meant to be temperature? Speed? System resource load? It's not clear or actionable, which just adds confusing clutter."*)

## Layout

The menu bar panel, about 360 points wide, nothing else:

- Status line: "Running warm: 1 cause" or "All calm".
- Cards: one short sentence each, with Explore fixes (worth watching) or Learn more (calm).
- Along the bottom: battery health, then switches for notifications and open at login, and icons for Activity Monitor, About and Quit. The name and version ("Cool Head v0.1.0") sit small at the top right. Right-clicking the menu bar icon shows About and Quit.

No tabs, no tables, no process list. Activity Monitor is one click away, from the icon at the bottom of the panel, for anyone who wants the raw list.

## Look

System font, system colors, generous spacing, one accent color for "needs a look". Light and dark follow macOS. Icons only where they carry meaning (heat, battery, a process's own app icon).

## Build language

**Swift with SwiftUI (recommended).** Native menu bar app, small (a few MB), lowest overhead, direct access to the system facts (process info, battery, thermal state) and to Apple's on-device model. Builds on this Mac with the installed Command Line Tools. Weakest point: Mac-only, which is the point.

Alternatives considered: a web app in a native shell (Tauri or Electron) would make the design easier to iterate but would be 10 to 100 times larger, use more memory than the problems it reports, and still need native code for every system fact. Python would be quick to write but cannot make a proper menu bar app without extra layers.

## Other choices

- **No history (Phil, 15 November 2026):** Cool Head is not a record of the past. It samples every 10 seconds and keeps only what it needs in memory (recent readings, which cards have already notified); nothing is written to disk. The one exception is the person's own choice: the apps and jobs they mark Always trust, saved on this Mac as a setting (no record of what happened). Diagnostic logs exist only inside a case the user chooses to share, or where the law requires.
- **Overhead target:** under 0.5% of the Mac on average (not shown in the panel; Phil, 15 November 2026: the "Cool Head uses…" line was unnecessary).
- **Permissions:** none required. Full Disk Access is optional, only for reading other users' or system processes' files.
- **Distribution:** for Phil's Mac only at first, ad-hoc signed. Public release later is a separate decision.
