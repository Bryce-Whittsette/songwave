#!/bin/bash
set -euo pipefail
project="$(cd "$(dirname "$0")/.." && pwd)"
regression="CallPermissionRegression"
extra_sources=()
swift_flags=()
if [[ "${1:-}" == --audio-edges ]]; then
  regression="AudioEdgeRegression"
  shift
fi
if [[ "${1:-}" == --source-overlap ]]; then
  regression="SourceOverlapRegression"
  swift_flags=(-D SONGWAVE_DRIVER_BOUNDARY_TEST)
  extra_sources=("$project/Sources/Trackpad.swift" "$project/Sources/Effects.swift" "$project/Sources/PlayerWindowVisibility.swift" "$project/Tests/Support/DriverBoundary.swift")
  shift
fi
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
  "$project"/Tests/Support/{InterruptionHAL,InterruptionEdges}.swift "$project/Tests/$regression.swift" "$scratch/source/"
if [[ ${#extra_sources[@]} -gt 0 ]]; then cp -X "${extra_sources[@]}" "$scratch/source/"; fi
xcrun swiftc -swift-version 5 -O -warnings-as-errors ${swift_flags[@]+"${swift_flags[@]}"} "$scratch/source/"*.swift -o "$app/Contents/MacOS/check"
python3 - "$app/Contents/MacOS/check" "$regression" <<'PY'
import subprocess, sys
# A missing/wrongly typed SDK replacement must fail before the fixture runs.
forbidden={'_AudioHardwareCreateProcessTap','_AudioHardwareDestroyProcessTap',
    '_AudioHardwareCreateAggregateDevice','_AudioHardwareDestroyAggregateDevice',
    '_AudioDeviceCreateIOProcIDWithBlock','_AudioDeviceDestroyIOProcID','_AudioDeviceStart','_AudioDeviceStop',
    '_AudioObjectGetPropertyDataSize','_AudioObjectGetPropertyData','_AudioObjectSetPropertyData',
    '_AudioObjectAddPropertyListenerBlock','_AudioObjectRemovePropertyListenerBlock'}
if sys.argv[2] == 'AudioEdgeRegression':
    forbidden.add('_OBJC_CLASS_$_AVAudioPlayer')
# Clang's OS availability thunk imports dlsym for CoreFoundation version data;
# disassembly confirms Trackpad resolves its eight symbols through our Swift stub.
if sys.argv[2] == 'SourceOverlapRegression':
    forbidden.update({'_dlopen','_dlclose','_AudioObjectHasProperty','_OBJC_CLASS_$_AVAudioPlayer'})
symbols={line.split()[-1] for line in subprocess.check_output(['nm','-u',sys.argv[1]],text=True).splitlines() if line.split()}
assert not forbidden & symbols, 'Fixture linked real capture SDK calls: '+str(sorted(forbidden & symbols))
print('Fixture symbol audit: real Core Audio capture/property entry points are replaced.',flush=True)
PY
"$app/Contents/MacOS/check" "$@"
