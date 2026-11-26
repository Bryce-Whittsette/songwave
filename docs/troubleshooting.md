# Help with SongWave

## macOS won't open the app

The public preview is ad hoc signed and has not been notarized by Apple. If you trust the release and choose to open it, try launching it once, then use **System Settings → Privacy & Security → Open Anyway**. Check that the app name is SongWave. [Apple explains this warning](https://support.apple.com/en-us/102445).

If you prefer, [build the source yourself](development.md). No Terminal command that disables macOS security checks is required.

## No vibration

1. Use a Mac with a Force Touch trackpad. The public download is for Apple silicon.
2. Open SongWave and select **Mac Audio**. The button says **Stop Mac Audio** while listening.
3. Open the sliders menu → **Playback Access** and check System Audio Recording access. In macOS, this may be under **Privacy & Security → Screen & System Audio Recording**. Reopen SongWave if macOS requests it.
4. Play a song, choose **Speakers + haptics**, and rest a finger lightly on the trackpad. Raise Intensity gradually.

Trackpad only follows vocals, so instrumental passages may be quiet. Isolated needs a brief model warmup. Some protected audio cannot be captured. Music detection also needs a moment when playback starts.

No song link, imported pattern, or file is needed for normal use.

## It asks for permission after an update

macOS may treat a replacement ad hoc preview as a new binary. Granting access to one preview does not guarantee authorization for a replacement. SongWave keeps setup preferences; it does not bypass macOS permissions. Developer ID signing and notarization are planned for a later release.

## The beat feels early or late

Open **Fine Tune** in Speakers + haptics. Leave **Match audio output timing** enabled, then adjust **Timing offset**. Positive values make haptics later; negative values reduce the automatic added delay. Bluetooth and external audio devices can have different delays. Real-time beat recognition and reported output latency are estimates.

## Song title or cover is missing

Open Spotify or Music, then use **Playback Access → Connect Spotify / Connect Apple Music** to allow optional player details. Audio routing does not require this connection. Other sources may show only the playing app.

## Talking videos vibrate

Speech and known call apps are filtered, but an instrumental video intro can sound like music. For YouTube, use **Set Up YouTube Filter** in the sliders menu. Chrome and Firefox are supported. Safari uses audio recognition. See the [guide](guide.md#music-detection).

## Keyboard light is faint or unavailable

Keyboard lighting is optional and only works on supported backlit keyboards. macOS and ambient brightness can affect it. SongWave restores the previous brightness when the effect stops.

## Report a problem

Use [the bug report form](https://github.com/Bryce-Whittsette/songwave/issues/new/choose). Include your Mac model, macOS version, SongWave version, source app and steps to reproduce. Never include private recordings, credentials, or personal listening logs.
