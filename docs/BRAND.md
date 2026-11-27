# Cool Head's look and voice

One look and one voice for the Mac app, its Chrome extension, and these pages, on every platform. Cool Head uses its own blue rather than each computer's accent color, so it looks the same everywhere. Contrast figures are WCAG 2.2 ratios; AA asks 4.5:1 for text and 3:1 for icons and control edges.

## Color

**Cool Head blue** is the color of what Cool Head does and offers: the recommended option, switches that are on, the selected tool, links (including a card's Explore fixes, even on a warning), and focus rings. It's Cool Head's own, not the Mac's accent color, which differs on each Mac and which Chrome hides from extensions. A blue also keeps "do this" apart from the yellow, orange, and red that say "watch out".

| Use | Light | Dark |
|---|---|---|
| Blue for marks: links, switches, icons | `#1769D1` | `#4A9EFF` |
| Blue behind text: the recommended option, the open tool | `#0F52AD` | `#0F52AD`, with a `#4A9EFF` edge (5.1:1 against the dark card) |
| Text on the blue behind text | white, 7.4:1 (AAA) | white, 7.4:1 (AAA) |
| Blue text on the panel | 4.9:1 on the light panel | 6.1:1 on `#1E1E1E` |

Text on blue is never dimmed: white at 80% on `#1769D1` measured 4.0:1, under the 4.5:1 text needs, and was harder to read. Text goes on the deeper blue instead, at full strength. The open tool along the bottom is the same: blue on a pale-blue highlight measured 3.0:1 in dark and 4.4:1 in light on a plain background, and under 2:1 when the panel's frost sat over a bright desktop, so it's white on the deep blue. The top and bottom bars have a denser frost of their own, the window's color at 75% under the level's tint: over a bright desktop in dark mode the panel's frost turned mid-gray and gray text on it fell to about 3:1, and with the denser frost it measured 5:1.

**At night** Cool Head stays blue and leaves warmth to the Mac's Night Shift, which warms the whole screen, Cool Head included. I considered an orange night mode and decided against it: orange already means "watch out" on the same cards, and white text on it measured 4.7:1, against the deep blue's 7.4:1.

**The network test's dashes** are the one place Cool Head uses other colors for itself: while a test runs, they circle the Network tool's globe as a small neon rainbow, a quiet nod to pride, whether the tool is open or closed. They aren't orange, which would say "watch out", and moving through every color, they don't read as any one status.

**Status colors** say how the Mac is, and never mean "click here":

| Status | Color | Used for |
|---|---|---|
| All good | macOS green | the top row's wash, gauges, the menu bar badge |
| Worth watching | yellow `#FFBD00` | the same |
| Problem | macOS red | the same; "ends without saving" on options |
| Caution | macOS orange | warnings on cards |

Status colors always come with words or a shape (the Melting Snowflake icon works without color), never color alone. As text on the light panel they fall short of 4.5:1, so they're used for fills, washes, and marks, with the words in the text color.

**Neutrals** are macOS's own text colors, the panel's card and edge colors in `Ink` (Sources/CoolHeadApp/PanelView.swift), and the level's wash at 10% behind the top row and the tools bar.

## Type

The system font everywhere, so each feels native: SF Pro on the Mac (SwiftUI's defaults: body, callout, and caption), and in the extension the system stack `system-ui, -apple-system, "Segoe UI", Roboto, sans-serif`, which is SF Pro on a Mac, Segoe UI on Windows, and the desktop's own font on Linux. Monospaced only for Nerdy stuff. Sentence case for every title, button, and heading.

## Icons

- The app's icon: the menu bar's melting snowflake, in white on Cool Head blue, its drops and puddle a paler white so the flake leads (docs/images/logo.png, drawn by scripts/make-icon.swift). It replaced a smiling face with snowflakes in 0.17.0, so the app icon and the menu bar are one family.
- The menu bar, in two styles (docs/images/menu-icons.png): the Status badge, one melting snowflake with ice-blue drops and puddle, the same at every level, with a green circle, yellow triangle, or red octagon; and the Melting Snowflake, whole, melting, or in flames. The menu bar keeps the bolder ice-blue drops, which show better at its size than the app icon's pale ones.
- Inside the app: SF Symbols, in the text color or Cool Head blue. Two arrows in a circle mean Cool Head and its Chrome extension are working together, wherever that shows.

## Voice

- Every card aims to make it easy to see what's happening and decide what to do, in simple, literal English that a person who learned English as a second language reads correctly the first time: the fewest words that keep it clear, and the same words and shapes for the same things on every card (26 November 2026).
- Plain, non-technical words where possible; US English; the Oxford comma; no em dashes; no exclamation marks.
- On cards: the present tense, with "still … after" for something still going on ("Site is still busy after 3 hours."), and the past only for an event that is over; never the present perfect ("has used"); no contractions ("is not"); no idioms or two-word verbs ("Wait a few minutes", not "Give it a minute"; "Search the web", not "Look it up"), except macOS's own Turn on and Turn off; no "we"; full sentences of at most 25 words, and at most 3 in an explanation.
- A card gives the verdict, a brief disclaimer, and the advice, and says what Cool Head thinks rather than leaving it to the reader.
- Every "why" ends in what it means for the person.
- Each option says what it does and what it costs before it's pressed.
- Each fact once. A card says each fact in one place: the headline, an option's title, or the explanation. A sentence that would say it again is cut, not reworded.
- One word for each idea, from the word list in docs/CARD-TEMPLATE.md ("app", "program", "part of macOS", "working hard", "heat", "stuck", "not responding", "memory", "storage", "Quit", "Stop", "Run it cooler"); four words say how sure Cool Head is: none for a fact, "probably", "may", and "usually".
- Figures as numerals, rounded, with "about" for an estimate (a "~" only where space is tight and the text isn't a sentence: Nerdy stuff, the dials, the menu bar); times written as 2:30pm.
- A wording change stays only if the card ends up shorter or clearer, read card by card (25 and 26 November 2026).

## Card template

Every card fills the same slots, whatever it's about (adopted 26 November 2026). The code writes the sentences from the slots (Sources/CoolHeadCore/CardTemplate.swift), so no card takes a shape of its own, and the selftest checks every card made from it against these rules (card-template). Each slot's grammar, the verdicts, and the word list, with their sources, are in docs/CARD-TEMPLATE.md.

- Headline: subject, reading, verdict. "A Google Chrome tab is still working hard after 1 hour. This is more than usual." A memory card leads with its verdict: "Apps and programs are using almost all of your Mac's memory. Google Chrome uses the most, 5.1 GB."
  - Subject: what the card is about, named the same way on every card.
  - Reading: one measurement, whose type sets its words: how hard it works ("is working hard", "is still working hard after 1 hour"; the figure is in Nerdy stuff), the graphics chip, memory, progress ("is 96% done"), its last progress ("made its last progress at 1:39pm"), a start ("started at 3:38pm"), an activity, a temperature, or a count.
  - Verdict: one sentence from a closed set, each with one meaning (the list is in docs/CARD-TEMPLATE.md): "This is normal." "This is more than usual." "This is longer than usual." "Wait a few minutes." "It is probably stuck." "It is not responding." "Apps and programs are using almost all of your Mac's memory." "It will finish at about 2:30pm." and the rest. A card whose reading is a single event, such as a crash restart, has none.
- Explanation: the evidence (how Cool Head knows, with no figure from the headline), then what it means for you, in at most 3 full sentences; none where Cool Head knows nothing more.
- Terms footer: a word a reader may not know (memory and storage, so far) is defined once, in one visible line with ⓘ under the cards that use it, never on a card.
- Option: a title that starts with one specific verb ("Quit Slack instead to free 1.1 GB"); then a consequence that starts with "This" (what it does), then what you lose ("Nothing is lost." "Unsaved work is lost." "You may lose up to 2 hours of its work." "You may lose the work it did." "It asks you to save your work first."), then "You can undo this." where Cool Head can.

## Accessibility

Text at least 4.5:1, icons and control edges at least 3:1, in light and dark; nothing by color alone; every control reachable by keyboard and named for VoiceOver; targets at least 24 by 24 points; no motion that matters when reduced motion is on.
