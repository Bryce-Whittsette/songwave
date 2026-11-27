# Help with SongWave

## macOS won't open the app

The public preview is ad hoc signed and has not been notarized by Apple. If you trust the release and choose to open it, try launching it once, then use **System Settings → Privacy & Security → Open Anyway**. Check that the app name is SongWave. [Apple explains this warning](https://support.apple.com/en-us/102445).

If you prefer, [build the source yourself](development.md). No Terminal command that disables macOS security checks is required.

## Connection status and a short test

Open **Listening help** in the player for trackpad, capture, selected-app and pause status. **Run setup check** shows music activity and offers an explicit short tap test. Confirm only if you felt the taps. **Copy diagnostics** excludes songs, personal paths and device names; paste it into a bug report only if you choose.

## No vibration

1. Use a Mac with a Force Touch trackpad. The public download is for Apple silicon.
2. Open SongWave and choose **Listen to Mac audio**. The button says **Stop listening** while listening.
3. Open **Settings → Listening Help** and check System Audio Recording access. In macOS, this may be under **Privacy & Security → Screen & System Audio Recording**. Reopen SongWave if macOS requests it.
4. Play a song, choose **Speakers + haptics**, and rest a finger lightly on the trackpad. Raise Intensity gradually.

Choose **Feel → Beat**, **Voice** or **Both** in either output. Voice can be quiet during instrumental passages. Isolated needs a brief model warmup. Some protected audio cannot be captured. Music detection also needs a moment when playback starts.

No song link, imported pattern, or file is needed for normal use.

## It asks for permission after an update

macOS may treat a replacement ad hoc preview as a new binary. Granting access to one preview does not guarantee authorization for a replacement. SongWave keeps setup preferences; it does not bypass macOS permissions. Developer ID signing and notarization are planned for a later release.

## The beat feels early or late

Open **Tools… → Sound → Fine Tune** in Speakers + haptics. Leave **Match audio output timing** enabled, then adjust **Timing offset**. Positive values make haptics later; negative values reduce the automatic added delay. Bluetooth and external audio devices can have different delays. Real-time beat recognition and reported output latency are estimates.

## Song title or cover is missing

Open Spotify or Music, then use **Listening Help → Player access… → Connect Spotify / Connect Apple Music** to allow optional player details. Audio routing does not require this connection. Other sources may show only the playing app.

## Talking videos vibrate

Speech and known call apps are filtered, but an instrumental video intro can sound like music. For YouTube, open **Settings → Effects → YouTube music filter**. Chrome and Firefox are supported. Safari uses audio recognition. See the [guide](guide.md#music-detection).

## Keyboard light is faint or unavailable

Keyboard lighting is optional and only works on supported backlit keyboards. macOS and ambient brightness can affect it. SongWave restores the previous brightness when the effect stops.

## Report a problem

Use [the bug report form](https://github.com/Bryce-Whittsette/songwave/issues/new/choose). Include your Mac model, macOS version, SongWave version, source app and steps to reproduce. Never include private recordings, credentials, or personal listening logs.
