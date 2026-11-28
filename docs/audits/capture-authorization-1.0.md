# Live capture authorization and interruption follow-up

**Later countercheck, November 28:** installed 1.0.0 captured synthetic local music during the [overlap/focus pass](overlap-focus-1.0.md), without a permission or signing change. The registration stall below is historical evidence, not a permanent current blocker. Its underlying cause and recurrence across sessions remain unresolved.

There are two findings on the test Mac. The installed 1.0.0 release has an authorization blocker: macOS's saved System Audio Recording requirement matches the **published 0.5.13 binary**, while installed 1.0.0 has a different requirement. Separately, the unchanged, matching-grant 0.5.13 control also stalled in tap I/O registration. Output-only HAL registration worked on the same Mac. The complete server-side cause of the tap-path wait remains unresolved.

Renewing 1.0.0's grant requires the owner's Touch ID/password. A valid current grant is necessary for its live countercheck, but the historical control shows that renewing access cannot yet be promised as the complete fix. Inspecting the audio server requires privileges unavailable in this session.

## What was observed

Testing used the Apple-silicon MacBook Air, macOS 27.3 build 26C5047e, built-in speakers at 48 kHz. No audio recordings, microphone capture, external calls or motor output were used by the diagnostic probes. Only API stages, elapsed time, callback/byte counts and aggregate signal levels were logged locally.

| Check | Result |
| --- | --- |
| Tap metadata, without starting I/O | Tap creation and format reads succeeded. The returned UID matched the description UUID. The format was valid 48 kHz, stereo Float32 with 8 bytes/frame. The tap was destroyed afterward. |
| Unmodified installed 1.0.0 | Sampled waiting in `AudioDeviceCreateIOProcIDWithBlock` → `HALC_ProxyIOContext::_TellServerAboutStreamUsage` → synchronous Mach IPC. The earlier pass had also sampled `AudioDeviceStart`. The wait is before classifier, isolation or haptic rendering. |
| Active playback | Resumed the local Spotify player and confirmed its Core Audio output-running flag. The installed release still stalled at I/O registration. Playback was paused afterward and haptics were disabled during observation. No song metadata is included here. |
| Unchanged public 0.5.13 control | Extracted the previously verified archive without installing or re-signing it; strict signature verification passed and its original requirement matched the saved grant. `tccd` reported `authValue=2`, `authReason=2`, no error and no requirement mismatch for that request. While Spotify played, this version also waited in `_TellServerAboutStreamUsage` during tap I/O registration. Haptics stayed off. This rules out the 1.0.0 grant mismatch as the sole explanation. |
| Minimal diagnostic app using production `AudioTap` | Removed the player, classifier, model and motor from the experiment. Tap/format/aggregate creation completed; I/O registration waited with zero callbacks. A foreground run behaved the same; no permission prompt appeared. Runs terminated after 30 seconds. |
| Disable aggregate tap-autostart waiting | The one-variable diagnostic still waited at I/O registration with zero callbacks for 30 seconds. It was not adopted. |
| Output-only clock anchor from the preceding pass | That trial did not establish working capture. The authorization mismatch now identified also confounds conclusions drawn from rebuilt diagnostic apps. No clock-anchor change was adopted. |
| Output-only physical-device control | Verified the selected speaker device had zero input streams. Registered and started silent output I/O using the same block callback API and a serial queue, with no process tap or aggregate and no captured input. Registration returned in about 0.3 ms, start in about 16 ms, and 1,157 callbacks arrived over 12 seconds. No default route was changed. |
| Live bounded access check | A temporary diagnostic using the new production access-check code and a two-second test deadline returned its unfinished-capture message after about 2.06 seconds while I/O registration remained blocked. UI remained responsive. The production deadline is 60 seconds; no permission was granted by the diagnostic. |

The SDK describes tap autostart as waiting for the first tapped audio. That can matter during silence, but disabling it did not resolve this registration wait. Apple's [Core Audio tap sample](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps) requires System Audio Recording access and an audio-capture usage description; SongWave's description is present.

## Authorization evidence

The audio server's request for the unchanged installed app was correlated by process and timestamp with this macOS `tccd` message:

> Failed to match existing code requirement for subject studio.songwave.trackpad and service kTCCServiceAudioCapture

Read-only `codesign -d -r-` inspection of the previously verified public 0.5.13 archive's executable and the installed 1.0.0 app confirmed:

- The saved requirement in the OS rejection matches 0.5.13 exactly.
- Installed 1.0.0 has a different, hash-based designated requirement.
- System Settings nevertheless shows SongWave's System Audio Recording Only switch as **On**.

