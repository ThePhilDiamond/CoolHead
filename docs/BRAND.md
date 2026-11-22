# Cool Head's look and voice

One look and one voice for the Mac app, its Chrome extension, and these pages, on every platform. Cool Head uses its own blue rather than each computer's accent color, so it looks the same everywhere. Contrast figures are WCAG 2.2 ratios; AA asks 4.5:1 for text and 3:1 for icons and control edges.

## Color

**Cool Head blue** is the color of what Cool Head does and offers: the recommended option, switches that are on, the selected tool, links, and focus rings. It's Cool Head's own, not the Mac's accent color, which differs on each Mac and which Chrome hides from extensions. A blue also keeps "do this" apart from the yellow, orange, and red that say "watch out".

| Use | Light | Dark |
|---|---|---|
| Blue for marks: links, switches, the selected tool, icons | `#1769D1` | `#4A9EFF` |
| Blue behind text: the recommended option, the Recommended pill | `#0F52AD` | `#0F52AD`, with a `#4A9EFF` edge (5.1:1 against the dark card) |
| Text on the blue behind text | white, 7.4:1 (AAA) | white, 7.4:1 (AAA) |
| Blue text on the panel | 4.9:1 on the light panel | 6.1:1 on `#1E1E1E` |

Text on blue is never dimmed: white at 80% on `#1769D1` measured 4.0:1, under the 4.5:1 text needs, and was harder to read. Text goes on the deeper blue instead, at full strength.

**At night** Cool Head stays blue and leaves warmth to the Mac's Night Shift, which warms the whole screen, Cool Head included. I considered an orange night mode and decided against it: orange already means "watch out" on the same cards, and white text on it measured 4.7:1, against the deep blue's 7.4:1.

**Status colors** say how the Mac is, and never mean "click here":

| Status | Color | Used for |
|---|---|---|
| All good | macOS green | the top row's wash, gauges, the menu bar badge |
| Worth watching | yellow `#FFBD00` | the same |
| Problem | macOS red | the same; "ends without saving" on options |
| Caution | macOS orange | warnings on cards, the network test's dashes |

Status colors always come with words or a shape (the Melting Snowflake icon works without color), never color alone. As text on the light panel they fall short of 4.5:1, so they're used for fills, washes, and marks, with the words in the text color.

**Neutrals** are macOS's own text colors, the panel's card and edge colors in `Ink` (Sources/CoolHeadApp/PanelView.swift), and the level's wash at 10% behind the top row and the tools bar.

## Type

The system font everywhere, so each feels native: SF Pro on the Mac (SwiftUI's defaults: body, callout, and caption), and in the extension the system stack `system-ui, -apple-system, "Segoe UI", Roboto, sans-serif`, which is SF Pro on a Mac, Segoe UI on Windows, and the desktop's own font on Linux. Monospaced only for Nerdy stuff. Sentence case for every title, button, and heading.

## Icons

- The app's icon: the menu bar's melting snowflake, in white on Cool Head blue, its drops and puddle a paler white so the flake leads (docs/images/logo.png, drawn by scripts/make-icon.swift). It replaced a smiling face with snowflakes in 0.17.0, so the app icon and the menu bar are one family.
- The menu bar, in two styles (docs/images/menu-icons.png): the Status badge, one melting snowflake with ice-blue drops and puddle, the same at every level, with a green circle, yellow triangle, or red octagon; and the Melting Snowflake, whole, melting, or in flames. The menu bar keeps the bolder ice-blue drops, which show better at its size than the app icon's pale ones.
- Inside the app: SF Symbols, in the text color or Cool Head blue. Two arrows in a circle mean Cool Head and its Chrome extension are working together, wherever that shows.

## Voice

- Plain words a person who isn't technical understands; US English; the Oxford comma; no em dashes; no exclamation marks.
- A card gives the verdict, a brief disclaimer, and the advice, and says what Cool Head thinks rather than leaving it to the reader.
- Every "why" ends in what it means for the person.
- Each option says what it does and what it costs before it's pressed.

## Accessibility

Text at least 4.5:1, icons and control edges at least 3:1, in light and dark; nothing by color alone; every control reachable by keyboard and named for VoiceOver; targets at least 24 by 24 points; no motion that matters when reduced motion is on.
