#!/bin/sh
# Checks that every place a version appears agrees, so a release can't go out with mismatched numbers.
#   scripts/check-version.sh          on any change: VERSION, the app's own version, and CHANGELOG.md agree
#   scripts/check-version.sh v1.2.3   for a release: also the tag, and CHANGELOG.md has a dated section for it
# See RELEASING.md.
set -e
cd "$(dirname "$0")/.."
fail() { echo "Version check failed: $1"; exit 1; }

VERSION=$(cat VERSION)
echo "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || fail "VERSION ($VERSION) isn't MAJOR.MINOR.PATCH"
grep -q "version = \"$VERSION\"" Sources/CoolHeadCore/CaseReport.swift || fail "VERSION ($VERSION) and CoolHead.version in CaseReport.swift differ"
grep -q '^## \[Unreleased\]$' CHANGELOG.md || fail "CHANGELOG.md has no ## [Unreleased] section"
grep -Eq "^## \[$VERSION\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$" CHANGELOG.md || fail "CHANGELOG.md has no dated ## [$VERSION] section"
grep -q "^\[$VERSION\]: " CHANGELOG.md || fail "CHANGELOG.md has no [$VERSION] link at the bottom"

if [ -n "$1" ]; then
  [ "$1" = "v$VERSION" ] || fail "tag $1 doesn't match VERSION ($VERSION); the tag must be v$VERSION"
  notes=$(awk -v v="## [$VERSION] " 'index($0, v) == 1 {on=1; next} /^## / || /^\[[^]]+\]: / {on=0} on' CHANGELOG.md | grep -c '^- ' || true)
  [ "$notes" -gt 0 ] || fail "CHANGELOG.md's [$VERSION] section has no entries"
fi
echo "Version $VERSION: VERSION, the app, and CHANGELOG.md agree${1:+, and so does tag $1}."