Apple explains how designated requirements identify [updates and upgrades](https://developer.apple.com/library/archive/technotes/tn2206/_index.html). The observed OS rejection establishes that the existing grant does not match this installed binary. Sparkle's verified archive/feed signatures serve a separate purpose; they do not repair an OS permission grant. See [Updates](../updates.md).

Clicking SongWave's switch required Touch ID/password **before applying a change**. Authentication was canceled, and the switch was verified still On. No permission database, code requirement, signing identity, notarization configuration or security setting was changed. Raw local traces contain process paths and remain outside the repository; this report omits them, code hashes and listening metadata.

The owner must renew System Audio Recording access for the **current installed app**, relaunch if macOS requests it, and verify nonzero audio in SongWave's setup check. That countercheck is blocked until owner authentication is available. Future distribution-identity work remains outside this batch's scope.

Sampling the client identifies synchronous IPC to the audio server, but does not identify what the server is waiting for. A read-only attempt to sample `coreaudiod` was denied for insufficient privileges. No elevated command, audio-server restart, driver removal, system-input shutdown or permission reset was attempted. Those would change the host state or require owner participation. A valid-current-grant test and owner-supervised server/clean-session investigation are still needed before selecting a routing workaround. In particular, the minimal rebuilt probes' empty input cannot validate a new capture configuration while their grants do not match.

## Safe app-side correction

The explicit access check used a separate detached task that could wait indefinitely in Core Audio. Its opening phase now shares listening's four-worker admission limit, including the preparatory process-list query, and uses a 60-second wait deadline with a recovery message for an unfinished check. Task or request cancellation ends the wait; a canceled late metadata query cannot start another tap. Checks remain unmuted and non-actuating.

This deadline limits the app's wait, not the OS call itself. A blocked system call cannot be forcibly interrupted by this mechanism; four stuck calls still exhaust admission until they return or the app restarts. The new code does not infer permission denial from silence or claim that opening a tap proves audio is flowing. First-success verification still requires audio detection and the listener's explicit sensation confirmation.

`Tests/CaptureAccessRegression.swift` exercises the production access-check and handoff code with fake HAL boundaries: success, SDK error propagation, timeout, task/request cancellation, late cleanup, self-exclusion, no muting, shared admission and a blocked process-list read. It requests no OS permission.

## Sleep, idle and interruption coverage

| Area | Evidence and remaining limit |
| --- | --- |
| Sleep/wake notification wiring | Production `MenuController` and `Studio` now receive injected `NSWorkspace` notifications in the controller suite. Checks cover duplicate attachment/notifications, one bypass-preserving resume, ignored pre-sleep callbacks, explicit Stop, retained file position and failed-access suppression. These notifications affect the test process only. |
| Long idle | The preceding two-hour wall-clock soak passed on the async-capture prototype with fake I/O; continuous-clock tests cover jumps through 24 hours. This remains backend evidence, not a physical sleep or authorized live-capture endurance pass. |
| Physical sleep/wake | Not performed unattended. This session runs as user 501. Apple's supported [wake-event scheduling API requires root](https://developer.apple.com/documentation/iokit/1557076-iopmschedulepowerevent); a controlled wake/operator route is unavailable without additional owner involvement. Existing power events were inspected read-only, and no schedule or power setting was changed. The Mac was not forced asleep with no controlled return path. |
| Call interruption | The unchanged real model now runs through a simulated FaceTime interruption: capture/muting release, no queued separated output during interruption, and resumed output afterward. Existing explicit-player tests cover both providers, outputs and focus choices. No real call was placed. A working authorized capture stream is still needed for the live countercheck. |
| Lost capture mid-session | The real-model stress test stops PCM while the source remains active, checks bounded settling and released muting, then verifies explicit recovery. This models a possible permission-revocation symptom or driver stall; it does not establish actual OS revocation behavior. |
| Live permission revocation | Blocked by owner authentication and the initial mismatched grant. Revoking a working stream cannot be validated before the current app has working authorization. The protected toggle attempt was canceled without changing access. |

Run `bash Tests/run.sh` and `bash Tests/test-isolation.sh` for repeatable coverage. The latter uses the existing model unchanged and fake capture/actuator edges.

The optional model job exposed test scheduling dependencies: its exact-sample-count check used wall time, so a delayed CI task could trigger the engine's intentional stale-audio discard or exhaust the five-second drain budget. That numerical/resampling check now advances timestamps by source frames and allows up to 30 seconds for loading/draining. The mode/interruption fixture had also supplied only 8 ms of audio per read regardless of elapsed capture time, underfeeding the real model when the consumer used a slower timer or CI delayed a read. Its fake capture now follows elapsed time with a bounded 80 ms reserve, and cold model startup/resume uses the same 30-second test budget with observed recovery time printed. The separate mode/interruption stress still uses real time under CPU load; these are functional test budgets, not a latency guarantee. No model or rendering implementation changed.

Disk-full installation and wall-clock/timezone offset checks were not advanced under this task's conditional third priority: live authorization, physical sleep and live interruption checks are not yet fully clean. No binary release or public-feed update is part of this batch.
