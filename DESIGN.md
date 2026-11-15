# Cool Head: design choices

Drafted 14 November 2026 for Phil's review, at his request: *"we also should possibly consider user journeys, workflows, UX, layout, build language and other choices"*. Each choice has a recommendation and the reason; Phil decides.

## Journeys

1. **"Why is my Mac hot?"** Click the menu bar icon. The panel opens on the answer: one card per cause, worst first. If all is calm, it says so in one line, with the last 24 hours as a strip.
2. **It tells you first.** Something has been abnormal for a while (default 10 minutes): the icon gets a dot, and a notification gives the card's one sentence. Clicking opens the panel on that card. No sound, at most one notification per cause.
3. **Act.** The card's one button does the obvious thing (let it finish, run it cooler, close the tab, quit the app). Stopping anything asks once.
4. **Look closer.** Tapping the card opens its evidence in place: the facts that led to the sentence, in plain lines. Nothing else to navigate.
5. **Unknown.** The card says it is not sure and offers Look it up, which opens a web search for the process name in the browser. That is the only network use.
6. **Looking back.** "What happened today?" is the 24-hour strip: heat, power and CPU on one line, with each past card as a mark you can tap.

## Layout

The menu bar panel, about 360 points wide, nothing else:

- Status line: "Running warm: 1 cause" or "All calm".
- Cards, each two lines plus one button.
- The 24-hour strip.
- A small gear for settings (launch at login, notifications on or off).

No tabs, no tables, no process list. Activity Monitor is one click away in the gear menu for anyone who wants the raw list.

## Look

System font, system colors, generous spacing, one accent color for "needs a look". Light and dark follow macOS. Icons only where they carry meaning (heat, battery, a process's own app icon).

## Build language

**Swift with SwiftUI (recommended).** Native menu bar app, small (a few MB), lowest overhead, direct access to the system facts (process info, battery, thermal state) and to Apple's on-device model. Builds on this Mac with the installed Command Line Tools. Weakest point: Mac-only, which is the point.

Alternatives considered: a web app in a native shell (Tauri or Electron) would make the design easier to iterate but would be 10 to 100 times larger, use more memory than the problems it reports, and still need native code for every system fact. Python would be quick to write but cannot make a proper menu bar app without extra layers.

## Other choices

- **History:** 7 days, kept on this Mac, sampled every 10 seconds when calm and every 2 seconds while a cause is open; a cause's evidence is kept with it.
- **Overhead target:** under 0.5% of the Mac on average, measured and shown in the gear menu.
- **Permissions:** none required. Full Disk Access is optional, only for reading other users' or system processes' files.
- **Distribution:** for Phil's Mac only at first, ad-hoc signed. Public release later is a separate decision.
