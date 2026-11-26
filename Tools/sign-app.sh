#!/bin/bash
set -euo pipefail
app="${1:?Usage: bash Tools/sign-app.sh /path/to/SongWave.app}"
identity="${SONGWAVE_SIGNING_IDENTITY:--}"
flags=(--force --sign "$identity")
if [[ "$identity" != - ]]; then flags+=(--timestamp --options runtime); fi
framework="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
if [[ -d "$framework" ]]; then
  for child in "$framework/Autoupdate" "$framework/Updater.app" \
    "$framework/XPCServices/Downloader.xpc" "$framework/XPCServices/Installer.xpc"; do
    codesign "${flags[@]}" --preserve-metadata=entitlements "$child"
  done
  codesign "${flags[@]}" "$app/Contents/Frameworks/Sparkle.framework"
fi
codesign "${flags[@]}" "$app/Contents/Helpers/SongWaveYouTubeHost"
codesign "${flags[@]}" "$app"
codesign --verify --deep --strict "$app"
