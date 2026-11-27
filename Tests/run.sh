#!/bin/bash
set -euo pipefail
project="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/songwave-wheels.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
cp -X "$project"/Sources/{GlassControls,Equalizer,Signal,RhythmDSP,VocalFocus,Trackpad}.swift "$project/Tests/WheelRegression.swift" "$scratch/"
xcrun swiftc -swift-version 5 "$scratch"/*.swift -o "$scratch/check"
"$scratch/check"

rhythm="$scratch/rhythm"
mkdir -p "$rhythm"
cp -X "$project"/Sources/{Effects,AudioTap,Equalizer,Signal,RhythmDSP,VocalFocus,Trackpad}.swift "$project/Tests/RhythmRegression.swift" "$rhythm/"
xcrun swiftc -swift-version 5 -O "$rhythm"/*.swift -o "$rhythm/check"
"$rhythm/check"

vocals="$scratch/vocals"
mkdir -p "$vocals"
cp -X "$project"/Sources/{Equalizer,Signal,RhythmDSP,VocalFocus,Trackpad}.swift "$project/Tests/VocalFocusRegression.swift" "$vocals/"
xcrun swiftc -swift-version 5 -O "$vocals"/*.swift -o "$vocals/check"
"$vocals/check"

patterns="$scratch/patterns"
mkdir -p "$patterns"
cp -X "$project"/Sources/{HapticPattern,Equalizer,Signal,RhythmDSP,VocalFocus,Trackpad}.swift "$project/Tests/PatternRegression.swift" "$patterns/"
xcrun swiftc -swift-version 5 -O "$patterns"/*.swift -o "$patterns/check"
"$patterns/check" "$project/Examples/120bpm.ahap"

live="$scratch/live"
mkdir -p "$live"
cp -X "$project"/Sources/{MusicDetection,HapticPattern,Equalizer,Signal,RhythmDSP,VocalFocus}.swift "$project/Tests/LiveHapticsRegression.swift" "$live/"
xcrun swiftc -swift-version 5 -O "$live"/*.swift -o "$live/check"
"$live/check"

bass="$scratch/bass"
mkdir -p "$bass"
cp -X "$project"/Sources/{HapticPattern,Equalizer,Signal,RhythmDSP,VocalFocus,Trackpad}.swift "$project/Tests/BassRegression.swift" "$bass/"
xcrun swiftc -swift-version 5 -O "$bass"/*.swift -o "$bass/check"
"$bass/check"

access="$scratch/access"
mkdir -p "$access"
cp -X "$project/Sources/AudioAccessHealth.swift" "$project/Tests/AccessRegression.swift" "$access/"
xcrun swiftc -swift-version 5 -O "$access"/*.swift -o "$access/check"
"$access/check"

lifecycle="$scratch/lifecycle"
mkdir -p "$lifecycle"
cp -X "$project"/Sources/{Playback,Source,MusicDetection,HapticPattern,Signal,Equalizer,RhythmDSP,VocalFocus}.swift \
  "$project/Tests/PlaybackLifecycleRegression.swift" "$lifecycle/"
xcrun swiftc -swift-version 5 -O "$lifecycle"/*.swift -o "$lifecycle/check"
"$lifecycle/check"

display="$scratch/display"
mkdir -p "$display"
cp -X "$project"/Sources/{SignalDisplay,Signal,Equalizer,RhythmDSP,VocalFocus,Trackpad}.swift \
  "$project/Tests/DisplayRegression.swift" "$display/"
xcrun swiftc -swift-version 5 -O "$display"/*.swift -o "$display/check"
"$display/check"

xcrun swift "$project/Tools/verify-update.swift" --self-test

bash "$project/Tests/test-mobile-core.sh"
