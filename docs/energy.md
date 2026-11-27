# Energy and responsiveness

Mac 0.5.8 reduces avoidable interface work while keeping audio analysis and haptic timing independent of the window.

## Changes

- Discover the Messages sharing service once per process, rather than during repeated SwiftUI player updates. A sample of the installed 0.5.7 app showed repeated ShareKit/XPC discovery on its main thread.
- Pause signal-monitor publications and visual animation schedules when the player is hidden, minimized, covered or inactive. Keep only the latest packet and resume without replaying old frames.
- Continue audio capture, detection and haptic output independently. The energy fix does not slow the motor scheduler or add a larger analysis buffer.
- On iPhone, stop custom analysis and PCM collection in the background, while paused, at zero intensity or on unsupported hardware. Artwork is downsampled and cached; foreground progress updates four times per second.

An offline regression delivered **10,000 packets** to the hidden display without visual/object publications. It also checks foreground interpolation, fresh/stale resume and cancellation of release animations. This establishes avoided UI work, not a battery-life improvement.

## Measurement status

An initial sample of the installed Mac 0.5.7 build during playback observed roughly **29% CPU** and **142 MB physical footprint** on an M4 MacBook Air running macOS 27.3 beta. It was one active session, not a controlled battery benchmark. RSS and physical footprint are different measures.

The new build has not yet been measured in the same playback conditions. There is no claimed percentage saving or guarantee that macOS's “significant energy” notice disappears. The existing AI vocal model is unchanged and remains more expensive than Light analysis.

## Compare builds

Use the same Mac, OS, output route, volume, power state, song and selected focus. Record the exact build number and whether Light or Isolated is selected. Do not compare a silent source against music playback.

For each build, observe five minutes after settling:

| State | Record |
| --- | --- |
| Listening, player visible | CPU, Energy Impact, memory, observed audio-to-touch alignment |
| Listening, window hidden/minimized | Same values; haptics should continue |
| Paused/stopped | CPU and wakeups should settle; no actuator output |
| Voice + Isolated | Model memory and processing overhead separately from Light |

Use Activity Monitor's CPU, Memory and Energy tabs for whole-app observations; use Instruments' Time Profiler and energy tools for attribution. Note that Energy Impact is relative and does not directly predict hours of battery life. On iPhone, repeat with a signed physical-device build; Simulator compilation does not measure its motor or battery.

Apple recommends reducing periodic work when inactive: [Work when active](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/WorkWhenActive.html), [Timers](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html).
