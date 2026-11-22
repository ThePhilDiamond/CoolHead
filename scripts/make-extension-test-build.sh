#!/bin/sh
# Builds the test version of Cool Head for Chrome into build/chrome-test, for loading by hand in Chrome
# (chrome://extensions, Developer mode, Load unpacked). It's the same extension with the test log turned on: what it
# did and why, kept in Chrome's storage on this computer and read on the Log page (right-click the toolbar button,
# Open the test log). Sites appear by host name only.
#
# It keeps the manifest's "key", so its ID is the one Cool Head's helper allows for a copy loaded by hand
# (idncmcjhcnoknfiomdkjidgmjkglmghl) and it links to Cool Head. Running this again replaces the folder; press the
# reload arrow on chrome://extensions to pick up the new copy.
#   scripts/make-extension-test-build.sh
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Extension/chrome"
OUT="$ROOT/build/chrome-test"
mkdir -p "$OUT"
# Only this script writes here; clearing it first means a file removed from the extension doesn't linger.
find "$OUT" -mindepth 1 -delete
for part in manifest.json icons popup setup src content log; do cp -R "$SRC/$part" "$OUT/"; done

cat > "$OUT/src/build.js" <<'JS'
// Written by scripts/make-extension-test-build.sh: this copy is the test build, so the test log is on.
export const TEST_BUILD = true;
JS

python3 -I - "$OUT/manifest.json" <<'PY'
import json, sys
path = sys.argv[1]
m = json.load(open(path))
m["name"] = "Cool Head for Chrome (test)"
m["version_name"] = m["version"] + " test"
m["action"]["default_title"] = "Cool Head for Chrome (test)"
with open(path, "w") as f:
    json.dump(m, f, indent=2)
    f.write("\n")
PY
echo "$OUT"
