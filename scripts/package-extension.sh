#!/bin/sh
# Builds the Chrome Web Store upload for Cool Head for Chrome from Extension/chrome, without its tests and developer
# tools, and without the manifest's "key". That key fixes the extension's ID while it's loaded by hand
# (idncmcjhcnoknfiomdkjidgmjkglmghl); the store refuses an upload that has one and uses its own ID instead
# (pobnaljpjmpbpokcdbjpmlkdaljhhcfm), which Cool Head's helper allows (Extension/chrome/PROTOCOL.md).
#
# Writes build/cool-head-for-chrome-<version>.zip and, when the signing key is there, a signed
# build/cool-head-for-chrome-<version>.crx. The store's Verified CRX uploads accepts only packages signed with this key,
# so someone who gets into the store account still can't publish an update. The key stays in .secrets/ (git-ignored),
# with a backup kept outside this Mac; losing it means waiting on Chrome Web Store support to replace it.
#   scripts/package-extension.sh
#   COOLHEAD_CRX_KEY=<key.pem>   a key somewhere else (default .secrets/chrome-extension-key.pem)
#   CHROME=<Chrome binary>       the Chrome that signs the package; it runs on a scratch profile and exits, never
#                                touching a Chrome that's open (default Google Chrome)
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Extension/chrome"
VERSION=$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' "$SRC/manifest.json")
OUT="$ROOT/build/cool-head-for-chrome-$VERSION.zip"
STAGE=$(mktemp -d)
mkdir -p "$ROOT/build"

# Only what the extension runs: the popup, the setup page, the worker and its logic, the page scripts, and icons.
for part in manifest.json icons popup setup src content; do cp -R "$SRC/$part" "$STAGE/"; done

python3 -I - "$STAGE/manifest.json" <<'EOF'
import json, sys
path = sys.argv[1]
manifest = json.load(open(path))
manifest.pop("key", None)
with open(path, "w") as f:
    json.dump(manifest, f, indent=2)
    f.write("\n")
EOF

rm -f "$OUT"
(cd "$STAGE" && zip -qrX "$OUT" . -x '.*' -x '*/.*')
echo "$OUT"

KEY="${COOLHEAD_CRX_KEY:-$ROOT/.secrets/chrome-extension-key.pem}"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
if [ ! -f "$KEY" ]; then
  echo "No signing key at $KEY, so no signed .crx: the store needs one once Verified CRX uploads is on." >&2
  exit 0
fi
CRX="${OUT%.zip}.crx"
PROFILE=$(mktemp -d)
rm -f "$CRX" "$STAGE.crx"
"$CHROME" --pack-extension="$STAGE" --pack-extension-key="$KEY" --user-data-dir="$PROFILE" --no-first-run >/dev/null 2>&1
# Chrome writes the package beside the folder it packed. A CRX3 file starts with "Cr24" and version 3.
if [ "$(head -c 4 "$STAGE.crx" 2>/dev/null)" != "Cr24" ]; then
  echo "Chrome didn't make a signed package." >&2
  exit 1
fi
mv "$STAGE.crx" "$CRX"
echo "$CRX"
