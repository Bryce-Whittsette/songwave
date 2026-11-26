#!/bin/bash
set -euo pipefail
project="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/songwave-isolation.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
model="${1:-$project/Resources/Vocals/Spleeter2Model.mlmodelc}"
if [[ ! -d "$model" ]]; then
  printf 'Vocal model not found: %s\n' "$model" >&2
  exit 1
fi
# Generate the fixture into a file. This does not play speech over the speakers.
/usr/bin/say -o "$scratch/voice.aiff" 'This is SongWave. The voice should stay clear while bass and drums are removed. The melody follows my voice.'
cp -X "$project"/Sources/Vendor*.swift "$project/Sources/IsolatedVocals.swift" \
  "$project/Tests/VocalIsolationRegression.swift" "$scratch/"
xcrun swiftc -swift-version 5 -O "$scratch/"*.swift -o "$scratch/check"
"$scratch/check" "$model" "$scratch/voice.aiff"
