#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")" && pwd)"
destination="${1:-$project_dir/../SongWave.app}"
parent="$(dirname "$destination")"
mkdir -p "$parent"
staging="$(mktemp -d "${TMPDIR:-/tmp}/songwave-build.XXXXXX")"
delivery=""
app="$staging/SongWave.app"

cleanup() {
  if [[ -n "$delivery" ]]; then
    if [[ -d "$delivery/previous.app" && ! -e "$destination" ]]; then
      mv "$delivery/previous.app" "$destination"
    fi
    rm -rf "$delivery"
  fi
  rm -rf "$staging"
}
trap cleanup EXIT

mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$staging/Sources"
cp -X "$project_dir"/Sources/*.swift "$staging/Sources/"
sdk="$(xcrun --sdk macosx --show-sdk-path)"
arch="$(uname -m)"
xcrun swiftc -swift-version 5 -O -sdk "$sdk" -target "${arch}-apple-macosx14.2" \
  "$staging"/Sources/*.swift -o "$app/Contents/MacOS/SongWave"
cp -X "$project_dir/Resources/Info.plist" "$app/Contents/"
cp -X "$project_dir/LICENSE" "$app/Contents/Resources/LICENSE.txt"
cp -X "$project_dir"/Resources/*LICENSE.txt "$project_dir"/Resources/SongWave.icns "$app/Contents/Resources/"
if [[ -d "$project_dir/Resources/Vocals" ]]; then
  ditto --norsrc --noextattr "$project_dir/Resources/Vocals" "$app/Contents/Resources/Vocals"
fi
mkdir -p "$app/Contents/Helpers"
cp -X "$project_dir/Helpers/YouTubeHost.swift" "$staging/YouTubeHost.swift"
xcrun swiftc -O -sdk "$sdk" -target "${arch}-apple-macosx14.2" "$staging/YouTubeHost.swift" -o "$app/Contents/Helpers/SongWaveYouTubeHost"
codesign --force --sign - "$app/Contents/Helpers/SongWaveYouTubeHost"
for browser in Chrome Firefox; do
  extension_dir="$app/Contents/Resources/YouTube/$browser"
  mkdir -p "$extension_dir"
  cp -X "$project_dir/YouTube/$browser/manifest.json" "$project_dir/YouTube/Shared/"*.js "$extension_dir/"
done
codesign --sign - "$app"
codesign --verify --strict "$app"

delivery="$(mktemp -d "$parent/.songwave-install.XXXXXX")"
ditto --norsrc --noextattr "$app" "$delivery/SongWave.app"
if [[ -e "$destination" || -L "$destination" ]]; then
  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$destination/Contents/Info.plist" 2>/dev/null || true)"
  if [[ -L "$destination" || "$bundle_id" != "studio.songwave.trackpad" ]]; then
    printf 'Choose another install location. A different item exists at %s\n' "$destination" >&2
    exit 1
  fi
  mv "$destination" "$delivery/previous.app"
fi
mv "$delivery/SongWave.app" "$destination"
