#!/bin/sh
# Builds the Chrome Web Store upload for Cool Head for Chrome: build/cool-head-for-chrome-<version>.zip, from
# Extension/chrome without its tests and developer tools, and without the manifest's "key". The key fixes the
# extension's ID while it's loaded by hand (idncmcjhcnoknfiomdkjidgmjkglmghl); the store refuses an upload that has
# one and gives the extension its own ID, which Cool Head's helper must then allow (see notes/chrome-link-protocol.md).
#   scripts/package-extension.sh
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
