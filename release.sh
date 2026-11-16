#!/bin/zsh
# Publishes a new version of Text Tool.
#
#   ./release.sh 1.1.0 "What changed in this version" [--push]
#
# Stamps the version into Info.plist, builds the app, saves the zip in releases/,
# points updates/latest.json at it (installed apps read this to update themselves),
# adds a CHANGELOG entry, then commits and tags v<version>. With --push it also pushes.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-}"
NOTES="${2:-}"
PUSH="${3:-}"
RAW_BASE="https://raw.githubusercontent.com/mudafakins/Text-Tool/main"
PLIST="Resources/Info.plist"
FEED="updates/latest.json"

[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { echo "Usage: ./release.sh 1.2.3 \"notes\" [--push]"; exit 1; }
[[ -n "$NOTES" ]] || { echo "Please describe what changed."; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "Commit your changes first, so the release matches the code."; exit 1; }
if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then echo "v$VERSION already exists."; exit 1; fi

# Build number: one more than the last published release (or the current one for the first release).
if [[ -f "$FEED" ]]; then
  BUILD=$(( $(python3 -c "import json;print(json.load(open('$FEED'))['build'])") + 1 ))
else
  BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$PLIST"

./build.sh

mkdir -p releases updates
ZIP="releases/TextTool-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "build/Text Tool.app" "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
MIN_OS=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$PLIST")

python3 - "$FEED" "$VERSION" "$BUILD" "$RAW_BASE/$ZIP" "$SHA" "$NOTES" "$MIN_OS" <<'PY'
import json, sys
path, version, build, url, sha, notes, min_os = sys.argv[1:]
json.dump({"version": version, "build": int(build), "url": url, "sha256": sha,
           "notes": notes, "minimumSystemVersion": min_os}, open(path, "w"), indent=2)
open(path, "a").write("\n")
PY

ENTRY="## v$VERSION ($(date +%Y-%m-%d))\n\n$NOTES\n"
if [[ -f CHANGELOG.md ]]; then
  { echo "# Changelog\n"; echo "$ENTRY"; tail -n +3 CHANGELOG.md; } > CHANGELOG.tmp && mv CHANGELOG.tmp CHANGELOG.md
else
  { echo "# Changelog\n"; echo "$ENTRY"; } > CHANGELOG.md
fi

git add -A
git commit -q -m "Release v$VERSION" -m "$NOTES"
git tag -a "v$VERSION" -m "Text Tool $VERSION" -m "$NOTES"
echo "Released v$VERSION (build $BUILD): $ZIP"

if [[ "$PUSH" == "--push" ]]; then
  git push origin HEAD --follow-tags
  echo "Pushed. Installed copies will pick it up on their next update check."
else
  echo "Not pushed yet. Run: git push origin HEAD --follow-tags"
fi
