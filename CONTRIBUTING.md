# Contributing to Cool Head

Thanks for helping. There are three easy ways in.

## Report a process Cool Head got wrong, or couldn't explain

Most of the work on Cool Head starts with a report. [Open an issue](../../issues/new/choose) with:

- the Cool Head version and your macOS version,
- what you saw on the card, and what you think was really going on,
- what `coolhead why <name>` printed for that process. Read it over before posting: it shows command lines and folder names.

## Report a problem from the app

If a fix caused trouble, or Cool Head isn't working right, use **Report a problem** (the speech-bubble icon at the bottom of the panel, or right-click the menu bar icon). It shows you everything it would share, and opens a GitHub issue for you to submit.

## Share a case it couldn't explain

When a card says "Can't tell" or "looks stuck", **Share this case** shows you an anonymised report and opens it as a GitHub issue for you to submit. You see every word first. `coolhead case <name>` prints the same report in Terminal.

## Teach it a pattern

The [catalogue](Sources/CoolHeadCore/Catalogue.swift) is where Cool Head learns what processes are and when they are normal. Adding to it is the most useful contribution, and it needs no app-building knowledge. [docs/DIAGNOSIS.md](docs/DIAGNOSIS.md) explains how, step by step.

## Send code

1. Read [BUILDING.md](BUILDING.md) and get a build running.
2. Make your change on a branch and open a pull request. Say what it fixes and how you tested it.
3. `coolhead selftest` must pass; the CI runs it on every pull request.
4. The first time, the CLA bot asks you to sign the [Contributor License Agreement](CLA.md) by leaving a comment. You only do this once. It lets the project offer Cool Head under both licenses (see [COMMERCIAL.md](COMMERCIAL.md)); you keep your copyright.

### How changes reach main

- Every change arrives as a pull request and is merged by squashing, so main reads as one commit per change.
- The CI must pass (`build`: the build, `coolhead selftest`, and packaging the app), and the maintainer reviews and approves.
- main can't be force-pushed or deleted. The rules are in [`.github/rulesets/protect-main.json`](.github/rulesets/protect-main.json), and `scripts/apply-repo-settings.sh` applies them along with the repository's other settings.

### Changelog and releases

If your change is something a user would notice, add a line for it under **[Unreleased]** in [CHANGELOG.md](CHANGELOG.md), in plain words, under Added, Changed or Fixed. Releases are made by the maintainer; how versions are numbered and every step of a release are in [RELEASING.md](RELEASING.md).

### How the code is meant to work

- **One short sentence, then the options.** A card says what something is and whether it is fine, in one short sentence a child could follow. Everything else (how we know, the options and what each would cause) goes behind Explore fixes, never on the card.
- **Big is not broken.** Never suggest stopping a job just because it is big or long. Stopping is for stalled jobs, and the card must say what it would cost.
- **Say "can't tell" when you can't.** A plain admission beats a guess.
- **Everything stays on the Mac.** No network calls, no analytics. The only exception is Look it up, which the user presses, and which sends the process name only.
- **Light on the Mac.** Keep Cool Head's own CPU use under 0.5% of the Mac on average; check it in Activity Monitor.
- **No administrator password.** Everything Cool Head reads is readable by the signed-in user.
- **License-clean dependencies.** MIT, BSD, Apache-2.0 and similar only. No GPL, AGPL or LGPL code linked into what ships, because it would stop Cool Head from being offered under a commercial license. The project has no dependencies today.
- **Comments explain why**, especially for kernel calls (`proc_pidinfo`, `proc_pid_rusage`) and IOKit keys.

## Security problems

See [SECURITY.md](SECURITY.md). Please don't open a public issue for those.
