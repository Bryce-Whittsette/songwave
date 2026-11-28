# Building SongWave

SongWave is developed by Bryce Whittsette with AI coding assistance. Bryce drives product requirements, interface direction, listening feedback and acceptance decisions. Codex assists with implementation, investigation and automated checks.

## Product and engineering decisions

- **Follow music already playing.** Links/files are optional. Process taps avoid requiring a virtual audio driver.
- **Keep output and musical focus independent.** Speakers + haptics and Trackpad only each support Beat, Voice and Both; switching output retains the listener's focus.
- **Expose the tradeoff.** Light favors responsiveness and memory use. Isolated uses a bundled model for cleaner vocals with more buffering. Separation is approximate.
- **Make tuning understandable.** Two-finger wheels have a click-to-edit alternative. Monochrome system typography and native controls follow Bryce's selected direction. Each unfamiliar control needs an explanation of what it changes.
- **Keep experiments deliberate.** Ultra follows the current source and never starts a demo. Its duration is an app limit, not a hardware safety certification.
- **Measure specific behavior.** Synthetic regressions and DSP benchmarks do not establish whole-app RAM, physical sync or hardware endurance. License, trained weights and native validation are prerequisites for changing the live model.

Recent source work covers silent-capture guidance and mute release, malformed input, long-pattern scheduling, diagnostic decoding and capture identity across recycled process IDs. The [validation matrix](validation.md) distinguishes automated checks, live observations and work still open. Source fixes merged after 1.0.0 require a later installer release to reach existing downloads.

Next evidence to collect: the [actual-app recording](launch-recording.md), physical timing/resource comparisons, and first-use observations from people new to the project. Those results are not claimed here yet.

[Architecture](architecture.md) · [Engine decisions](streaming-engine.md) · [Version history](../CHANGELOG.md) · [Credits](credits.md)
