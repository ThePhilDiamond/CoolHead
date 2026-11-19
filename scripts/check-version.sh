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
# a merge left unfinished (15 November 2026: one was committed with its markers still in the changelog)
! grep -Eq '^(<<<<<<<|=======$|>>>>>>>)' CHANGELOG.md || fail "CHANGELOG.md still has merge conflict markers"
# entries waiting for a release live in changes/, one file each, so pull requests don't edit the same lines
unreleased=$(awk '/^## \[Unreleased\]$/ {on=1; next} /^## / {on=0} on' CHANGELOG.md | grep -c '^- ' || true)
[ "$unreleased" -eq 0 ] || fail "CHANGELOG.md has entries under [Unreleased]; put each in its own file in changes/ (see changes/README.md)"
for f in $(find changes -type f ! -path changes/README.md | sort); do
  echo "$f" | grep -Eq '^changes/(added|changed|fixed)/[a-z0-9]+(-[a-z0-9]+)*\.md$' \
    || fail "$f: entries go in changes/added, changes/changed or changes/fixed, named in lowercase words joined by hyphens, ending .md"
  head -c 2 "$f" | grep -q '^- ' || fail "$f doesn't start with \"- \""
  ! grep -Eq '^(<<<<<<<|=======$|>>>>>>>)' "$f" || fail "$f still has merge conflict markers"
done
grep -Eq "^## \[$VERSION\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$" CHANGELOG.md || fail "CHANGELOG.md has no dated ## [$VERSION] section"
grep -q "^\[$VERSION\]: " CHANGELOG.md || fail "CHANGELOG.md has no [$VERSION] link at the bottom"
# the release date Settings shows is the changelog's
DATE=$(grep -E "^## \[$VERSION\] - " CHANGELOG.md | head -1 | sed -E 's/.* - //')
grep -q "released = \"$DATE\"" Sources/CoolHeadCore/CaseReport.swift || fail "CoolHead.released in CaseReport.swift isn't $DATE, the date CHANGELOG.md gives $VERSION"

if [ -n "$1" ]; then
  [ "$1" = "v$VERSION" ] || fail "tag $1 doesn't match VERSION ($VERSION); the tag must be v$VERSION"
  notes=$(awk -v v="## [$VERSION] " 'index($0, v) == 1 {on=1; next} /^## / || /^\[[^]]+\]: / {on=0} on' CHANGELOG.md | grep -c '^- ' || true)
  [ "$notes" -gt 0 ] || fail "CHANGELOG.md's [$VERSION] section has no entries"
fi
echo "Version $VERSION: VERSION, the app, and CHANGELOG.md agree${1:+, and so does tag $1}."
