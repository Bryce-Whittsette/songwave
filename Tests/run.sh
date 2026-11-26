#!/bin/bash
set -euo pipefail
project="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/songwave-wheels.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
cp -X "$project"/Sources/{GlassControls,Equalizer,Signal,VocalFocus,Trackpad}.swift "$project/Tests/WheelRegression.swift" "$scratch/"
xcrun swiftc -swift-version 5 "$scratch"/*.swift -o "$scratch/check"
"$scratch/check"

rhythm="$scratch/rhythm"
mkdir -p "$rhythm"
cp -X "$project"/Sources/{Effects,AudioTap,Equalizer,Signal,VocalFocus,Trackpad}.swift "$project/Tests/RhythmRegression.swift" "$rhythm/"
xcrun swiftc -swift-version 5 -O "$rhythm"/*.swift -o "$rhythm/check"
"$rhythm/check"

vocals="$scratch/vocals"
mkdir -p "$vocals"
cp -X "$project"/Sources/{Equalizer,Signal,VocalFocus,Trackpad}.swift "$project/Tests/VocalFocusRegression.swift" "$vocals/"
xcrun swiftc -swift-version 5 -O "$vocals"/*.swift -o "$vocals/check"
"$vocals/check"

patterns="$scratch/patterns"
mkdir -p "$patterns"
cp -X "$project"/Sources/{HapticPattern,Equalizer,Signal,VocalFocus,Trackpad}.swift "$project/Tests/PatternRegression.swift" "$patterns/"
xcrun swiftc -swift-version 5 -O "$patterns"/*.swift -o "$patterns/check"
"$patterns/check" "$project/Examples/120bpm.ahap"

live="$scratch/live"
mkdir -p "$live"
cp -X "$project"/Sources/{MusicDetection,HapticPattern,Equalizer,Signal,VocalFocus}.swift "$project/Tests/LiveHapticsRegression.swift" "$live/"
xcrun swiftc -swift-version 5 -O "$live"/*.swift -o "$live/check"
"$live/check"
