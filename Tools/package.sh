#!/bin/bash
set -euo pipefail
project="$(cd "$(dirname "$0")/.." && pwd)"
app="${1:?Usage: bash Tools/package.sh /path/to/SongWave.app /output/folder}"
output="${2:?Specify an output folder outside the source tree}"
app="$(cd "$(dirname "$app")" && pwd)/$(basename "$app")"
mkdir -p "$output"
output="$(cd "$output" && pwd)"
case "$output/" in "$project/"*) printf 'Choose an output folder outside the source tree.\n' >&2; exit 1;; esac
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")"
case "$version" in *[!0-9.]*|'') printf 'Invalid version.\n' >&2; exit 1;; esac
stage="$(mktemp -d "${TMPDIR:-/tmp}/songwave-release.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
# File Provider folders may attach Finder metadata after a build. Verify a clean
# staging copy so incidental metadata is not shipped in the disk image or ZIP.
ditto --norsrc --noextattr "$app" "$stage/verified/SongWave.app"
app="$stage/verified/SongWave.app"
codesign --verify --deep --strict "$app"
[[ "$(lipo -archs "$app/Contents/MacOS/SongWave")" == arm64 ]] || {
  printf 'The AppleSilicon package requires an arm64 build.\n' >&2; exit 1;
}
mkdir -p "$stage/disk" "$stage/unpacked"
ditto --norsrc --noextattr "$app" "$stage/disk/SongWave.app"
ln -s /Applications "$stage/disk/Applications"
cat > "$stage/disk/Install SongWave.txt" <<'TXT'
SongWave — Public Preview

1. Drag SongWave into the Applications folder in this window.
2. Open SongWave from Applications, finish setup, and allow System Audio Recording.
3. Play music normally and rest a finger lightly on the trackpad.

Requires Apple silicon, macOS 14.2 or later, and a Force Touch trackpad.

This preview has not been notarized by Apple. If macOS blocks it and you choose
to proceed, first try opening SongWave, then use System Settings > Privacy &
Security > Open Anyway. Confirm that the app name is SongWave.

Help: https://github.com/Bryce-Whittsette/songwave
TXT
hdiutil create -quiet -volname SongWave -srcfolder "$stage/disk" -format UDZO "$output/SongWave-$version-AppleSilicon.dmg"
ditto -c -k --norsrc --noextattr --keepParent "$app" "$output/SongWave-macOS.zip"
ditto -x -k "$output/SongWave-macOS.zip" "$stage/unpacked"
codesign --verify --deep --strict "$stage/unpacked/SongWave.app"
# Only tracked source belongs in a public archive; no local files or Git metadata.
mkdir -p "$stage/songwave-source"
git -C "$project" archive HEAD | tar -xf - -C "$stage/songwave-source"
ditto -c -k --norsrc --noextattr --keepParent "$stage/songwave-source" "$output/songwave-source.zip"
(cd "$output" && shasum -a 256 "SongWave-$version-AppleSilicon.dmg" SongWave-macOS.zip songwave-source.zip > SHA256SUMS)
unzip -tq "$output/SongWave-macOS.zip"
unzip -tq "$output/songwave-source.zip"
printf 'Packaged SongWave %s in %s\n' "$version" "$output"
