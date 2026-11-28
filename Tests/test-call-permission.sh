#!/bin/bash
set -euo pipefail
project="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/songwave-call-permission.XXXXXX")"
fixture_id=""
cleanup() {
  if [[ "$fixture_id" == studio.songwave.interruption-test.* ]]; then
    /usr/bin/defaults delete "$fixture_id" >/dev/null 2>&1 || true
  fi
  rm -rf "$scratch"
}
trap cleanup EXIT
app="$scratch/InterruptionFixture.app"
mkdir -p "$app/Contents/MacOS" "$scratch/source"
python3 - "$app" <<'PY'
from pathlib import Path
import plistlib, sys, uuid
info={'CFBundleExecutable':'check','CFBundleIdentifier':'studio.songwave.interruption-test.'+uuid.uuid4().hex,
      'CFBundleName':'SongWave Interruption Fixture','CFBundlePackageType':'APPL'}
(Path(sys.argv[1])/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
fixture_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")"
cp -X "$project"/Sources/{Studio,Source,ListeningSetup,GlassControls,Signal,Equalizer,RhythmDSP,VocalFocus,HapticPattern,SignalDisplay,ListeningHealth,AudioAccessHealth,Playback,MusicDetection,CaptureRequest,AudioTap,PlayerAuthorization}.swift \
  "$project"/Tests/Support/{InterruptionHAL,InterruptionEdges}.swift "$project/Tests/CallPermissionRegression.swift" "$scratch/source/"
xcrun swiftc -swift-version 5 -O -warnings-as-errors "$scratch/source/"*.swift -o "$app/Contents/MacOS/check"
python3 - "$app/Contents/MacOS/check" <<'PY'
import subprocess, sys
# A missing/wrongly typed SDK replacement must fail before the fixture runs.
forbidden={'_AudioHardwareCreateProcessTap','_AudioHardwareDestroyProcessTap',
    '_AudioHardwareCreateAggregateDevice','_AudioHardwareDestroyAggregateDevice',
    '_AudioDeviceCreateIOProcIDWithBlock','_AudioDeviceDestroyIOProcID','_AudioDeviceStart','_AudioDeviceStop',
    '_AudioObjectGetPropertyDataSize','_AudioObjectGetPropertyData','_AudioObjectSetPropertyData',
    '_AudioObjectAddPropertyListenerBlock','_AudioObjectRemovePropertyListenerBlock'}
symbols={line.split()[-1] for line in subprocess.check_output(['nm','-u',sys.argv[1]],text=True).splitlines() if line.split()}
assert not forbidden & symbols, 'Fixture linked real capture SDK calls: '+str(sorted(forbidden & symbols))
print('Fixture symbol audit: real Core Audio capture/property entry points are replaced.',flush=True)
PY
"$app/Contents/MacOS/check" "$@"
