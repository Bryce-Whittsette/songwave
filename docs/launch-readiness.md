# Preparing the broader launch

0.5.3 is a public preview. The 0.5.4 work is a local development candidate until reviewed and published. Readiness means someone new can install, understand, recover, and update the app reliably.

## Independent review baseline

Two AI-assisted reviewer roles assessed the existing preview on November 26, 2026. These are structured opinions, not hiring outcomes, a user study, or tactile-quality ratings.

| Lens | Baseline | Strong evidence | Largest gap |
| --- | --- | --- | --- |
| Hiring director | 6.8/10 | Native audio/DSP work, bounded queues, real model tests, documented tradeoffs | Distribution trust, session failure coverage, and visible ownership |
| First-time consumer | 6/10 | Clear benefit, optional files/links, brief preferences, honest limits | Opening an unnotarized app, confirming first success, and recovery clarity |

The hiring rubric weighted technical depth 30%, validation 25%, maintainability 20%, distribution 15% and documented ownership 10%. The consumer assessment considered installation, onboarding, explanation, recovery and expectations. Neither score has been inflated after code changes without further use.

## Changes prepared in 0.5.4

- Signed Sparkle update checks with installation approval, and a release/feed pipeline that needs no private CI key.
- Shared recognized-call policy for explicit player routes, plus capture/muting cleanup and reconnect tests.
- A host-time user bypass fade, with immediate Stop/call/error behavior retained.
- Separate saved setup and explicit audio-access check state, with Retry and failed-check continuation tests.
- Inline Transient emphasis help and strict Boolean/numeric AHAP validation.

## Remaining launch order

1. **Finish the distribution identity.** Sign with Developer ID, notarize and staple. Verify a clean-account installation and a second update using the same identity. OS permissions remain under macOS control.
2. **Confirm first success.** After access setup, show audio detection and an explicit, short trackpad test. Let the listener confirm a sensation or enter recovery. Make the test silent unless they deliberately select audio. Keep the normal view focused on listening state, mode and intensity; group optional link/file and experimental controls.
3. **Make recovery one place.** Show trackpad availability, capture result, selected app and pause reason with the relevant Retry/Settings action. A privacy-safe diagnostics copy should contain app/build, Mac/OS, output route and error state, excluding song titles, recordings and personal paths.
4. **Collect physical and novice evidence.** Test multiple Apple-silicon MacBooks and supported OS versions, speakers/wired/Bluetooth routes, sleep/wake, app switching, permission denial, calls, keyboard restoration and repeated relaunches. Measure whole-app CPU/RAM/energy and observed sync in both vocal modes. Watch several new users install and reach a working state; record failures before claiming a completion time.
5. **Show the work.** Publish a short recording of the actual app, a compact hardware matrix, clear current limits and the [development decisions](project-decisions.md). Describe Bryce's product/tuning/testing role and AI assistance accurately. A small download/demo page can follow; GitHub release assets should remain the versioned download source.

## Verification scope

**Later reference:** evaluate a stem splitter after the launch work. Compare streaming separation against the current DSP for beat accuracy, vocal leakage, latency, RAM, licensing and offline reliability. This is a research backlog item, not part of the current implementation pass. [Existing engine research](streaming-engine.md).

Offline stress checks exercised concurrent ring buffers with 2.56 million offered samples; extreme/nonfinite PCM across five rates and both modes; 20 minutes of synthetic PCM; malformed links/AHAP; and discontinuous clocks. The DSP-only stress process used about 5.05 MB maximum RSS and processed its synthetic workload in 4.84 seconds. Those numbers do not measure the full app, real-time physical delay, battery life or motor endurance.

Updater tests use a disposable app and separate temporary key. Modified feeds and archives must be rejected; a valid update must replace/relaunch the test app and write its result marker. The production signing key is not exported for those tests. Public-feed automation still needs its first real release run after merge.

[Build/tests](development.md) · [Update pipeline](updates.md) · [Release notes](releases/0.5.4.md)
