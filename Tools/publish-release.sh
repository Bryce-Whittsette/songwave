#!/bin/bash
set -euo pipefail
project="$(cd "$(dirname "$0")/.." && pwd)"
folder="${1:?Usage: bash Tools/publish-release.sh /path/to/packaged-release [--publish]}"
publish="${2:-}"
[[ -z "$publish" || "$publish" == --publish ]] || { printf 'Unknown option.\n' >&2; exit 1; }
cd "$project"
[[ -z "$(git status --porcelain)" ]] || { printf 'Commit and review source changes before preparing a public release.\n' >&2; exit 1; }
folder="$(cd "$folder" && pwd)"
(cd "$folder" && shasum -a 256 --check SHA256SUMS)
[[ "$(unzip -p "$folder/SongWave-macOS.zip" SongWave.app/Contents/Resources/BuildRevision.txt)" == "$(git rev-parse HEAD)" ]] || {
  printf 'Rebuild and package from this exact clean commit before publishing.\n' >&2; exit 1;
}
python3 "$project/Tools/prepare-update.py" "$folder"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
tag="v$version"
notes="$project/docs/releases/$version.md"
[[ -f "$notes" ]] || { printf 'Release notes missing.\n' >&2; exit 1; }
# A feed contains one versioned asset URL; verify the archive matches this tag.
xcrun swift "$project/Tools/verify-update.swift" "$folder/appcast.xml" "$folder/SongWave-macOS.zip" "$tag"
gh release create "$tag" --repo Bryce-Whittsette/songwave --target "$(git rev-parse HEAD)" \
  --title "SongWave $version — Public Preview" --notes-file "$notes" --draft --prerelease \
  "$folder/SongWave-$version-AppleSilicon.dmg" "$folder/SongWave-macOS.zip" \
  "$folder/songwave-source.zip" "$folder/SHA256SUMS" "$folder/appcast.xml"
if [[ "$publish" == --publish ]]; then
  gh release edit "$tag" --repo Bryce-Whittsette/songwave --draft=false
  printf 'Published %s. Check the Publish update feed workflow before announcing it.\n' "$tag"
else
  printf 'Draft ready. Review it, then publish with: gh release edit %s --repo Bryce-Whittsette/songwave --draft=false\n' "$tag"
fi
