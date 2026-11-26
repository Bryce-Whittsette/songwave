# Mobile feasibility

SongWave's mobile work belongs in this repository. A future iPhone build should bundle its own processing and provide its own setup; users should not need to install Nugget or visit another project to make SongWave work.

The current public release is macOS only. No iPhone release, universal iOS audio capture or reliable custom locked-screen haptics is advertised.

Before committing to a mobile release, test on a physical iPhone:

- Permissioned access to the intended audio sources, including protected streams.
- Custom haptics during app switching, screen lock, interruptions and resume.
- Bluetooth alignment, battery consumption and bounded resource use.
- A normal installation and update path that keeps working on supported iOS versions.

Feature-flag or restore exploits do not themselves demonstrate that these capabilities are available to SongWave. A separate experimental implementation would need evidence for each capability. Supported Core Haptics can render custom patterns; its background restrictions and the lack of the Mac's capture API remain engineering constraints.

Developer references: [Core Haptics lifecycle](https://developer.apple.com/documentation/corehaptics/preparing-your-app-to-play-haptics), [ReplayKit](https://developer.apple.com/documentation/replaykit), [Music Haptics](https://developer.apple.com/documentation/mediaaccessibility/music-haptics). These references are not user installation requirements.
