# Contributing to Cool Head

Thanks for helping. There are three easy ways in.

## Report a process Cool Head got wrong, or couldn't explain

Most of the work on Cool Head starts with a report. [Open an issue](../../issues/new/choose) with:

- the Cool Head version and your macOS version,
- what you saw on the card, and what you think was really going on,
- what `coolhead why <name or PID>` printed for that process, with the process's name or PID from Activity Monitor in place of `<name or PID>` (for example `coolhead why mds_stores`). [Command line](README.md#command-line) in the README shows how to run it, step by step. Read what it prints before posting: it shows command lines and folder names.

## Report a problem from the app

If a fix caused trouble, or Cool Head isn't working right, use **Report a problem** (Report, among the tools along the bottom of the panel). It shows you everything it would share, and opens a GitHub issue for you to submit.

## Share a case it couldn't explain

When a card says "Can't tell" or "looks stuck", **Share this case** shows you an anonymised report and opens it as a GitHub issue for you to submit. You see every word first. `coolhead case <name or PID>` prints the same report in Terminal (see [Command line](README.md#command-line) for how to run it).

## Teach it a pattern

The [catalogue](Sources/CoolHeadCore/Catalogue.swift) is where Cool Head learns what processes are and when they are normal. Adding to it is the most useful contribution, and it needs no app-building knowledge. [docs/DIAGNOSIS.md](docs/DIAGNOSIS.md) explains how, step by step. Write each entry in your own words and link its source rather than copying from it: Apple's support articles and other people's documentation are under their own copyright.

## Send code

1. Read [BUILDING.md](BUILDING.md) and get a build running.
2. Make your change on a branch and open a pull request. Say what it fixes and how you tested it.
3. `coolhead selftest` must pass; the CI runs it on every pull request. One of its checks compares every sample card's winner and options with `Sources/CoolHeadCore/GoldenRanking.swift`: if your change means a sample should get a different card or option, run `coolhead ranking --write` and commit the file, so the change shows in your pull request's diff.
4. The first time, the CLA bot asks you to sign the [Contributor License Agreement](CLA.md) by leaving a comment with the sentence it gives. You do this once for each version of the agreement, not on every pull request. It lets the project offer Cool Head under both licenses (see [COMMERCIAL.md](COMMERCIAL.md)); you keep your copyright, and what's published under the AGPL stays under the AGPL.
   - Everyone whose work is in the pull request signs for themselves, including every person named in a `Co-authored-by` line. Nobody signs for someone else.
   - Opening a pull request, or ticking a box in its description, isn't signing; only the bot's sentence is.
   - If you'd rather not sign, open an issue that describes the change instead.

### Using AI tools

You can use AI tools to help with a contribution. You're responsible for it as if you'd typed it: read and test every line, and make sure you have the right to submit it, as the [CLA](CLA.md) asks. An AI tool can't sign the CLA, so name it in an `Assisted-by:` line at the end of the commit message, not as a co-author, for example `Assisted-by: Claude Code:claude-opus-5-5`. Cool Head's own commits follow the same rule; commits made before this rule name the tool in a `Co-Authored-By:` line instead, and it records the same thing.

### How changes reach main

- Every change arrives as a pull request and is merged by squashing, so main reads as one commit per change.
- **Start every branch from main**, never from another pull request's branch. Squash merging gives main a new commit for each pull request, so a branch built on another one conflicts as soon as that one merges.
- **Write where no one else is writing**, so pull requests made at the same time don't conflict: a changelog entry is its own file in `changes/` (below); a feature's selftest checks and sample cards go in their own file, named for the feature (`Sources/CoolHeadCore/Fixtures+CrashLoops.swift` for the crash-loop card, declaring `crashLoopsChecks` and `crashLoopsSamples`), and the build lists every such file itself (`Plugins/Lists`), as it does every card source (`Sources/CoolHeadApp/<Name>Cards.swift`, declaring `<Name>Watch`) and every card about a busy process (`Sources/CoolHeadCore/Cards/<Name>Card.swift`, declaring `<Name>Card`; see docs/DIAGNOSIS.md, "How a card is chosen"); and lists that grow (option kinds, SECURITY.md's points) have one item per line. Two pull requests that must edit the same lines are made one after the other.
- The CI must pass (`build`: the build, `coolhead selftest`, and packaging the app), and the maintainer reviews and approves.
- main can't be force-pushed or deleted. The rules are in [`.github/rulesets/protect-main.json`](.github/rulesets/protect-main.json), and `scripts/apply-repo-settings.sh` applies them along with the repository's other settings.

### Changelog and releases

If your change is something a user would notice, add one file for it in [changes/](changes/README.md): `changes/added/`, `changes/changed/` or `changes/fixed/`, named in a few words joined by hyphens, holding one line in plain words that starts `- `. Don't edit CHANGELOG.md itself; the release gathers these files into it. Releases are made by the maintainer; how versions are numbered and every step of a release are in [RELEASING.md](RELEASING.md).

### Writing the docs

Write for someone who has never opened Terminal. Every step names where it happens and what to press ("Open Terminal: it's in Applications ▸ Utilities"). A placeholder in angle brackets, such as `<name or PID>`, is explained where it's used: what to type in its place, where to find it, and an example with a real value (`coolhead why mds_stores`). A command for `coolhead` links to [Command line](README.md#command-line) in the README the first time a page uses it, since the tool needs its full path until it's set up.

### How the code is meant to work

- **One short sentence, then the options.** A card says what something is and whether it is fine, in one short sentence a child could follow. Everything else (how we know, the options and what each would cause) goes behind Explore fixes, never on the card.
- **Every sentence is written by hand.** No model rewords anything, so what you write is what people read. Write each sentence whole: say a fact once, start sentences with a capital (a name like "a script" can start one), give every step a verb ("Choose Window ▸ Task Manager"), and join several facts about one thing into one sentence ("It's adding to the heat and draining your battery") rather than a string of short ones. `coolhead wording` prints every card from the recorded examples, so you can read them all in one place before and after a change.
- **Big is not broken.** Never suggest stopping a job just because it is big or long. Stopping is for stalled jobs, and the card must say what it would cost.
- **Say "can't tell" when you can't.** A plain admission beats a guess.
- **Everything stays on the Mac.** No network calls, no analytics. The exceptions are ones the user presses: Look it up, which sends the process name only, and Test my network's Start test, which runs Apple's network test against Apple's servers.
- **Light on the Mac.** Keep Cool Head's own CPU use under 0.5% of the Mac on average; check it in Activity Monitor.
- **No administrator password.** Everything Cool Head reads is readable by the signed-in user.
- **License-clean dependencies.** MIT, BSD, Apache-2.0 and similar only. No GPL, AGPL or LGPL code linked into what ships, because it would stop Cool Head from being offered under a commercial license. The project has no dependencies today. Anything taken from another project, even a list or an approach, is credited in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) with its license.
- **Comments explain why**, especially for kernel calls (`proc_pidinfo`, `proc_pid_rusage`) and IOKit keys.

## Security problems

See [SECURITY.md](SECURITY.md). Please don't open a public issue for those.
