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
mkdir -p "$app/Contents/Frameworks" "$staging/Sparkle"
sparkle_archive="$(bash "$project_dir/Tools/fetch-sparkle.sh")"
tar -xJf "$sparkle_archive" -C "$staging/Sparkle"
ditto --norsrc --noextattr "$staging/Sparkle/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
cp -X "$project_dir"/Sources/*.swift "$staging/Sources/"
sdk="$(xcrun --sdk macosx --show-sdk-path)"
arch="$(uname -m)"
xcrun swiftc -swift-version 5 -O -sdk "$sdk" -target "${arch}-apple-macosx14.2" \
  -F "$staging/Sparkle" -framework Sparkle -Xlinker -rpath -Xlinker '@executable_path/../Frameworks' \
  "$staging"/Sources/*.swift -o "$app/Contents/MacOS/SongWave"
cp -X "$project_dir/Resources/Info.plist" "$app/Contents/"
revision="source archive"
if [[ "$(git -C "$project_dir" rev-parse --show-toplevel 2>/dev/null || true)" == "$project_dir" ]]; then
  revision="$(git -C "$project_dir" rev-parse HEAD)"
  if [[ -n "$(git -C "$project_dir" status --porcelain)" ]]; then revision="$revision-dirty"; fi
fi
printf '%s\n' "$revision" > "$app/Contents/Resources/BuildRevision.txt"
cp -X "$project_dir/LICENSE" "$app/Contents/Resources/LICENSE.txt"
cp -X "$project_dir"/Resources/*LICENSE.txt "$project_dir"/Resources/SongWave.icns "$app/Contents/Resources/"
if [[ -d "$project_dir/Resources/Vocals" ]]; then
  ditto --norsrc --noextattr "$project_dir/Resources/Vocals" "$app/Contents/Resources/Vocals"
fi
mkdir -p "$app/Contents/Helpers"
cp -X "$project_dir/Helpers/YouTubeHost.swift" "$staging/YouTubeHost.swift"
xcrun swiftc -O -sdk "$sdk" -target "${arch}-apple-macosx14.2" "$staging/YouTubeHost.swift" -o "$app/Contents/Helpers/SongWaveYouTubeHost"
for browser in Chrome Firefox; do
  extension_dir="$app/Contents/Resources/YouTube/$browser"
  mkdir -p "$extension_dir"
  cp -X "$project_dir/YouTube/$browser/manifest.json" "$project_dir/YouTube/Shared/"*.js "$extension_dir/"
done
bash "$project_dir/Tools/sign-app.sh" "$app"

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
