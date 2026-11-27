# Changelog

Every public release is listed here, newest first. Each version has a short explanation and expandable developer notes.

## [0.5.12 — Visual listening](docs/releases/0.5.12.md)

Public Preview · November 27, 2026

Clearer Beat and Music level feedback at the top of the main Signal Monitor, including while haptics are off. One level bar retains percentage/dB readings; larger bounded pulse, reduced-motion text feedback and compact-window checks. Audio isolation and haptic rendering are unchanged.

[Download](https://github.com/Bryce-Whittsette/songwave/releases/tag/v0.5.12) · [Full notes and validation](docs/releases/0.5.12.md)

## [0.5.11 — Connection and recovery](docs/releases/0.5.11.md)

Public Preview · November 27, 2026

Connection retries stay in one place, recovery opens at the top, local files retain position and bypass, and audio detection no longer implies music is still playing after it stops. Expanded native setup/recovery and grouped-control tests.

[Download](https://github.com/Bryce-Whittsette/songwave/releases/tag/v0.5.11) · [Full notes and validation](docs/releases/0.5.11.md)

## [0.5.10 — Clarity and accessibility](docs/releases/0.5.10.md)

Public Preview · November 27, 2026

Native accessibility checks for setup and recovery, motion reduction without losing visual feedback, and a clearer percussion accent in Both. The isolation engine stays unchanged.

[Download](https://github.com/Bryce-Whittsette/songwave/releases/tag/v0.5.10) · [Full notes and validation](docs/releases/0.5.10.md)

## [0.5.9 — First connection](docs/releases/0.5.9.md)

Public Preview · November 27, 2026

An explicit first-success check, unified Listening help with privacy-safe diagnostics, a visual beat/level indicator, and a focused player with grouped Sources and Tools.

[Download](https://github.com/Bryce-Whittsette/songwave/releases/tag/v0.5.9) · [Full notes and validation](docs/releases/0.5.9.md)

## [0.5.8 — Energy and detail](docs/releases/0.5.8.md)

Public Preview · November 27, 2026

Mac build 18. iPhone source prototype 0.1.0 (1) is not a mobile release.

- Add **Feel → Both** to blend Voice and Beat using the shared Light analyzer.
- Reduce hidden-player visual work and cache Messages service discovery. Battery savings still need a controlled playback comparison.
- Add Beat detail balance, bringing detected mid/treble accents forward against bass rumble.
- Keep Trackpad-only intensity independent of muted speaker volume.
- Add an unsigned standalone iPhone prototype for local-file Voice/Beat/Both haptics and Apple Music's matched haptic tracks. No mobile download yet; see [mobile status](docs/mobile.md).

[Download](https://github.com/Bryce-Whittsette/songwave/releases/tag/v0.5.8) · [Full notes](docs/releases/0.5.8.md)

<details>
<summary>Developer notes</summary>

Display tests cover 10,000 hidden packets with no visual publications and fresh/stale resume. Mobile tests exercise bounded recent PCM and analysis-suspension policy. Simulator/device compile checks do not establish physical haptic quality, latency or energy use. The existing AI isolation engine is unchanged.

</details>

## [0.5.7 — Voice and Beat](docs/releases/0.5.7.md)

Public Preview · November 26, 2026

Independent Voice/Beat selection, a lower Beat silence gate for soft percussion, and Voice-aware output timing. The existing AI isolation engine is unchanged.

[Download](https://github.com/Bryce-Whittsette/songwave/releases/tag/v0.5.7) · [Full notes](docs/releases/0.5.7.md)

## [0.5.6 — Your music only](docs/releases/0.5.6.md)

Public Preview · November 26, 2026

Removed the built-in demo, Ultra demo option and generated audio playback. SongWave follows Mac audio or your chosen file.

[Download](https://github.com/Bryce-Whittsette/songwave/releases/tag/v0.5.6) · [Full notes](docs/releases/0.5.6.md)

## [0.5.5 — Ultra response](docs/releases/0.5.5.md)

Public Preview · November 26, 2026

Stronger Ultra response with a temporary internal EQ, lifted accents and stronger beat lighting. Saved controls stay unchanged. The 45-second timer and existing interruption limits remain.

[Download](https://github.com/Bryce-Whittsette/songwave/releases/tag/v0.5.5) · [Full notes](docs/releases/0.5.5.md)

## [0.5.4 — Settings and updates](docs/releases/0.5.4.md)

Public Preview · November 26, 2026

- Visible Settings, clearer typography and contrast, native glass controls and consistent light/dark appearance.
- Signed in-app updates with automatic checks and approval before installation.
- Smoother haptic bypass, call handling for song-link routes and clearer audio-access recovery.
- Precision-entry validation, tuning help and stricter AHAP numbers.

[Download](https://github.com/Bryce-Whittsette/songwave/releases/tag/v0.5.4) · [Full notes and developer details](docs/releases/0.5.4.md) · [Code changes](https://github.com/Bryce-Whittsette/songwave/compare/v0.5.3...v0.5.4)

## [0.5.3 — Bass sustain](docs/releases/0.5.3.md)

Public Preview · November 26, 2026

- Added soft low-bass rumble alongside individual percussion taps in Speakers + haptics.
- Added **Bass sustain**, including zero for taps only.
- Made **Transient emphasis** shape each tap's fade: rounder at low settings, crisper at high settings.
- Added tests for bass response, vocal rejection, stopping and suppression. Kept installation help and engine plans within SongWave's docs.

[Download](https://github.com/Bryce-Whittsette/songwave/releases/tag/v0.5.3) · [Full notes and developer details](docs/releases/0.5.3.md) · [Code changes](https://github.com/Bryce-Whittsette/songwave/compare/v0.5.2...v0.5.3)

## [0.5.2 — First public preview](docs/releases/0.5.2.md)

Public Preview · November 25, 2026

- Automatic haptics from music playing on the Mac, without a file or song link.
- Speakers + haptics with shaped rhythmic attacks and releases.
- Vocal-focused Trackpad only, with Light and on-device Isolated choices.
- Trackpad EQ, timing adjustment, volume following and menu-bar controls.
- Optional keyboard-light pulses and a timed 45-second Ultra mode.
- Saved setup/output mode and automatic launch listening.
- Optional local-file AHAP haptic layers and YouTube category filtering.

Apple silicon build, macOS 14.2 minimum, tested on an M4 MacBook Air. This is an unnotarized preview. Private hardware interfaces, music recognition and separation have compatibility and accuracy limits.

[Download](https://github.com/Bryce-Whittsette/songwave/releases/tag/v0.5.2) · [Full notes and developer details](docs/releases/0.5.2.md)

Earlier builds were local prototypes, not public releases. Their work became the 0.5.2 baseline; there are no archived public downloads for those versions.
