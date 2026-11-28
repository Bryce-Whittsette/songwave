# SongWave

Feel the music playing on your Mac through its Force Touch trackpad.

Open SongWave, play music in Spotify, Apple Music, or your browser, and rest a finger on the trackpad. No song link or file needed.

**[Download for Mac — Apple silicon](https://github.com/Bryce-Whittsette/songwave/releases/download/v1.0.0/SongWave-1.0.0-AppleSilicon.dmg)** · [What's new](docs/releases/1.0.0.md) · [Version history](CHANGELOG.md)

macOS 14.2 or later · Force Touch trackpad required · Tested on an M4 MacBook Air

## Install

1. Download and open **SongWave-1.0.0-AppleSilicon.dmg**.
2. Drag **SongWave** into the **Applications** folder shown in the window. Open SongWave from Applications.
3. Finish the short setup and allow **System Audio Recording** when prompted. Then play music normally.

This app hasn't been notarized by Apple. If macOS blocks it, see [the SongWave installation help](docs/troubleshooting.md#macos-wont-open-the-app). If you choose to proceed, first try opening SongWave, then go to **System Settings → Privacy & Security → Open Anyway** and confirm the app name. You can also [build it yourself](docs/development.md).

**Already installed?** Choose **SongWave → Check for Updates…** and approve the update. SongWave checks about once an hour; you choose when to download and install. Your listening preferences stay saved. Version 0.5.3 and earlier need one manual DMG installation to get the updater. [Update help](docs/updates.md).

## New in 1.0

- Smaller signed updates where possible, with hourly checks and approval before installation.
- A calmer Beat cue, stable listening text and an Ultra glow in Signal Monitor.
- Updated setup and a one-time orientation for existing listeners.
- Better continuity during macOS Dictation, low-bass tracking and recovery fixes.

See [every public version](CHANGELOG.md) for changes and developer notes.

## Choose how it feels

Choose **Beat** for bass and percussion, **Voice** for vocal pitch and texture, or **Both** to blend them. All three work with **Speakers + haptics** or **Trackpad only**. Changing the output keeps your selected focus.

**Light** uses fast audio analysis. **Voice → Trackpad only → Isolated** uses the existing bundled AI vocal model: cleaner separation, higher memory use and roughly 0.8 seconds of buffering. Both and other combinations use Light; no new separation model has been added. Voice focus can be quiet during instrumental passages. Recognition and tactile detail vary with the mix and hardware.

Point at **Intensity** and swipe with two fingers, or click the number for a slider. The waveform in the menu bar toggles speaker-mode haptics. SongWave can keep listening with its window closed and reconnect when it launches.

Open **Tools… → Sound** for genre and Fine Tune, **Trackpad EQ** for the editable bands, or **Experiments** for keyboard-light pulses and a 45-second **Insane Ultra** burst with a cooldown. Ultra explains its limits before starting. Repeated strong vibration can increase heat and wear; the app's timer is not a manufacturer safety rating.

## Music through touch and sight

SongWave explores another way for deaf and hard-of-hearing listeners to connect with music through touch and visual rhythm. Haptics follow musical texture, while an on-screen beat and level indicator provides visual feedback. Voice, Beat and Both choices let listeners choose which part of the music to follow.

Accessibility is a design goal, and we haven't yet validated the experience with deaf or hard-of-hearing users. [Accessibility checks](docs/accessibility.md) describe our automated coverage and remaining listener testing. [Feedback on comfort, clarity and useful controls](https://github.com/Bryce-Whittsette/songwave/issues/new/choose) will help guide the work.

## iPhone development

A standalone iPhone prototype is now in this repository: local audio with Voice/Beat/Both feedback, plus Apple Music playback with Apple's available haptic tracks. **No iPhone download yet**; signing and physical-device testing are still required. It does not capture Spotify or audio from other iPhone apps. [Supported sources and beta preparation](docs/mobile.md).

## Need help?

- [No vibration, permissions, or sync issues](docs/troubleshooting.md)
- [All controls and the optional YouTube filter](docs/guide.md)
- [Report a bug](https://github.com/Bryce-Whittsette/songwave/issues/new/choose)

Music detection and vocal separation are approximate. Some protected audio cannot be captured. Speech and recognized calls pause haptics; non-music video filtering works best with the optional browser filter. The trackpad and keyboard features use undocumented macOS interfaces and may behave differently across Macs or OS updates.

## For developers

[Product decisions and development credits](docs/project-decisions.md) · [Validation and current limits](docs/validation.md) · [Update pipeline](docs/updates.md)

[Build and test](docs/development.md) · [How it works](docs/architecture.md) · [Streaming engine decisions](docs/streaming-engine.md) · [iPhone prototype](docs/mobile.md) · [Energy work and measurements](docs/energy.md) · [Release process](docs/releasing.md) · [Contributing](CONTRIBUTING.md) · [Privacy](PRIVACY.md)

[MIT license](LICENSE). Third-party code and the bundled vocal model retain their [own notices](docs/credits.md). SongWave is an independent project, unaffiliated with Apple or Spotify.
