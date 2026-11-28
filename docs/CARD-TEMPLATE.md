# How every card is written

Every card fills the same slots, and the code writes the sentences from them (Sources/CoolHeadCore/CardTemplate.swift). The selftest's card-template check fails any sample card that isn't written this way. This page is the rulebook; docs/BRAND.md has the short version.

## Who it's for

A card should read right the first time for someone who isn't technical, and for someone who learned English as a second language. So the English is simple and literal:

- The present tense for now ("is working hard"), and "still … after" for something still going on ("Site is still busy after 3 hours."). The past is only for an event that is over ("Model made its last progress at 1:39pm."). Never "has been" or "has used": learners often misread the present perfect, and ASD-STE100, the simplified English that aircraft manuals use, leaves it out.
- No negative or conditional contractions ("is not", never "isn't"; see Contractions), no idioms ("Wait a few minutes", not "Give it a minute"), and no two-word verbs ("Search the web", not "Look it up"; "open again", not "come back"), except the ones macOS uses itself: Turn on, Turn off, Shut down, Back up, and plugged in.
- No "over" with an amount or a time: "moved over 256 MB" reads as "moved across" or "moved more than". An amount takes "more than" ("more than 256 MB"), a time takes "in" or "during" ("in the last 2 minutes").
- No "we": it's unclear who it means on a card. Cool Head names itself.
- Full sentences of at most 25 words. An explanation has at most 3: where a card has more to say (a memory card with several notes, an extra, a rule line), the first piece of evidence and the first effect stay, the rest fill in while they fit, and what doesn't fit moves to Nerdy stuff.
- Plain words before technical ones. A card says "is working hard"; the figure, in cores, is in Nerdy stuff.

## Contractions

GOV.UK's rule (style guide, A to Z, "contractions"), everywhere Cool Head writes: on cards, in Nerdy stuff, in the panel and Settings, and in the `coolhead` tool.

- A positive contraction is fine: it's, you're, you'll, that's, there's, I'm.
- A negative one is spelled out: "cannot", "do not", "is not", "will not", never can't, don't, isn't, or won't. Many readers find them harder to read, or misread them as the opposite of what they say.
- So is a conditional one, and any "'d": "should have", "would have", "it would", never should've, would've, or it'd.
- "'s" means only "is", never "has": "it's busy", but "it has been busy", never "it's been busy". On a card that is the present perfect, which is left out anyway.
- "Let's" is "let us", and a card does not say "we".
- Where a step quotes another app's own button or menu name exactly, it keeps that app's words, contraction and all. None does today; each one is listed by its whole text in `Fixture.contractionExceptions` (Sources/CoolHeadCore/Fixtures+Contractions.swift).

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

## Options

