#!/bin/bash
set -euo pipefail
project="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/songwave-mobile-core.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
cp -X "$project/Mobile/SongWaveiOS/MobileAudioCore.swift" "$project/Tests/MobileRingRegression.swift" "$scratch/"
xcrun swiftc -swift-version 5 -O "$scratch/"*.swift -o "$scratch/check"
"$scratch/check"
