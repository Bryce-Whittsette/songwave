# Using SongWave

## First connection and recovery

New-user setup continues to System Audio Recording access, then a first connection check. Play a song and watch **Audio detected** and the music-level meter. Automatic haptics remain paused and speakers unmuted during this check. **Test trackpad** explicitly runs three brief taps without generated speaker audio. **I felt it** records your confirmation; **I didn’t feel anything** opens Listening help. You can continue without confirmation and run the check later. Existing users do not repeat setup automatically.

**Listening help** in the player or **Settings → Listening Help** shows trackpad availability, capture result, selected app and listening/pause state. Each has Retry or Settings actions. Retries preserve call, speech and video filtering. **Copy diagnostics** copies only app/build, hardware model, OS, output transport, app category and categorical states. It excludes song titles, filenames, personal paths, device names and recordings, and sends nothing automatically.

The monochrome **Beat / Level** indicator shows analyzed music activity alongside the signal monitor. It does not prove physical actuator motion. Text and accessibility labels accompany the graphic; Reduce Motion keeps pulse size and brightness fixed and removes animated interpolation while preserving level and recent-beat text. Visibility-aware scheduling pauses visual animation when hidden. [Accessibility checks and remaining listener validation](accessibility.md).

## Playback and tuning

- **Trackpad only** mutes captured audio while the trackpad follows your selected Voice, Beat or Both focus. Voice focus follows vocals through the Force Touch motor. For **Voice + Trackpad only**, choose **Light** for fast vocal focus with low memory use; instruments that resemble a voice can leak through. Choose **Isolated** for cleaner vocals using a bundled Spleeter model. It processes audio on your Mac, adds about 0.8 seconds of buffering, and uses more memory. Its first use includes a brief model warmup. Instrumental passages can be quiet in Voice; choose Beat or Both to include percussion. Separation is approximate in dense mixes.
- **Speakers + haptics** leaves the full mix on the speakers. With **Feel → Beat**, the trackpad and keyboard use detected kick and percussion attacks, with softer accents for quiet midrange and treble details and a short fade between hits. Harmonic vocal attacks are filtered. Dense mixes can still produce missed or false beats.
- **Other sources · link or file → Open audio file…** plays a local audio file. **Open & Route** opens a Spotify or Apple Music link in its desktop app. Press **Play** there if needed. Allow **System Audio Recording** when macOS asks, then retry routing.
- **Tools… → Trackpad EQ** adjusts bass, mid, and treble. Point at a value and swipe up or down with two fingers. A single click opens a slider, plus/minus buttons and a field for typing the exact number. Editing a bypassed band turns the EQ back on. **Band Settings** sets each band’s center frequency and width. **Tools… → Fine Tune → Bass sustain** adjusts the low-bass continuous layer for Beat and Both, including zero for taps only. **Tools… → Fine Tune** controls vocal pitch smoothing and how many vocal harmonics to keep for Voice and Both, and output timing in Speakers + haptics. **Match audio output timing** uses the selected output’s reported latency. **Timing offset** fine-tunes that estimate. Positive values make haptics later, and negative values reduce the added delay.
- **Genre** applies a new starting curve. **Settings → General → Listening preferences** lets you change bass or clarity preference. Manual EQ edits take effect immediately.
- **Follow Mac Volume** adjusts haptic strength in Speakers + haptics using the selected output’s volume. Trackpad only always uses manual intensity, even when speaker volume is muted. Fixed-level outputs also keep manual intensity.
- **Sync Keyboard Light** pulses a supported MacBook’s white backlight from the same detected beats as speaker-mode haptics, then fades close to dark between hits. SongWave restores its previous brightness when the effect stops. macOS may suppress lighting in bright environments.
- **Insane Ultra** adds timed haptic accents and a rainbow progress bar for up to 45 seconds. Ultra follows the current source and waits quietly during silence. Keyboard lighting is a separate choice in the start sheet. Stop early with **Stop Ultra**. A one-minute cooldown applies after a burst. Repeated vibration may increase heat and mechanical wear. Effects on adhesives and fasteners are unverified. The timer is an app limit, not a manufacturer safety rating.
- **Share** opens a prefilled Messages draft or copies the project’s GitHub link.

SongWave applies the EQ to the trackpad. The signal monitor shows the filtered signal. Spotify and Apple Music link previews display catalog artwork when it’s available. Albums and playlists show the linked item’s cover. Local files use embedded artwork if present.

With automatic **Beat** or **Both**, **Tools… → Fine Tune → Transient emphasis** changes how quickly a detected percussion hit fades. Lower values leave a longer, rounder tail; higher values make it shorter and crisper. The initial hit strength stays the same. This control does not change detection sensitivity, beat timing, the separate Bass sustain layer, or imported AHAP curves.

## Automatic haptics

Open SongWave and play music in Spotify, Apple Music, your browser, or another audio app. **Mac Audio** follows the playing music automatically. There is no file, link, or pattern to import. Choose **Feel → Voice**, **Beat**, or **Both** independently of output. Voice follows vocal texture, Beat follows bass and percussion, and Both blends them. Both uses Light analysis; Isolated remains available for Voice with Trackpad only. Speech, calls, and supported non-music video filtering still pause output. Capture availability and music recognition can vary by app.

The labeled **Settings** button and **Command-comma** open a browsable settings window. **Keyboard light**, **Follow Mac volume**, genre, EQ, Fine Tune, Ultra and local-file patterns are grouped in **Tools…**. In speaker mode, the **Haptics** switch fades trackpad output on/off while music continues; **Stop listening** ends automatic capture.

