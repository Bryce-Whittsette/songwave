# Silent capture loss: scoped production fix

The accepted scope is **explicit signal-interruption guidance with uncertainty, plus safe source-mute release**. Signal silence is never labeled as a confirmed revoked grant. This closes the two PR #15 UX gaps under that clarified contract, without claiming live OS permission or audible-call verification.

## Resulting behavior

- A previously audible live source that goes silent/unresponsive for 1.5 seconds shows **Audio signal interrupted · check recording access**. Listening help becomes available immediately. Capture health records an interrupted signal, independently of saved permission verification; listening stays active and the state clears when PCM returns.
- Startup silence remains ordinary waiting. Speech, excluded video and recognized-call states retain priority. A legitimate silent passage can produce the same warning as a zeroed stream; the app makes no denied-permission claim.
- Explicit Trackpad only now applies muting only after receiving non-silent raw PCM. The existing automatic route's 1.5-second grace is used for both zero-filled callbacks and stopped callbacks. Longer loss releases source muting; fresh PCM re-establishes it. Short gaps do not flap routing.
- Routing decisions use raw samples, not the listener's intensity, EQ or separated-vocal energy. An instrument-only section or zero intensity therefore cannot masquerade as capture loss simply because haptic output is quiet.
- If HAL rejects an unmute, the failed tap is destroyed and the existing actionable capture-error path runs. Route changes during first muting still discard the stale connection and reconnect. No new timer or permission prompt is added.

## Why the warning preserves uncertainty

The current public Core Audio headers expose operation errors, but no authoritative System Audio Recording grant query. Apple's [process-tap sample](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps) describes consent through the recording operation. AudioCap's [permission implementation](https://github.com/insidegui/AudioCap/blob/main/AudioCap/ProcessTap/AudioRecordingPermission.swift) explicitly uses private TCC SPI for direct status queries; that approach was not adopted.

Stopped/zero PCM can also mean legitimate silence, protected audio or a driver fault. The fixture deliberately compares a still-permitted silent passage with simulated revoked delivery: it requires the same truthful signal-loss state, no invented denial, no fatal error and no corrupted permission-verification state. The requested authoritative permission-only diagnosis was stopped at this boundary; the user explicitly selected uncertain, actionable capture guidance instead. No private TCC API, permission database access, grant reset, elevated helper or signing change is introduced.

## Verification

```sh
bash Tests/test-call-permission.sh --require-all
bash Tests/run.sh
```

The disposable fixture compiles the real capture/controller path with symbol-audited SDK replacements. Tests assert automatic and explicit Spotify/Music recovery, both outputs, stopped/zero callbacks, silent startup, brief gaps, zero EQ/intensity, failed unmute, actual SDK-error guidance, call priority, late startup cleanup and rapid call transitions. Controller regressions check that interruption guidance clears on fresh audio and never becomes a false permission verdict. All scoped requirements are now mandatory assertions; the old assessment flag remains accepted for compatibility.

Production changes are limited to playback mute ownership, router capture-health observation and recovery-state propagation. Signal.swift, HapticPattern.swift, separation/model code, branding, colors, signing/notarization and real grants remain unchanged. The real host's existing tap-registration stall and physical call/revoke/re-grant semantics are still outside fixture verification. Re-muting uses the existing tap property API; actual device response timing and audible onset behavior need hardware listening tests.
