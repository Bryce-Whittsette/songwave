# Building SongWave

SongWave is developed by Bryce Whittsette with AI coding assistance. Bryce drives product requirements, interface direction, listening feedback and acceptance decisions. Codex assists with implementation, investigation and automated checks.

## Product and engineering decisions

- **Follow music already playing.** Links/files are optional. Process taps avoid requiring a virtual audio driver.
- **Give the modes distinct purposes.** Speakers + haptics emphasizes rhythm; Trackpad only follows voice-shaped material.
- **Expose the tradeoff.** Light favors responsiveness and memory use. Isolated uses a bundled model for cleaner vocals with more buffering. Separation is approximate.
- **Make tuning understandable.** Two-finger wheels have a click-to-edit alternative. Monochrome system typography and native controls follow Bryce's selected direction. Each unfamiliar control needs an explanation of what it changes.
- **Keep experiments deliberate.** Ultra follows the current source unless someone selects the demo. Its duration is an app limit, not a hardware safety certification.
- **Measure specific behavior.** Synthetic regressions and DSP benchmarks do not establish whole-app RAM, physical sync or hardware endurance. License, trained weights and native validation are prerequisites for changing the live model.

Recent investigation found a link-route call-suppression gap and a bypass path that skipped its fade. The 0.5.4 candidate adds shared call handling, a timed bypass ramp and mocked session-lifecycle tests. Reproducible bugs and verified fixes are useful evidence of the development process.

Next evidence to collect: a recording of the actual app, physical timing/resource measurements, and first-use observations from people new to the project. Those results are not claimed here yet.

[Architecture](architecture.md) · [Engine decisions](streaming-engine.md) · [Version history](../CHANGELOG.md) · [Credits](credits.md)