The automatic renderer runs on every audio source and both output modes. Its attack and release levels use elapsed host time, so changing audio callback cadence does not change the fade speed. It adds no lookahead buffer; Isolated retains its own vocal-separation buffer.

## Optional custom file patterns

Live speaker-mode percussion uses separate transient and release envelopes. This shapes each detected hit without adding a lookahead buffer or loading the vocal model.

For authored haptics, open a local audio file, choose **Speakers + haptics**, then choose **Tools… → Attach Pattern…**. The pattern replaces automatic percussion for that file and follows its current playback position. Replay the file to hear the pattern from the beginning. **Use Automatic** restores automatic detection. A different source clears the attachment.

The supplied [120 BPM example](../Examples/120bpm.ahap) can be attached to your matching local audio loop. Its embedded audio reference is skipped.

The AHAP 1.0 adapter supports `HapticTransient`, `HapticContinuous`, intensity curves and sharpness curves. Curve point times are relative to the curve start. Intensity control multiplies intensity; sharpness control adds to sharpness. The trackpad approximates sharpness by blending tactile frequencies. Imported audio events are skipped and their waveform paths are never opened. Audio playback stays with the local file you chose. Pattern timing follows the local player's clock with the selected output-delay compensation; it does not promise sample-accurate physical actuation.

Patterns are limited to 1 MB, 4,096 entries, 256 curves, 256 points per curve, 32 overlapping events, a one-hour timeline, and continuous events of at most 30 seconds. These are software bounds, not a hardware safety certification. AHAP attachments are session-only and are not applied to Spotify or browser playback.

The Mac build does not integrate Apple's Music Haptics catalog; the separate [iPhone prototype](mobile.md) uses Apple's supported integration. Core Haptics reports no built-in haptic support on the tested Mac, so SongWave retains its existing trackpad driver. No coil-temperature sensing, braking control, Apple-authored tracks or undocumented Music Haptics services are claimed. See [Apple's AHAP format](https://developer.apple.com/documentation/corehaptics/representing-haptic-patterns-in-ahap-files) and [Music Haptics integration](https://developer.apple.com/documentation/mediaaccessibility/music-haptics).

## Music detection

Mac Audio listens for music on-device. Speech and recognized call apps, including FaceTime, pause haptics. Detection needs a moment when a song starts. On audio alone, an instrumental intro to a spoken video can sound like a song.

For category-aware YouTube filtering, open **Settings → Effects → YouTube music filter**. Follow the steps for Chrome or Firefox. The filter uses the playing video’s YouTube category and pauses haptics for other categories and ads. Safari uses audio recognition. Firefox’s temporary add-on needs to be loaded again after a browser restart.

SongWave reads playback position and duration from Spotify, Music, local files and the optional YouTube filter. Other live sources show signal activity. The current title and artwork appear when available. Optional player access is requested from **Settings → Listening Help**. SongWave can read the current track after you connect the player there. Sources without track details show the playing app. Choose **System**, **Light**, or **Dark** in **Settings → General**. Native Liquid Glass is available on macOS 26 and later.

Routing works with audio macOS makes available for capture. Some protected streams may be silent. Local files need no capture permission. Trackpad playback uses an undocumented macOS interface and was tested on an M4 MacBook Air. Audio is processed on-device and stays in bounded memory. Light and Speakers + haptics do not load the vocal-separation model.

The genre adjustments are modest, editable starting points designed for this trackpad. Personal taste informed the choice to offer an independent bass or clarity preference. [McMullin’s bass-preference study](https://aes.org/publications/elibrary/elibrary-page/?id=19252) and [listening tests across five genres](https://www.mdpi.com/2624-599X/4/3/45) studied audible EQ. SongWave’s tactile presets have not been validated in a listening study.

## Voice, Beat and Both

Use **Feel → Voice / Beat / Both** independently of the output choice. Voice follows pitch and texture; Beat follows bass and percussion; Both blends the two. Both shares one FFT and does not load an additional model. The selected focus is kept when changing output. Light processing is used for Beat, Both and Voice with speakers. The existing AI Isolated option remains available only with Voice and Trackpad only; its model and inference code are unchanged. Authored file patterns use their own content, so the focus selector is disabled while one is attached.

In Both, a detected percussion attack briefly lowers the vocal layer, which returns smoothly over roughly a tenth of a second. A short, complementary tactile texture helps distinguish attacks that share a frequency with the vocal layer. These changes redistribute the existing output budget; they add no model, onset detector or lookahead. How clearly that contrast feels still needs listener feedback on real trackpads.

**Tools… → Fine Tune → Detail balance** makes detected mid/treble percussion more prominent and briefly lowers the bass rumble beneath it. It does not change EQ, beat timing or detection sensitivity. Voice passes through unchanged.

## Connection checks and retries

Listening help keeps trackpad, capture, selected source and pause status together. Capture and listening retries stay on that page during setup and keep normal haptics off. Choose **Run setup check** when you want another explicit sensation test. Recording permission alone never confirms a sensation. If music stops during the check, the status distinguishes earlier audio from current input.

**Retry listening** keeps a local file's position and your haptics-off choice. Local files do not need recording access, so their capture retry is unavailable. Diagnostics copy only categorical connection information and numeric app/system facts; they exclude titles, recordings, device names and personal paths. [Audit and screenshots](audits/connection-0.5.11.md).
