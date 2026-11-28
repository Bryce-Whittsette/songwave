# Session and capture stress checks

This pass follows the 1.0.0 release. It changes capture ownership, route recovery, input validation and sleep/resume state. It does not change the isolation model/algorithm, haptic DSP, visual system, signing or notarization configuration.

## Reproduced failures and corrections

- A stalled Core Audio startup blocked the playback queue. Startup now runs on at most four workers, with cancellable result handoff and an eight-second session deadline. Stop remains responsive; a late result cannot mute a player or enter a replacement session. An OS call already in progress cannot be forcibly cancelled. Four permanently stalled calls exhaust admission until they return or the app restarts.
- A route change could leave old taps and analysis rates in use. Tap format, default output and output sample-rate notifications now request a rebuild. A format recheck after listener registration also catches changes during startup. Stale startup results are discarded before muting or PCM consumption.
- Buffered PCM survived an idle/sleep interval. The fixed-capacity ring now expires input after 200 ms using a continuous clock that includes system sleep. Empty callbacks cannot refresh stale audio.
- Recycled process object IDs could retain a different app's cached identity. Router caches now validate bundle identity as well as the object ID.
- Wake could turn haptics back on after the listener had disabled them. Resume preserves bypass; duplicate sleep notifications preserve resume intent, and explicit Stop cancels it.
- Malformed AHAP parameter arrays could fall back to full-strength defaults. Invalid shapes, duplicate parameters and ambiguous pattern entries now fail parsing. Audio references remain ignored and are never opened.
- Invalid capture metadata or nonfinite PCM could enter analysis. Capture validates the Float32 layout, channel/byte counts, alignment and sample rate. Corrupt sample values become silence; normal PCM and headroom are preserved. These checks assume the OS supplies readable backing memory; metadata validation cannot prove an arbitrary pointer's allocation size.
- Isolated input above its existing 192 kHz limit could silently yield no output. Playback now reports the limit and suggests Light or a lower-rate source. It does not change the selected engine automatically or load a model before the source rate is known.

## Repeatable coverage

Run `bash Tests/run.sh` for the default suite. It uses production capture/routing/playback code with injected OS/device boundaries; no recording permission, speakers, keyboard lighting or physical actuator is used.

| Area | Coverage |
| --- | --- |
| Routes | 20 reconnect cycles across automatic/explicit sources and both output modes; 16/44.1/48/96 kHz changes; stale asynchronous startup completions; unchanged-format notifications; cleanup at every injected HAL setup failure |
| Sample rates | 16 rates from 8–768 kHz at capture and playback boundaries; zero, negative, nonfinite and out-of-range values rejected; existing isolation limit reported without model substitution |
| Buffers/files | Empty, missing, misaligned, oversized and partial-frame PCM layouts; unequal/missing planar channels; NaN/infinity/outliers; unchanged valid mono/interleaved/planar stereo; zero-byte, empty valid WAV and truncated WAV startup |
| Source identity | 3,000 simulated Spotify/Music/browser switches, reused object IDs, both muting policies and long idle clock jumps |
| Lifetime | Blocked startup cancellation, 80 startup requests with at most four admissions, failure/timeout recovery, calls, Stop, wake bypass and duplicate sleep notifications |
| AHAP | 10,000 seeded byte mutations, invalid encodings/numbers, malformed/duplicate parameters, overlap boundaries and hostile audio references |
| Ring lifetime | Continuous-clock jumps through 24 hours, a real 300 ms stale-input check, overflow and 1.92 million concurrently offered samples |

`bash Tests/test-isolation.sh` additionally runs the unchanged bundled Core ML model and 120 rapid Beat/Voice/Both, Light/Isolated and output changes under CPU load, with fake capture/actuator edges. The controlled separation fixture improved SNR from −1.34 dB to 15.12 dB; this is not a real-song accuracy score. The stress process peaked near 111 MB RSS, not a whole-app RAM or energy measurement.

A two-hour wall-clock idle/resume run of the async-capture prototype passed, including no retained capture, muting or late output while idle and successful resume. Its capture/actuator edges were simulated; it was not physical sleep and preceded the final format/buffer validation refinements. Repeat a bounded soak with:

```sh
bash Tests/stress-mode-switching.sh Resources/Vocals/Spleeter2Model.mlmodelc 7200
```

## Hardware evidence and open checks

Local validation used an Apple-silicon MacBook Air on macOS 27.3 build 26C5047e. Only built-in speakers at 48 kHz were available as an active output. Bluetooth/wired switching and physical sleep/wake remain unverified.

The capture ring and real `AudioTap` boundary suites also passed with Address Sanitizer and compiler warnings treated as errors. A native app build passed strict code-signature verification using the existing build configuration. A local native accessibility run could not initialize macOS UI automation; that environment failure is not an accessibility pass. The repository's separate accessibility CI remains the native UI gate.

A live capture attempt reproduced a long wait inside `AudioDeviceStart`. The candidate kept Stop responsive and showed bounded capture-failure recovery. The underlying OS/driver/authorization cause of the live no-signal result was not established or fixed. Offline recovery coverage is not proof of successful live capture on this machine.

Revoking System Audio Recording required the owner's Touch ID/password. Authentication was cancelled and permission was left enabled. Mid-session permission failure and call interruption are covered through injected boundaries; live permission revocation and a real call remain unverified. No recording or song metadata is included in this report.

The public 1.0.0 appcast and signing/notarization configuration are unchanged by this pass. Source fixes require a subsequent versioned release before installed apps receive them.
