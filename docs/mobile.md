# SongWave for iPhone

**Development prototype — no iPhone download yet.** The public DMG is for Mac. The standalone iPhone project lives here in `Mobile/SongWaveiOS.xcodeproj`; a Mac connection is not required for playback.

## What you can play

| Source | What SongWave does |
| --- | --- |
| Audio files opened inside SongWave | Plays audio with on-device **Beat** or **Voice** haptics. Includes intensity, audio on/off, artwork and progress. Light analysis can include other instruments; this is not AI stem isolation. |
| Apple Music played inside SongWave | Searches and plays songs through MusicKit. Uses Apple's Music Haptics for songs with matched haptic tracks, when enabled and available. Apple controls that haptic mix and intensity. |
| Spotify, YouTube or another iPhone app | Not captured. This build has no universal system-audio capture. |

Custom file haptics require a supported physical iPhone and work while SongWave is on screen. Audible file playback can continue in the background; haptics-only playback pauses there. Native Music Haptics follow Apple's device, setting and track availability. No restore exploit, device modification or helper app is used.

For Apple Music, enable **Settings → Accessibility → Music Haptics**. A subscription and configured SongWave App ID are needed for catalog playback. The app checks the current authorization status rather than asking again on every launch. [Apple's Music Haptics integration](https://developer.apple.com/documentation/mediaaccessibility/music-haptics).

## Run the development build

These steps are for developers testing the prototype. They are not the eventual public installation flow.

1. Install Xcode with an iOS SDK. Open **Mobile/SongWaveiOS.xcodeproj** and select **SongWaveMobile**.
2. Under **Signing & Capabilities**, choose your development team. Change the bundle identifier if testing your own copy.
3. Connect and select a supported iPhone, then click **Run**. Open an audio file inside SongWave and tap **Play**.
4. For Apple Music, register the matching App ID and enable its **MusicKit App Service** in the Apple developer account. No private API or invented MusicKit entitlement is required. [Apple's setup instructions](https://developer.apple.com/help/account/services/musickit/).

Unsigned compile checks, from the repository root:

```sh
xcodebuild -project Mobile/SongWaveiOS.xcodeproj -scheme SongWaveMobile \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

```sh
xcodebuild -project Mobile/SongWaveiOS.xcodeproj -scheme SongWaveMobile \
  -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

## Implementation

The file player shares SongWave's Light DSP sources with the Mac app. The render callback copies PCM into a fixed 32,768-sample ring with a nonblocking lock attempt. A serial 16 ms analysis schedule consumes at most the newest 80 ms, discarding backlog instead of progressively increasing latency. This schedule is not a measured end-to-end latency guarantee.

Analysis and PCM collection stop when hidden, paused, unsupported or at zero intensity. The player caches downsampled cover art, publishes progress at 4 Hz only in the foreground, and does not load the desktop AI model. Files are copied to temporary local storage; there is no audio upload or mobile backend. Temporary imports are cleared on the next launch.

Core Haptics maps detected attacks to transients and bass/voice envelopes to bounded continuous intensity and sharpness. It does not reproduce an audio waveform or promise separate physical pitches. Stop, interruption and source changes invalidate pending operations. Media-services reset recreates the audio graph and requires explicit playback again.

## Before a public beta

- Sign the app with the owner's development team and configure the MusicKit App Service.
- Test physical haptics, comfort, audible/muted playback, repeated source changes, file completion, calls, headphones, lock/unlock and service resets on iPhone.
- Measure whole-app energy and audio-to-touch alignment on speakers, wired output and Bluetooth. Current desktop timing offsets are not iPhone measurements.
- Check VoiceOver, large text and feedback from Deaf and hard-of-hearing listeners. This prototype has no validated accessibility-benefit claim.
- Finish the app icon, first-run guidance, App Store privacy details and distribution review.

The intended easy beta installation is **TestFlight**, with a link from this repository. External testing requires Apple's beta review; there is no public invite link yet. [TestFlight distribution](https://developer.apple.com/testflight/).
