# How Cool Head updates itself

Cool Head checks GitHub for a newer release a minute after it opens and then once a day. When one exists, the panel says so, with **Install** and **What's new**. To check now, click **Cool Head v…** at the top right of the panel: it says "Up to date" for a moment, or downloads, verifies and installs the update. The right-click menu also has **Check for Updates…**, and **Check for Updates Automatically** to turn the daily check off.

## What it sends

One request to GitHub's public API for the latest release of this repository. If you press Install, the download of that release's zip and its signature. Nothing about you, your Mac or your processes; GitHub sees the request come from your internet address, as it does for any web page.

## How it knows the update is genuine

1. The release workflow signs each release zip with the project's private Ed25519 key (`scripts/sign-update.swift`), and publishes the signature (`.zip.sig`) beside it.
2. The matching public key is built into the app (`Sources/CoolHeadApp/Updater.swift`).
3. Before installing, the app checks the signature against that key, and refuses the update if it doesn't match, so a changed or substituted download is never installed.
4. It also checks the download is Cool Head (same bundle identifier), at the version announced, with an intact code signature.
5. It checks the update can run on this Mac: the macOS version the update needs (its `LSMinimumSystemVersion`) against this Mac's. If this Mac is older, the update isn't installed, the working copy stays, the panel says which macOS it needs, and that version isn't offered again. Versions before 0.8.0 don't make this check, so a release that needs a newer macOS than its users have must say so in its notes.
5. It moves the running copy to the Trash (so it can be put back) and puts the new one in its place, then reopens.

A release without a signature can't be installed from inside the app; the panel says so and points to the release page.

## The key

- The private key lives in two places only: the repository secret `UPDATE_SIGNING_KEY`, used by the release workflow, and the maintainer's password manager. It is never committed.
- Make a key pair once, with `swift scripts/update-key.swift <folder>`, where `<folder>` is the folder to write the private key to, such as `.secrets` (which git ignores, so the key is never committed); it prints the public key for `Updater.swift`.
- If the private key is ever lost or exposed, make a new pair and ship a release with the new public key. Versions with the old key can't verify updates signed with the new one, so those users download that one release by hand.

## Tested

On 15 November 2026 a copy labelled 0.2.9 found v0.3.0 on GitHub, verified its signature, replaced itself and reopened as 0.3.0 (`COOLHEAD_UPDATE_TEST=1` makes a copy check and install at launch). The same day, a real installed 0.3.0 updated itself to v0.3.1 when its version was clicked.

## Not covered

Cool Head isn't signed with an Apple Developer ID or notarized (that needs the paid Apple Developer Program), so the first download from a browser still needs **Open Anyway** in System Settings ▸ Privacy & Security. Updates installed from inside the app don't, because macOS only asks about apps downloaded by a browser.