- **Groups.** One click, which Cool Head does for you, then Do it yourself, where Cool Head takes you to the right place or shows the steps. The recommended option sits first inside its group's box and always shows; the rest fold under it, with how many. The group holding the recommendation comes first.
- **Tags.** Every option has one tag for what it does about the problem, from a closed list: Fixes the cause, Helps, Helps later (setting up Cool Head for Chrome, which helps the next time), and Tells you more. They're in the text color, since the status colors never mean "click here". Caution, white on red, marks what Cool Head does that has consequences that can't be undone or known. The tags sit top right where they fit beside a name on one line; otherwise they take their own line under the name, so a name is never squeezed.
- **The recommendation.** One at most, shown in blue: a filled deep blue tile for one click, a blue dashed outline for a task; the other one-click options are a pale blue, so none looks switched off. There's no "Recommended" label; a line under a thin rule says it in words, from the options' facts: "Cool Head recommends this because it helps in one click." or "... because it is the only option that fixes the cause." Each reason holds against every other option that does as much: "in one click" where all of those are tasks, and never on a Caution option, which asks twice; "without closing anything" only for what Cool Head does, where all of those close something (a task may be closing tabs your own way). Where the facts give none (the card's own reason, or the only option that acts), the line is "Cool Head recommends this."
- **One click first.** Where a card's own pick is a task or only tells you more, an option Cool Head does in one click that helps, and isn't Caution, is recommended instead: one that closes nothing first, then the one that does most. Where the card can't tell what it's doing, an option that closes it isn't put forward, by this rule or as the next one: quitting may end work Cool Head can't see, such as a render, so its cost isn't known; it stays offered. A card that recommends nothing (a job working normally) still recommends nothing.
- **Quit beside Restart.** Where a card offers to restart an app and to quit it, the quit says when it's the one to use, in the fixed "Use this only if" form: "Use this only if you are no longer using it. This closes all its tabs." Otherwise both read as the same choice.
- **Done, then next.** After an option works, its note says what was done, and about 4 seconds later the option goes, since it can't be done again; the note stays above the options. Then the next is recommended: the card's own pick where one click had taken its place, one click or a task, since the easy way has been tried; otherwise the first option left that acts, isn't Caution, and isn't held back (a Sleep tabs option with no tab to sleep, say). Another option done leaves the recommendation where it is. An option whose answer comes later (Cool Head for Chrome, a restart) goes only once the answer says it worked; a failure stays where it is, and an option that only shows steps never goes. Done means that option on that target: an id a card reuses for another app (Quit Slack, then Quit Xcode) isn't taken as done.

## Nerdy stuff

Every card's Nerdy stuff is written from the same five slots, in this order, by its own family (Sources/CoolHeadCore/NerdyStuff.swift); a slot with nothing to say is left out:

1. **What Cool Head saw.** Each reading the card rests on: its exact figure, the macOS source it came from by its technical name (`proc_pid_rusage`, `pmset -g assertions`, `NVMe SMART log`, from a closed list), when it was read, and, where there is one, a Terminal command that shows the same figure. Sentences the card template moved out of an explanation come first. Then what else was busy, or using memory, or energy.
2. **Why this verdict.** The rule that made the card, with its thresholds ("0.5 cores or more for 60 seconds before a card shows"), the catalogue's usual time and its source, and which kind of card won, with its score.
3. **Why this option.** Every option's facts: one click or a task, its tag, Caution, and whether it closes something; the recommended one with why.
4. **What it is.** The process, app, or part: its name and PID, path, command (secrets hidden), what started it, when, and its folder.
5. **What Cool Head did.** This card's lines from Cool Head's log, newest first, at most five. The log is kept in memory only, so it starts empty after Cool Head restarts.

A list shows its first five, then one line for the rest ("and 13 more, 24% in total"). Copying copies the card's lines with the Mac first (model, cores, macOS, memory, uptime, startup disk, heat), which is what a helper asks first; the energy week's copy has every row. Technical terms are fine here, each said the same way every time; the word list's clarity rules still hold (no negative or conditional contraction, "'s" for "has", present perfect, "we", or "over" with an amount or a time).

## Verbose mode

A setting for power users, off to start (Settings, Look). With it on, a card's explanation is replaced by its key readings from Nerdy stuff, a short table of names and figures: each reading in What Cool Head saw, by its figure alone (CPU as "1.20 cores (120% in Activity Monitor)", without how it was averaged), readings with one name sharing a row (every file it writes); the first three rows of the first list; what it is; and the rule behind the verdict, named Rule on every card. A reading with a figure shows it in the headline too ("is still using about 1.5 cores after 1 hour"); a reading without one reads as before. Sources, Terminal checks, whole lists, and the log stay in Nerdy stuff, folded as usual. The terms footer is not shown, since a power user knows the words. A card with no key readings shows its whole explanation, with nothing moved to Nerdy stuff.

## Terms footer

A word a reader may mix up is defined once, in one visible line with ⓘ under the cards that use it, never on a card. So far there's one: memory and storage ("Memory is where apps and programs work. Storage is where your files are kept."), brought up by either word. A term joins the list only when a card uses it and a reader is likely to confuse it.

## What the selftest checks

On every sample card, on every catalogue entry (calm and running long), and on varied inputs the samples miss (hangs with programs waiting on them, a memory card with every note, an extra, a rule line, and the CPU limit added to a card): written from the template, with the template's headline; no negative or conditional contraction or "'s" for "has" (straight or curly apostrophe; see Contractions), present perfect, idiom, two-word verb, replaced word or action, "we", "over" with an amount or a time, or banned time word ("since", "for the last"), in any case, in the headline, the explanation, option titles and consequences, and steps, with names left out; no sentence of more than 25 words, and no explanation of more than 3 sentences; every option's consequence starting with "This" or a fixed phrase; no sentence of an explanation starting with "This"; and no definition on a card. Not checked: that a card with no verdict is about a single event. The terms-footer check covers which cards bring up the footer, and that it shows once however many cards do. The option-cues check covers every option's tag being on the list, every recommendation having its line, and each line's reason being true of the option's facts, read back from the sentence; option-done-then-next covers the next recommendation on every sample card, after the recommended option is done, after another one is, and after two in turn; option-labels covers one click first; quit-beside-restart covers the quit's words on every card with a restart of the same app, and their absence everywhere else. The rules that hold beyond the cards (no negative or conditional contraction, "'s" for "has", present perfect, "we", or "over" with an amount or a time) also run on every line of Nerdy stuff, Cool Head's log lines included, where technical words are fine. The contractions checks cover the rule itself on made-up sentences, on a card and in Nerdy stuff (what it spells out is caught; positive contractions, full forms, and possessives are not); every string in Sources/, comments left out, read from the source folder the copy was built from (a pass with a note where that folder is not on the Mac), outside the listed exceptions; and the reader of strings, on made-up source with every kind of comment, a regex literal, raw, multi-line, and interpolated strings, and an exception. The verbose-mode check covers every family's made-up card carrying its slots, busy cards made by the watcher's own code, each reading among the key readings by its figure (CPU by its figure alone), readings with one name in one row, the first list's first three rows and no more, what it is, and the rule present, no two rows sharing a name, no source tag or Terminal check on the card, the clarity rules, and every sample headline whose reading has a figure showing it, while the others read as before. The nerdy-stuff check covers every busy sample and every other family's cards as the app makes them (memory, power, hardware, crash loops, browsers) and the energy week: headings in order, every reading naming a source from the list, lists cut at five with the rest, and those clarity rules.

## Where this comes from

Apple's Human Interface Guidelines (Writing; Alerts), Microsoft's Writing Style Guide (writing tips for a global audience; contractions) and its Windows guidelines for error messages and UI text, Google's developer style guide (writing for a global audience; tense; pronouns), GOV.UK's writing guidelines and A to Z, Nielsen Norman Group (error messages; the first 2 words of a line; numerals; consistency and standards), ASD-STE100 Simplified Technical English, research on how learners read the present perfect, and Budescu and Wallsten's work on words for likelihood. Two readings of every sample card by a reviewer working at an average adult American reading level shaped the last changes.
