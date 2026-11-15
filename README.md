<p align="center"><img src="docs/images/logo.png" width="128" alt="Cool Head logo: a smiling face with snowflakes behind it"></p>

<h1 align="center">Cool Head</h1>

<p align="center"><em>Let cooler heads prevail.</em><br>Why is my Mac running hot or slow? What's happening, gathered from across your Mac into one place, with clear options to act in one click.<br>A free, open-source menu bar app for macOS.</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/panel-dark.png">
    <img src="docs/images/panel-light.png" width="400" alt="The Cool Head panel: a card saying a photo export job is 16% done and should finish around 1:14am, with its fixes open: do nothing and check back (recommended), run it cooler, or stop it, each with what it would cause">
  </picture>
</p>

## What it is

Activity Monitor shows numbers. Cool Head reads what a busy process is actually doing (its command, what started it, the files it writes, the progress it reports) and tells you, in one short sentence, whether that's fine:

> **Photo Export is 16% done. Ready around 1:14am.**

> **Spotlight is indexing your files. That's normal.**

> **Video Render hasn't moved since 9:46pm. It looks stuck.**

> **Memory is tight. Google Chrome is using the most (3.7 GB).**

A card that needs watching has **Explore fixes**; a calm one has **Learn more**. Each option says, in a few words, what it would do, and one is recommended: wait, run it cooler, stop it, quit an app, close a browser's heaviest tabs, or look it up. Anything you slow down stays pinned at the top, frozen, until it finishes or you set it back.

It keeps a cool head: a big job isn't a problem just because it's big. Stopping is recommended only when a job has stalled. When Cool Head can't tell, it says so.

## Privacy

Everything runs on your Mac. No account, no analytics, and nothing stored about what happened. The only thing it remembers is your own choice: apps and jobs you mark Always trust, kept on this Mac and listed in the right-click menu. The only automatic network use is a daily check with GitHub for a newer version of Cool Head (turn it off from the right-click menu; see [docs/UPDATES.md](docs/UPDATES.md)). Three buttons reach outside, and only when you press them:

- **Look it up** opens a web search for the process name.
- **Share this case**, on cards Cool Head can't explain, shows you an anonymised report of that process.
- **Report a problem**, at the bottom of the panel and in the right-click menu, is for when a fix caused trouble or Cool Head isn't working: your own words plus Cool Head's activity from the last 6 hours (which cards appeared, which buttons were pressed, what happened), kept in memory only and anonymised the same way.

Reports never hold file names, paths or project names. You see every word first; then **Open in GitHub** opens it as an issue for you to submit (posted under your GitHub account, only if you press Submit), or **Copy** keeps it on your Mac to send however you like. Details: [SECURITY.md](SECURITY.md).

## System requirements

macOS 14 Sonoma or later, on Apple Silicon or Intel.

## Quick start

1. Download the latest `Cool-Head-….zip` from [Releases](../../releases), and unzip it.
2. Move **Cool Head** to Applications and open it. The first time, macOS may say it can't check the app (it isn't notarized yet): open **System Settings ▸ Privacy & Security** and choose **Open Anyway**.
3. Look for the snowflake in the menu bar. Its badge shows the state by shape and colour: a green circle when all is good, a yellow triangle when something is worth watching, a red octagon for a problem. Prefer something sillier? Right-click it and choose **Menu Bar Icon ▸ Melting Snowflake**: it melts into a puddle as things heat up. Click the snowflake for the panel; right-click for updates, reporting a problem, and Quit.

After that, Cool Head keeps itself up to date: when a new version is out, the panel offers to install it, and checks the download is genuine first.

Or build it yourself: see [BUILDING.md](BUILDING.md).

## How it decides

[docs/DIAGNOSIS.md](docs/DIAGNOSIS.md) explains the method: symptom, suspects, identify, state, match, card. The [catalogue](Sources/CoolHeadCore/Catalogue.swift) holds what Cool Head knows about common macOS processes, each with its source, and `coolhead selftest` checks every recorded example still gives the right card.

## Command line

The app includes `coolhead`, for Terminal and for scripts:

```bash
coolhead now
```

```bash
coolhead why <pid or name>
```

## Contributing

The most useful help is teaching Cool Head a pattern it doesn't know, or reporting a card it got wrong. See [CONTRIBUTING.md](CONTRIBUTING.md). Everyone whose work is in the project is listed in [CONTRIBUTORS.md](CONTRIBUTORS.md).

## License

Free and open source under the [GNU AGPL v3.0](LICENSE), with a commercial license for closed-source use: see [COMMERCIAL.md](COMMERCIAL.md). The name and logo are covered separately: see [TRADEMARKS.md](TRADEMARKS.md).
