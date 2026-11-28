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

adversarial="$scratch/adversarial"
mkdir -p "$adversarial"
cp -X "$project"/Sources/{HapticPattern,Equalizer,Signal,RhythmDSP,VocalFocus,Trackpad}.swift "$project/Tests/PatternAdversarialRegression.swift" "$adversarial/"
xcrun swiftc -swift-version 5 -O "$adversarial"/*.swift -o "$adversarial/check"
"$adversarial/check"

capture="$scratch/capture"
mkdir -p "$capture"
cp -X "$project"/Sources/{AudioTap,CaptureRequest}.swift "$project/Tests/CaptureRegression.swift" "$capture/"
xcrun swiftc -swift-version 5 -O "$capture"/*.swift -o "$capture/check"
"$capture/check"

captureAccess="$scratch/capture-access"
mkdir -p "$captureAccess"
cp -X "$project"/Sources/{CaptureRequest,PlayerAuthorization}.swift "$project/Tests/CaptureAccessRegression.swift" "$captureAccess/"
xcrun swiftc -swift-version 5 -O "$captureAccess"/*.swift -o "$captureAccess/check"
"$captureAccess/check"

hal="$scratch/hal"
mkdir -p "$hal"
cp -X "$project"/Sources/{AudioTap,CaptureRequest}.swift "$project/Tests/AudioTapLifecycleRegression.swift" "$hal/"
xcrun swiftc -swift-version 5 -O "$hal"/*.swift -o "$hal/check"
"$hal/check"

both="$scratch/both"
mkdir -p "$both"
cp -X "$project"/Sources/{HapticPattern,Equalizer,Signal,RhythmDSP,VocalFocus,Trackpad}.swift "$project/Tests/BothRegression.swift" "$both/"
xcrun swiftc -swift-version 5 -O "$both"/*.swift -o "$both/check"
"$both/check"

live="$scratch/live"
mkdir -p "$live"
cp -X "$project"/Sources/{MusicDetection,CaptureRequest,HapticPattern,Equalizer,Signal,RhythmDSP,VocalFocus}.swift "$project/Tests/LiveHapticsRegression.swift" "$live/"
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
cp -X "$project"/Sources/{Playback,Source,MusicDetection,CaptureRequest,HapticPattern,Signal,Equalizer,RhythmDSP,VocalFocus,ListeningHealth}.swift \
  "$project/Tests/PlaybackLifecycleRegression.swift" "$project/Tests/Support/PlaybackTestEdges.swift" "$lifecycle/"
xcrun swiftc -swift-version 5 -O "$lifecycle"/*.swift -o "$lifecycle/check"
"$lifecycle/check"

display="$scratch/display"
mkdir -p "$display"
cp -X "$project"/Sources/{SignalDisplay,Signal,Equalizer,RhythmDSP,VocalFocus,Trackpad}.swift \
  "$project/Tests/DisplayRegression.swift" "$display/"
xcrun swiftc -swift-version 5 -O "$display"/*.swift -o "$display/check"
"$display/check"

xcrun swift "$project/Tools/verify-update.swift" --self-test
python3 "$project/Tests/UpdateDeltaRegression.py"

bash "$project/Tests/test-mobile-core.sh"

health="$scratch/health"
mkdir -p "$health"
cp -X "$project/Sources/ListeningHealth.swift" "$project/Tests/ListeningHealthRegression.swift" "$health/"
xcrun swiftc -swift-version 5 -O "$health"/*.swift -o "$health/check"
"$health/check"

studio="$scratch/studio"
mkdir -p "$studio"
cp -X "$project"/Sources/{Studio,MenuController,Source,ListeningSetup,GlassControls,Signal,Equalizer,RhythmDSP,VocalFocus,HapticPattern,SignalDisplay,ListeningHealth,AudioAccessHealth}.swift "$project/Tests/StudioRecoveryRegression.swift" "$project/Tests/Support/StudioTestEdges.swift" "$studio/"
xcrun swiftc -swift-version 5 -O "$studio"/*.swift -o "$studio/SongWaveStudioRegression"
"$studio/SongWaveStudioRegression"

motion="$scratch/motion"
mkdir -p "$motion"
cp -X "$project"/Sources/{MotionAccessibility,VisualActivity,Signal,Equalizer,RhythmDSP,VocalFocus,Trackpad}.swift "$project/Tests/MotionAccessibilityRegression.swift" "$motion/"
xcrun swiftc -swift-version 5 -O "$motion"/*.swift -o "$motion/check"
"$motion/check"
