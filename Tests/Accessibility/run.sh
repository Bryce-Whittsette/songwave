#!/bin/bash
set -euo pipefail
project="$(cd "$(dirname "$0")/../.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/songwave-accessibility.XXXXXX")"
# Keep the result bundle on failure for inspection; no production app is launched.
python3 "$project/Tests/Accessibility/generate-project.py" "$scratch/project"
xcodebuild -project "$scratch/project/Accessibility.xcodeproj" -scheme Accessibility \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "$scratch/build" \
  -resultBundlePath "${SONGWAVE_AX_RESULTS:-$scratch/Accessibility.xcresult}" \
  -parallel-testing-enabled NO test
