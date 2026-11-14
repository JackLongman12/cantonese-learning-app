#!/usr/bin/env bash
# Builds and publishes a DuckLearn release to GitHub Releases. Installed apps check the
# latest release on launch and offer to update (app/lib/platform/updater.dart).
#
#   bash tool/release.sh            # from the repo root, on the dev PC (Git Bash)
#
# Needs: a clean, pushed working tree; the release signing key at
# %USERPROFILE%/.ducklearn/key.properties (never committed); gh logged in.
# Build number = number of commits, so every release is newer than the last.
set -euo pipefail
cd "$(dirname "$0")/.."

FLUTTER="${FLUTTER:-/c/src/flutter/bin/flutter}"
PY="pipeline/.venv/Scripts/python.exe"
KEY="${DUCKLEARN_KEY_PROPERTIES:-$USERPROFILE/.ducklearn/key.properties}"

[ -f "$KEY" ] || { echo "No signing key at $KEY: updates would not install over the app." >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "Commit your changes first." >&2; exit 1; }
git push -q origin HEAD

BUILD=$(git rev-list --count HEAD)
NAME="0.$BUILD.0"  # Windows needs three-part versions
TAG="b$BUILD"
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "$TAG already released; commit something new first." >&2
  exit 1
fi
echo "== DuckLearn $NAME ($TAG)"

echo "== content"
"$PY" -X utf8 -m duk build | tail -3
"$PY" -X utf8 -m duk tts | tail -1
"$PY" -X utf8 -m duk bundle

echo "== builds"
cd app
"$FLUTTER" build apk --release --split-per-abi --target-platform android-arm,android-arm64 \
  --build-name "$NAME" --build-number "$BUILD" | grep -E "Built|rror"
"$FLUTTER" build windows --release --build-name "$NAME" --build-number "$BUILD" | grep -E "Built|rror"
cd ..

OUT=build/release
rm -rf "$OUT"
mkdir -p "$OUT"
cp app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk "$OUT/DuckLearn-android-arm64.apk"
cp app/build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk "$OUT/DuckLearn-android-arm32.apk"
powershell -NoProfile -Command "Compress-Archive -Path 'app\\build\\windows\\x64\\runner\\Release\\*' -DestinationPath '$OUT\\DuckLearn-windows-x64.zip' -Force"

PREV=$(git describe --tags --abbrev=0 --match 'b*' 2>/dev/null || true)
NOTES=$(git log --no-merges --format='- %s' ${PREV:+$PREV..}HEAD | head -30)
[ -n "$NOTES" ] || NOTES="- Maintenance build"

echo "== publish"
git tag "$TAG"
git push -q origin "$TAG"
gh release create "$TAG" "$OUT"/* --title "DuckLearn $NAME" --notes "$NOTES" --latest
echo "== done: https://github.com/JackLongman12/cantonese-learning-app/releases/tag/$TAG"
