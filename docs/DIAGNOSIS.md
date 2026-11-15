# How Cool Head works out the cause

Cool Head answers one question about anything keeping your Mac hot, busy or awake: **is this fine, and if not, what should I do?** It answers in one sentence and one action, and it says what acting would cost.

It never treats a big job as a problem just because it is big. Stopping something is only suggested when there is evidence it has stalled.

## The method

Every card comes from the same steps.

1. **Symptom.** What you would notice: the Mac is hot, the battery drains, it is slow, memory is tight, or it won't sleep.
2. **Suspects.** What contributes most to that symptom: for heat and battery, the processes using the most CPU for at least a minute; for memory, the largest; for sleep, whatever is holding the Mac awake.
3. **Identify.** For each suspect, the facts a person would otherwise have to look up: its full command, the chain of parents up to the app or shell that started it, its working folder, the files it is writing, any lock files it holds, and how long it has been running.
4. **State.** Whether it is doing its job:
   - **working**: it reports progress that is still advancing, or it is still writing output;
   - **waiting**: it is queued behind another job, usually on a lock;
   - **stalled**: it has reported no progress for longer than 30 minutes and longer than three of its own usual gaps between progress lines;
   - **can't tell**: it has been busy for a long time with no sign either way.
5. **Match.** It is looked up in the [catalogue](../Sources/CoolHeadCore/Catalogue.swift) of known patterns: what it is, when it is normal, how long is normal, and the risk of stopping it.
6. **Card.** One sentence: what it is and whether that is fine. One action. If acting would cost something, one line saying what.
7. **Afterwards.** Whether the action helped. *(Planned: power and heat before and after.)*

Where these steps cannot reach an answer, the card says so plainly ("Can't tell whether it is working or stuck") and offers **Look it up**, a web search for the process name only. Cards that can't reach an answer, or that look stuck, also offer **Share this case**: an anonymised report of what Cool Head saw, shown in full first, which you can open as a GitHub issue. Shared cases are reviewed and become catalogue entries through pull requests; nothing reaches the catalogue automatically, and the catalogue only changes with app releases.

## What each state allows

| State | Card says | Action offered | Stopping |
| --- | --- | --- | --- |
| working | how far along, and when it should finish | Let it finish (and Run it cooler, when the Mac is warm) | not offered; the card says how much work stopping would lose |
| waiting | what it is waiting for | Nothing to do | not offered |
| stalled | no progress since when | Stop it | offered, with what it would lose (nothing since its last progress) |
| can't tell | how long it has been busy | Look it up | not offered; the card warns against stopping it unknown |

## The catalogue

Each entry in [`Catalogue.swift`](../Sources/CoolHeadCore/Catalogue.swift) has:

- **what it matches**: process names, or part of a path;
- **what it is doing**, as the start of a sentence;
- **when it is normal**, and **how long is usual**;
- **whether it ends on its own** (a virtual machine doesn't);
- **what to do** when it has gone on longer than usual, and **the risk** of doing it;
- **a source**: an Apple support article, a man page, or a test anyone can repeat;
- **checked**: set once someone has confirmed the source says what the entry says.

## Adding a pattern

1. Add the entry to `Catalogue.swift`. Keep the sentence plain: what it is, in words a non-programmer would use.
2. Add a recorded example to [`Fixtures.swift`](../Sources/CoolHeadCore/Fixtures.swift) with the card it should produce.
3. Run `swift build -c release && .build/release/coolhead selftest`. Every example must pass.
4. In the pull request, link the source and say how you checked it.

If you have seen a process misbehave and don't know why, [open a "pattern" issue](../../../issues/new?template=pattern.yml) with what `coolhead why <name>` printed. Read it first: it shows command lines and folder names.
