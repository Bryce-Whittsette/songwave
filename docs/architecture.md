# How SongWave works

SongWave is a native SwiftUI macOS app. Audio analysis and motor scheduling run away from the UI thread. Captured audio stays in bounded in-memory buffers.

## Audio and source selection

`AudioTap.swift` creates per-process Core Audio taps. `MusicDetection.swift` discovers active audio clients, pauses for recognized call apps, and uses Apple's on-device SoundAnalysis classifier to decide when audio resembles music. Known playing tracks in authorized desktop players and the optional YouTube category filter provide additional context. Audio-only recognition can mistake instrumental video intros for music.

The callback copies PCM into a bounded ring. The playback queue consumes recent samples rather than accumulating a recording. Idle polling slows down. Process changes rebuild or reset analysis state, and shutdown releases taps so trackpad-only muting ends.

## Automatic haptics

`Signal.swift` uses Accelerate FFTs, band energy and positive spectral flux to detect rhythmic attacks. Harmonic checks reject many vocal attacks. Adaptive mid/treble thresholds preserve quieter percussion. Detection uses audio sample time; output uses monotonic host time.

`HapticPattern.swift` provides an automatic renderer for every source and both output modes. Speaker mode combines short attacks and bounded release layers. Trackpad mode preserves the vocal harmonic frequencies. A host-time motor envelope keeps attack/release behavior consistent when callback cadence changes. No fixed-tempo loop is laid over live songs.

Output-device latency is queried from Core Audio and used as an estimate. A manual offset can reduce or increase added delay. This is not sample-accurate physical synchronization, and Apple Music's haptic catalog is not used.

## Vocal modes

Light uses a causal harmonic tracker to focus on voice-shaped pitch families. Harmonic instruments can leak through. Isolated runs the bundled two-stem Spleeter model through Core ML and Accelerate, with bounded context, lookahead and output queues. The model loads only for Isolated. Cancellation and source switches invalidate pending output. Separation adds latency, especially during first use.

## Hardware

`Trackpad.swift` uses the undocumented MultitouchSupport actuator interface, following NO SPEAKER. `Effects.swift` uses the undocumented CoreBrightness keyboard interface when available. Built-in Core Haptics reported no supported actuator on the test Mac. Intensity is bounded; Ultra has a duration, cooldown and system thermal-state guard. These are software limits, not actuator temperature measurements or a manufacturer safety certification.

## Optional authored patterns

AHAP 1.0 haptic events and intensity/sharpness curves can override automatic rhythm for a local audio file. They follow that local player's clock. They are not attached to unrelated live songs. Audio events are skipped and waveform paths are never opened. Parsing limits size, event count, overlap, curve points and event duration.

## Metadata and networking

Player details are queried through Apple Events only after optional Automation access is granted. Catalog/artwork requests can go to Spotify, Apple and image hosts. Audio is never sent to those services. See [Privacy](../PRIVACY.md).
