# Call interruption and permission-loss assessment

This is fixture-only verification of the production capture/recovery path. It does **not** close the live macOS call/TCC verification gap or claim that audible output was tested. No production source, separation model, appearance, signing configuration, installed app or real permission setting changes in this batch.

## Run it

```sh
bash Tests/test-call-permission.sh
```

The normal command checks implemented safety/recovery invariants and prints unresolved acceptance findings explicitly. **A passing fixture job does not mean every requested behavior is clean.** To make those findings fail the assessment:

```sh
bash Tests/test-call-permission.sh --require-all
```

The strict assessment currently returns **2** for the findings below. Do not remove a finding or substitute a permission-success label just to make that command green. The Checks workflow runs the fixture in its own `call-permission` job; compilation treats warnings as errors. Known gaps appear as CI warning annotations and in the job summary, not just buried in console output.

## Boundary and privacy

The unmodified `Studio`, `Playback`, `MusicDetection`, `CaptureRequest`, `AudioTap`, `SampleRing`, access helper and recovery models are compiled together. Test functions replace the Core Audio SDK boundary at compile time. A pre-run symbol audit rejects binaries that still import the real capture/property entry points. Catalog results, hardware facts, motor and keyboard endpoints are also fixtures. Light processing is used; the neural separation implementation is neither linked nor changed.

The host has a unique actual Info.plist bundle identifier and its own preference domain, with failure cleanup. PCM is generated in memory, delivered through the real capture callback/ring and never saved or played over speakers. No contact is called, no microphone is opened, no TCC database/tool is used, and no privacy switch is touched. Output contains fixture categories, counts and error classes, not listening metadata or personal paths. This assesses the state and strings backing the UI, not a new visual or VoiceOver examination.

## What is exercised

| Scenario | Observed/required invariant |
| --- | --- |
| Automatic Spotify/Music, both outputs, FaceTime/telephony/conference identities | Twelve provider/output/identity cycles. An idle call window leaves music active; incoming output, active duplex and input-only call phases pause output and release capture/muting. |
| Call ended, fresh audio withheld | Reconnects without replaying old queued haptics; new output requires fresh PCM. |
| Music source during a call | The fixture's source-frame counter keeps advancing. This checks capture/control isolation, not physical speaker continuity or audible glitches. |
| Haptics off and explicit Stop | Bypass survives a call; ending a call cannot undo Stop. The assist-mode case uses the real toggle action; trackpad-mode restoration uses the real saved-bypass startup path. |
| SDK registration blocked during a mid-song reconnect | A call suppresses output while startup is outstanding. The canceled late connection remains unmuted, is destroyed when the SDK returns, and does not prevent a fresh post-call connection. |
| Thirty rapid call-state changes under CPU load | The final sustained call settles, releases capture and subsequently resumes. The policy polls about every 350 ms, so each 40 ms transition is not individually guaranteed to be observed. |
| Existing callback stops or returns zeros | Automatic routing settles and releases source muting; returning PCM resumes the same listening session. Long silent loss offers Listening help. See the warning limitation below. |
| Old tap invalidated, replacement attempts persistently denied | The real tap/watch/reconnect code reaches capture recovery, releases I/O, retries with bounded backoff and recovers when the fixture permits access again. |
| Explicit access check and Listening help Retry | The real access helper reports “Check System Audio Recording permission, then retry.” Re-grant and Retry clear failed access, preserve the assist-mode bypass choice and recover in the same process. |
| Explicit Spotify/Music routes, both outputs | Stopped/zero PCM and denied reconnects are assessed separately. A reconnect error includes recording-permission guidance, closes capture/muting and permits a new Reconnect in the same process. Silent-loss muting is a separate unresolved finding. |

The injected SDK error is `kAudioDevicePermissionsError`; this tests error handling, **not** a claim that macOS TCC revocation emits that particular code or invalidation notification. Likewise, the fixture's re-grant restores SDK delivery/admission; it does not prove the OS can re-grant a real recording session without relaunch.

## Unresolved acceptance findings

1. **Silent loss has no authoritative permission-specific warning.** Stopped callbacks and zero-filled callbacks leave the recovery model at “Waiting for audio” / “Waiting for music,” with no capture error. Automatic routing releases muting and eventually offers Listening help, but cannot identify permission revocation from silence alone. Genuine music silence can produce the same observation; inferring denied permission solely from it would also be incorrect. Real OS revoke behavior still needs measurement.
2. **Explicit Trackpad only can retain source muting after silent capture loss.** With a surviving explicit-player tap and no SDK error/invalidation, haptics settle but source muting remains until PCM returns or Stop/Reconnect tears down the tap. Automatic routing releases muting in the equivalent fixture case. This is a reproduced app-path difference under fault injection, not evidence that a specific macOS version delivers revocation this way. Production code remains unchanged as requested.

The requested end-to-end acceptance is therefore **not fully clean**. This batch stays on interruption/revocation assessment rather than starting unrelated cleanup. A future fix to explicit-route liveness/muting needs its own reviewed production change; a permission-specific warning needs an authoritative failure signal or carefully worded uncertainty.

## Live verification remains open

The prior [live capture investigation](capture-authorization-1.0.md) found a stale installed-app grant and a separate tap-registration stall even in the matching-grant historical control. This batch does not renew, revoke or reset the installed app's grant. A real working authorized stream plus an operator/test call is still required to assess physical call audio, route transitions and actual OS revoke/re-grant semantics. Simulation cannot turn that existing blocker into a verified live pass. It also cannot establish audible glitch freedom or a universal recovery latency.
