# How every card is written

Every card fills the same slots, and the code writes the sentences from them (Sources/CoolHeadCore/CardTemplate.swift). The selftest's card-template check fails any sample card that isn't written this way. This page is the rulebook; docs/BRAND.md has the short version.

## Who it's for

A card should read right the first time for someone who isn't technical, and for someone who learned English as a second language. So the English is simple and literal:

- The present tense for now ("is working hard"), and "still … after" for something still going on ("Site is still busy after 3 hours."). The past is only for an event that is over ("Model made its last progress at 1:39pm."). Never "has been" or "has used": learners often misread the present perfect, and ASD-STE100, the simplified English that aircraft manuals use, leaves it out.
- No contractions ("is not", never "isn't"), no idioms ("Wait a few minutes", not "Give it a minute"), and no two-word verbs ("Search the web", not "Look it up"; "open again", not "come back"), except the ones macOS uses itself: Turn on, Turn off, Shut down, Back up, and plugged in.
- No "we": it's unclear who it means on a card. Cool Head names itself.
- Full sentences of at most 25 words. An explanation has at most 3: where a card has more to say (a memory card with several notes, an extra, a rule line), the first piece of evidence and the first effect stay, the rest fill in while they fit, and what doesn't fit moves to Nerdy stuff.
- Plain words before technical ones. A card says "is working hard"; the figure, in cores, is in Nerdy stuff.

## The slots

- **Headline:** subject, reading, verdict. "A Google Chrome tab is still working hard after 1 hour. This is more than usual." A memory card leads with its verdict, since it's about the whole Mac: "Apps and programs are using almost all of your Mac's memory. Google Chrome uses the most, 5.1 GB."
- **Explanation:** how Cool Head knows, then what it means for you. Nothing from the headline is said again. Where Cool Head knows nothing more, there's no explanation: a card says what Cool Head knows, so where it says nothing, it doesn't know.
- **Each option:** a title that starts with one specific verb ("Quit Slack instead to free 1.1 GB"). Then a consequence that starts with "This" (what it does), then what you lose, then "You can undo this." where Cool Head can.

## Verdicts

One sentence each, from a closed list; no card writes its own. A card whose reading is a single event (a crash restart, a port that dropped a device) has none.

| Verdict | Means |
|---|---|
| This is normal. | expected; nothing to do |
| This is normal after an update. | expected work after a macOS update |
| This is normal wear. | a battery or drive wearing as expected |
| This is longer than usual. | expected work, running past its usual length |
| This is more than usual. | more than this kind of thing normally uses or does |
| It is not busy now. | it was busy, and isn't now |
| Wait a few minutes. | it just started; Cool Head checks again |
| It will finish at about 2:30pm. | a forecast from its own progress |
| It is almost done. | its own estimate has passed |
| It is probably stuck. | no progress for a while, from what Cool Head sees |
| It is stuck. | shown directly |
| It is not responding. | macOS marks it Not Responding |
| It waits for you. | you paused it, and it waits for you to continue it |
| It still adds heat. | limited or slowed, and still making heat |
| Let it cool. | a battery or drive is warm or hot |
| Apps and programs are using almost all of your Mac's memory. | the Mac moves data from memory to storage ("all of" when macOS says critical) |
| It probably leaks memory. | it grew with the same windows open |
| It probably forgot to stop. | it keeps the Mac awake while it does almost nothing |
| It may fail. | a drive that reports errors or a fault |
| It needs a repair. | a battery that macOS or its controller says needs one |
| The battery drains even when it is plugged in. | the charger gives less than the Mac uses |
| It is probably harmful. | a program pretending to be macOS's or Apple's |

The memory verdict says what apps and programs are doing, not what the Mac lacks: the fix is to close something, and a Mac's memory can't be added to.

## How sure

Four words, each with one meaning: none for a fact (macOS, the program, or a measurement says so); "probably" for Cool Head's best explanation, with the evidence beside it; "may" for something that can happen (an option's outcome, or a risk); and "usually" for what's normal for this kind of thing. Not "likely", "seems", "looks", "might", or "could": people read words like these as very different odds (Budescu and Wallsten), so the list is short and each word means one thing.

## One word for each idea

| Idea | Word | Not |
|---|---|---|
| Something that runs | app (has an icon you open and quit), program (anything else), part of macOS (Apple's own) | process, helper, service |
| How hard | working hard, busy; the figure, in cores, is in Nerdy stuff | power (that's electric: battery, charger) |
| Heat | adds heat; warm and hot for the Mac, the battery, and the drive, each by its own line | |
| Stuck | stuck (no progress), not responding (macOS's mark), paused, waits for | stalled, frozen, hung |
| Memory | memory (where apps and programs work), full | tight, low on memory |
| Files | storage (where files are kept); "drive" for the part itself | disk space |
| What you lose | Nothing is lost. / Unsaved work is lost. / You may lose up to 2 hours of its work. / You may lose the work it did. / It asks you to save your work first. | |
| Undo | You can undo this. | Undo any time |
| Actions | Quit (an app), Force quit, Stop (a program or job), Pause and Continue, Close (a tab), Restart, Unload, Turn on and Turn off, Open, Find, Search the web, Send this case | end, kill, Resume, Look it up, Share this case |

## Terms footer

A word a reader may mix up is defined once, in one visible line with ⓘ under the cards that use it, never on a card. So far there's one: memory and storage ("Memory is where apps and programs work. Storage is where your files are kept."), brought up by either word. A term joins the list only when a card uses it and a reader is likely to confuse it.

## What the selftest checks

On every sample card, on every catalogue entry (calm and running long), and on varied inputs the samples miss (hangs with programs waiting on them, a memory card with every note, an extra, a rule line, and the CPU limit added to a card): written from the template, with the template's headline; no contraction (straight or curly apostrophe), present perfect, idiom, two-word verb, replaced word or action, "we", or banned time word ("since", "for the last"), in any case, in the headline, the explanation, option titles and consequences, and steps, with names left out; no sentence over 25 words, and no explanation over 3 sentences; every option's consequence starting with "This" or a fixed phrase; no sentence of an explanation starting with "This"; and no definition on a card. Not checked: that a card with no verdict is about a single event. The terms-footer check covers which cards bring up the footer, and that it shows once however many cards do.

## Where this comes from

Apple's Human Interface Guidelines (Writing; Alerts), Microsoft's Writing Style Guide (writing tips for a global audience; contractions) and its Windows guidelines for error messages and UI text, Google's developer style guide (writing for a global audience; tense; pronouns), GOV.UK's writing guidelines and A to Z, Nielsen Norman Group (error messages; the first 2 words of a line; numerals; consistency and standards), ASD-STE100 Simplified Technical English, research on how learners read the present perfect, and Budescu and Wallsten's work on words for likelihood. Two readings of every sample card by a reviewer working at an average adult American reading level shaped the last changes.
