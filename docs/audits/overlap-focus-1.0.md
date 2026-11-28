# Overlapping sources and focus under load

## Finding and fix

A deterministic regression reproduced stuck automatic capture when a Core Audio process object ID was recycled for a new PID from the same app bundle. The router compared only object ID and bundle, so it kept the old tap. In the fixture that old process stopped supplying PCM, and a fresh tap never opened. This is a reproduced lifecycle failure under SDK-boundary injection, not a claim that the live Mac hit this exact race.

Automatic feeds and pending requests now retain the PID already read during discovery. A changed PID retires the old feed/request even when the object ID and bundle match. Explicit player routing has the same identity check using a PID snapshot on its existing scan. No new timer, isolation algorithm or haptic rendering change is introduced.

## Repeatable regression

```sh
bash Tests/test-call-permission.sh --source-overlap
```

The fixture runs production AudioTap → SampleRing → MacMusicInput → Playback → Trackpad. It also uses the real Effects/Ultra policy, Studio, SignalDisplay and PlayerWindowVisibility. SDK capture calls and the final private actuator ABI are compile-time replacements. The real driver constructs, normalizes and releases its waveform dictionaries; the replacement validates duration, finite tones, normalized weights and gain. All eight private function lookups must reach the fixture, and all actuator/tap ownership must close.

The pre-run symbol audit rejects real Core Audio capture/property calls, framework opening/closing, property-existence queries and speaker-player linkage. Clang's OS-availability thunk imports `dlsym` for CoreFoundation version data; disassembly confirmed those calls belong to `__initializeAvailabilityCheck`, while Trackpad resolves its functions through the Swift replacement. No private framework or device is opened by this fixture.

Coverage includes four automatic/explicit × output-mode process replacements, an obsolete request released after a new PID arrives, late callbacks retained after retirement/Stop, and 36 Spotify/Music/browser handoffs with three simultaneous taps. Selected routing remains single-owner and teardown complete. A native controlled window generates 360 visibility/activation transitions while two CPU workers run through Ultra's normal 45-second deadline; saved settings and listening survive, capture does not rebuild merely for focus, and the UI countdown expires. Thermal protection remains active; a host that blocks/ends Ultra prints that full-duration coverage was unavailable.

The full local burst passed, with a maximum main-actor heartbeat interval of about 128 ms for a loop deliberately sleeping 120 ms per cycle. This is not motor latency, an audio-glitch measurement or a physical foreground-switch benchmark. Native notifications are injected; no fixture window is ordered onto the user's desktop. The default regression suite also passed locally. CI runs the new fixture after the existing call and audio-edge suites.

## Live countercheck and limits

On November 28, the installed 1.0.0 build 24 successfully detected a generated local musical fixture, including with haptics off. The app showed nonzero music level and recent beats. Two bounded 65-second source/CPU trials each launched 22 local player processes, using overlapping player processes, with two CPU workers. Each included a normal 45-second Ultra request, keyboard lighting off, and verified return to the normal waiting/listening view afterward. All test players/workers exited; the original Speakers + haptics, Beat, 100% intensity and enabled-haptics state remained. No microphone, personal song metadata, permission change or signing change was involved.

These trials used synthetic local players, not live Spotify → Music → browser playback. UI snapshots show detection and state recovery, not continuous tactile quality or absence of every audible glitch. The previously recorded registration stall was not observed in these live checks; its underlying cause and behavior across other sessions remain unresolved.

**Real rapid foreground switching remains unverified.** The UI automation provider failed/reset during repeated Cmd-Tab and window-raise actions. An independent activation observer recorded zero verified app activations in the latter trial. No successful high-rate foreground-switch test is claimed. This tool failure does not replace the injected native observer coverage above or establish a SongWave fault.

Protected Signal.swift, HapticPattern.swift, isolation/Core ML internals, colors, signing/notarization and release assets remain unchanged. Physical sync, subjective sensation, Bluetooth/calls and long-term motor/energy behavior need separate evidence.
