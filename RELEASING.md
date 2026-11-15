# Releasing Cool Head

How versions are numbered, what each release contains, and the steps to make one. Anyone can follow along; only the maintainer publishes.

## Version numbers

Cool Head follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html): **MAJOR.MINOR.PATCH**, for example 0.5.0.

- **PATCH** (0.5.0 to 0.5.1): fixes only. Nothing new to learn.
- **MINOR** (0.5.0 to 0.6.0): anything new a user would notice, such as a new option, card or setting, with or without fixes.
- **MAJOR** (0.x to 1.0): saved for when Cool Head is notarized and its behaviour is settled. While the major number is 0, anything may still change.

One number names a version everywhere:

| Where | Looks like |
|---|---|
| `VERSION` file, and `CoolHead.version` in `Sources/CoolHeadCore/CaseReport.swift` | `0.5.0` |
| The app (top right of the panel, About window) | `Cool Head v0.5.0`, `Version 0.5.0` |
| Git tag | `v0.5.0` |
| GitHub release title | `Cool Head 0.5.0` |
| CHANGELOG.md heading | `## [0.5.0] - 2026-11-15` |
| Downloads | `Cool-Head-v0.5.0.zip`, `Cool-Head-v0.5.0.zip.sig`, `SHA256SUMS.txt` |

`scripts/check-version.sh` checks they agree. CI runs it on every change, and the release workflow runs it with the tag, so a release with mismatched numbers stops before anything is published.

## What a release contains

- **`Cool-Head-vX.Y.Z.zip`**: the app, built by GitHub from the tagged code, ad-hoc signed (not yet notarized).
- **`Cool-Head-vX.Y.Z.zip.sig`**: an Ed25519 signature of the zip. The in-app updater installs an update only if this checks out against the key built into the app (see [docs/UPDATES.md](docs/UPDATES.md)).
- **`SHA256SUMS.txt`**: the zip's checksum, to check a download by hand.
- **Notes**: copied from the version's section of [CHANGELOG.md](CHANGELOG.md), word for word.

## Steps

1. **During development**, each change a user would notice gets a line under `## [Unreleased]` in CHANGELOG.md, under Added, Changed or Fixed.
2. **Choose the number** by the rules above: MINOR if anything under Unreleased is Added or Changed, PATCH if it's all Fixed.
3. **Prepare the release** in one commit named `Release X.Y.Z`:
   - In CHANGELOG.md, rename `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD`, add a new empty `## [Unreleased]` above it, and update the links at the bottom (`[Unreleased]` compares `vX.Y.Z...HEAD`; `[X.Y.Z]` compares the previous tag with `vX.Y.Z`).
   - Set `VERSION` and `CoolHead.version` to X.Y.Z.
   - If the version changes something a user sees, add its short note for the app's What's new (`WhatsNew` in `Sources/CoolHeadApp/PanelView.swift`).
   - Run `scripts/check-version.sh vX.Y.Z`, `swift build -c release` and `.build/release/coolhead selftest`.
4. **Tag and push**: `git tag -a vX.Y.Z -m "Cool Head X.Y.Z"`, then push the commit and the tag. The release workflow checks the numbers, builds, runs the selftest, signs the zip, and publishes the release with its title, notes and downloads.
5. **Check the release**: the zip's checksum matches `SHA256SUMS.txt`, its signature verifies, the app reports X.Y.Z, and its selftest passes.

## History

- 0.1.0 and 0.2.0 have no `.sig` file: signing began with 0.3.0, the first version that updates itself.
- 0.4.1 to 0.4.5 added features under patch numbers. These rules start with 0.5.0.
- Release notes for 0.1.0 to 0.3.2 were filled in from CHANGELOG.md on 15 November 2026; at first they had only GitHub's list of commits.
