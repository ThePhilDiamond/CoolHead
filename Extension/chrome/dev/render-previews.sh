#!/bin/sh
# Screenshots the popup from dev/preview.html with made-up data, in light and dark, using headless Google Chrome on
# its own data folder (never your own Chrome profile).
#   dev/render-previews.sh <output folder> <scratch folder for Chrome's data>
# --allow-file-access-from-files lets the preview's modules load from file:// in this throwaway profile only.
set -eu
OUT="$1"
DATA="$2/chrome-data"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$OUT" "$DATA"
shot() { # name screen theme
  "$CHROME" --headless=new --user-data-dir="$DATA" --no-first-run --no-default-browser-check --hide-scrollbars \
    --allow-file-access-from-files --force-device-scale-factor=2 --window-size=360,600 --virtual-time-budget=3000 \
    --screenshot="$OUT/$1.png" "file://$HERE/preview.html?screen=$2&theme=$3" 2>/dev/null
}
for theme in light dark; do
  shot "home-$theme" home "$theme"
  shot "start-session-$theme" start "$theme"
  shot "held-open-$theme" held "$theme"
done
shot "held-asks-once-light" confirm light
shot "session-ending-light" ending light
shot "session-running-dark" session dark
shot "alone-dark" alone dark
shot "settings-light" settings light
shot "safe-list-light" safe light
ls "$OUT"
