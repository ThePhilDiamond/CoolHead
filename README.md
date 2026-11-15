# Cool Head

A free, open-source Mac menu bar app that tells you, in one sentence, why your Mac is hot, busy or draining its battery, and what to do about it.

Activity Monitor shows numbers. Cool Head reads what a busy process is actually doing (its command, what started it, the files it writes, the progress it reports) and gives a verdict:

> **Your photo library export is 97% done. Done around 4:50pm.**
> Let it finish
> Stopping it now would lose about 3 hours of work.

It keeps a cool head: a big job is not a problem just because it is big. Stopping is only suggested when a job has stalled, and every card says what stopping would cost.

Everything runs on your Mac. Nothing is sent anywhere.

## Status

Early. The command-line tool works; the menu bar app is not built yet. See [DESIGN.md](DESIGN.md) for where it is going.

## Try the command-line tool

Needs macOS 14 or later and the Xcode Command Line Tools (`xcode-select --install`).

```bash
swift build -c release
```

```bash
.build/release/coolhead now
```

```bash
.build/release/coolhead why <pid or name>
```

`now` shows the Mac's heat, power, battery and memory, and a card for each busy process. `why` shows one process's card and the evidence behind it.

## License

MIT. See [LICENSE](LICENSE).
