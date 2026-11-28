# What has been checked

SongWave is an experimental Mac app. The table below separates a working local observation from automated coverage and work still to do.

**Download versus source:** the public Mac installer is **1.0.0, build 24**. Later fixes merged into `main` are source changes until a new installer/update is published. The [version history](../CHANGELOG.md) lists public releases; the [merged pull requests](https://github.com/Bryce-Whittsette/songwave/pulls?q=is%3Apr+is%3Amerged) show repository work.

## Hardware and playback

| Area | Evidence | Remaining limit |
| --- | --- | --- |
| M4 MacBook Air, Mac16,13; macOS 27.3 beta, 26C5047e | November 28: installed 1.0.0 detected generated music through real system capture on the built-in 48 kHz output route. Signal level and recent beats were visible, including with haptics off. | One Mac/OS combination. No physical audio-to-touch latency or subjective sensation rating. |
| Concurrent local sources and Ultra | Two bounded 65-second trials, each with 22 local player launches, overlapping player processes, two CPU workers, and a normal 45-second Ultra request. Normal UI state and test-process cleanup were verified. | Synthetic local players, not a live Spotify/Music/browser handoff. No continuous glitch measurement or motor-endurance claim. |
| Spotify, Music and browser handoff logic | Production capture/ring/router/playback/driver code passes SDK/actuator-boundary fixtures, including overlapping sources, retired callbacks, PID replacement and muting cleanup. [Report](audits/overlap-focus-1.0.md). | Live provider-to-provider switching and physical foreground-app stress remain unverified. |
| Other sample rates and malformed input | Automated metadata tests cover 16 rates from 8–768 kHz. Real callback/ring/playback integration at 8/192 kHz passes with intercepted SDK/output calls. [Report](audits/audio-edges-1.0.md). | These are not measurements from physical 8/192 kHz devices. |
| Wired, Bluetooth, external trackpads, other Macs/OS versions | Route/rate changes and recovery have injected regression coverage. | A physical compatibility matrix is still needed. macOS 14.2 is the API minimum, not proof of testing on every later version. |
| iPhone | Unsigned Simulator/device compilation and bounded queue/core tests. [Status](mobile.md). | No public iPhone app. Developer signing, service setup and physical testing remain. |

## Reliability, access and accessibility

| Area | Checked | Still open |
| --- | --- | --- |
| Setup and recovery | Explicit sensation-confirmation flow, typed capture state, retry/cancellation and privacy-safe diagnostics are regression-covered. | New-listener completion rates and physical first-success testing. |
| Lost capture and calls | Disposable fixtures exercise stopped/zero PCM, denied requests, late startup, call state, mute release and recovery. [Scope](audits/call-permission-1.0.md). | Real calls and OS permission revoke/regrant. The historical registration stall is not proven resolved across sessions. |
| Visual rhythm and native accessibility | Separate beat/level feedback, haptics-off visibility, reduced motion, native roles/labels and navigation checks. [Details](accessibility.md). | Deaf/hard-of-hearing listener feedback and assistive-technology user testing are still needed to assess clarity, comfort and usefulness. |
| Installation and updates | Signed feed/archive validation, full/delta verification, approval-before-install, network-failure and disposable disk-full tests. | Developer ID, notarization/stapling and clean-account installation with a stable identity. [Roadmap](launch-readiness.md). |
| Energy and heat | Avoided UI work has automated coverage. Local stress observations and measurement limits are recorded in the audit reports. | Controlled whole-app comparisons, battery measurements and sustained thermal profiling. [Protocol](energy.md). |

Music recognition and separation are approximate; protected audio can be silent. The undocumented trackpad/keyboard interfaces can change with macOS. Ultra's duration and cooldown are app limits, not Apple's hardware safety rating.

[Install/help](../README.md) · [Developer tests](development.md) · [Privacy](../PRIVACY.md) · [Report a problem](https://github.com/Bryce-Whittsette/songwave/issues/new/choose)
