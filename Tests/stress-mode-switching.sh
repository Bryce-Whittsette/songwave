#!/bin/bash
set -euo pipefail
project="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/songwave-mode-stress.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
model="${1:-$project/Resources/Vocals/Spleeter2Model.mlmodelc}"
[[ -d "$model" ]] || { printf 'Bundled model missing.\n' >&2; exit 1; }
app="$scratch/SongWaveModeStress.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/Vocals" "$scratch/source"
ln -s "$model" "$app/Contents/Resources/Vocals/Spleeter2Model.mlmodelc"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>studio.songwave.offline-mode-stress</string><key>CFBundleExecutable</key><string>check</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
cp -X "$project"/Sources/{Playback,Source,MusicDetection,CaptureRequest,HapticPattern,Signal,Equalizer,RhythmDSP,VocalFocus,ListeningHealth,IsolatedVocals,Vendor*}.swift "$project/Tests/Support/PlaybackTestEdges.swift" "$project/Tests/ModeSwitchStress.swift" "$scratch/source/"
xcrun swiftc -swift-version 5 -O -D SONGWAVE_REAL_ISOLATION_TEST "$scratch/source/"*.swift -o "$app/Contents/MacOS/check"
"$app/Contents/MacOS/check" "${2:-0}"
