# SongWave

Feel the music playing on your Mac through its Force Touch trackpad.

Open SongWave, play music in Spotify, Apple Music, or your browser, and rest a finger on the trackpad. No song link or file needed.

**[Download for Mac — Apple silicon](https://github.com/Bryce-Whittsette/songwave/releases/download/v0.5.4/SongWave-0.5.4-AppleSilicon.dmg)** · [What's new](docs/releases/0.5.4.md) · [Version history](CHANGELOG.md)

Public preview · macOS 14.2 or later · Force Touch trackpad required · Tested on an M4 MacBook Air

## Install

1. Download and open **SongWave-0.5.4-AppleSilicon.dmg**.
2. Drag **SongWave** into the **Applications** folder shown in the window. Open SongWave from Applications.
3. Finish the short setup and allow **System Audio Recording** when prompted. Then play music normally.

This preview hasn't been notarized by Apple. If macOS blocks it, see [the SongWave installation help](docs/troubleshooting.md#macos-wont-open-the-app). If you choose to proceed, first try opening SongWave, then go to **System Settings → Privacy & Security → Open Anyway** and confirm the app name. You can also [build it yourself](docs/development.md).

**Already installed?** Quit SongWave, download the new DMG, and drag SongWave into Applications. Choose **Replace**, then open it again. Your listening preferences stay saved; macOS may ask for audio access again after a preview update. Version 0.5.3 needs this one manual update; from 0.5.4 onward, use **SongWave → Check for Updates…** or allow automatic checks.

## New in 0.5.4

- A visible **Settings** button with five clearly named pages and the **Command-comma** shortcut.
- Clearer text, spacing, light/dark appearance and native glass controls.
- Automatic update checks that ask before downloading and installing.
- Smoother haptic on/off transitions and better audio-access and call recovery.

See [every public version](CHANGELOG.md) for the changes and expandable developer notes.

## Choose how it feels

- **Speakers + haptics:** hear the song normally and feel its rhythm through the trackpad.
- **Trackpad only:** follow the vocals through the trackpad. **Light** is faster and uses less memory. **Isolated** gives cleaner separation with roughly 0.8 seconds of buffering and a brief first-use warmup.

Point at **Intensity** and swipe with two fingers, or click the number for a slider. The waveform in the menu bar toggles speaker-mode haptics. SongWave can keep listening with its window closed and reconnect when it launches.

There's also an editable EQ, optional keyboard-light pulses, and a 45-second **Insane Ultra** burst with a cooldown. Ultra explains its limits before starting. Repeated strong vibration can increase heat and wear; the app's timer is not a manufacturer safety rating.

## Need help?

- [No vibration, permissions, or sync issues](docs/troubleshooting.md)
- [All controls and the optional YouTube filter](docs/guide.md)
- [Report a bug](https://github.com/Bryce-Whittsette/songwave/issues/new/choose)

Music detection and vocal separation are approximate. Some protected audio cannot be captured. Speech and recognized calls pause haptics; non-music video filtering works best with the optional browser filter. The trackpad and keyboard features use undocumented macOS interfaces and may behave differently across Macs or OS updates.

## For developers

[Product decisions and development credits](docs/project-decisions.md) · [Update pipeline](docs/updates.md)

[Build and test](docs/development.md) · [How it works](docs/architecture.md) · [Streaming engine decisions](docs/streaming-engine.md) · [Mobile feasibility](docs/mobile.md) · [Release process](docs/releasing.md) · [Contributing](CONTRIBUTING.md) · [Privacy](PRIVACY.md)

[MIT license](LICENSE). Third-party code and the bundled vocal model retain their [own notices](docs/credits.md). SongWave is an independent project, unaffiliated with Apple or Spotify.
